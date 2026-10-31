#+build murk
#+private
package os

// Processes on Murk: children of the process service, started from a snapshot
// of their executable (murk_process_spawn), and the identity the program
// runs as (murk_identity). Written 27 September 2026.
//
// A pid is the process service's ID (its record index below its generation);
// a handle is the same number while the caller holds the child. A nil
// standard stream in Process_Desc passes the caller's own, since a child
// cannot start without one; a nil environment passes the caller's (the
// common contract). process_wait releases the child once it has exited.
// There are no signals yet, so process_terminate ends the child as
// process_kill does.

import "base:runtime"
import "core:time"

// murk_process_wait's exit kinds (abi.Exit_Kind) and running result.
@(private = "file") MURK_EXITED :: 1
@(private = "file") MURK_FAULTED :: 2
@(private = "file") MURK_RUNNING :: 1

@(private = "file")
murk_who :: proc() -> (who: Murk_Identity, ok: bool) {
	return who, murk_identity(&who) == 0
}

_get_uid :: proc() -> int {
	who, ok := murk_who()
	return int(who.uid) if ok else -1
}

// There is no setuid on Murk: the effective ids are the real ones.
_get_euid :: proc() -> int {
	return _get_uid()
}

_get_gid :: proc() -> int {
	who, ok := murk_who()
	return int(who.gid) if ok else -1
}

_get_egid :: proc() -> int {
	return _get_gid()
}

_get_pid :: proc() -> int {
	return int(murk_process_self())
}

_get_ppid :: proc() -> int {
	record, ok := murk_process_record(murk_process_self())
	return int(record.parent) if ok else 0
}

// Hosted programs run one thread today.
_get_current_thread_id :: proc "contextless" () -> int {
	return 0
}

_get_processor_core_count :: proc() -> int {
	return 1
}

// The process service's record of the program `id`.
@(private = "file")
murk_process_record :: proc(id: u64) -> (record: Murk_Process_Record, ok: bool) {
	if id == 0 {return}
	records := make([]Murk_Process_Record, 64, file_allocator())
	defer delete(records, file_allocator())
	total := murk_process_list(raw_data(records), len(records))
	for total > i64(len(records)) {
		delete(records, file_allocator())
		records = make([]Murk_Process_Record, int(total), file_allocator())
		total = murk_process_list(raw_data(records), len(records))
	}
	if total < 0 {return}
	for entry in records[:total] {
		if entry.id == id {return entry, true}
	}
	return
}

@(private = "file")
murk_process_info :: proc(id: u64, selection: Process_Info_Fields, allocator: runtime.Allocator) -> (info: Process_Info, err: Error) {
	info.pid = int(id)
	record, found := murk_process_record(id)
	if !found {return info, .Not_Exist}
	if .Executable_Path in selection {
		info.executable_path = clone_string(string(record.path[:record.path_length]), allocator) or_return
		info.fields += {.Executable_Path}
	}
	if .PPid in selection {
		info.ppid = int(record.parent)
		info.fields += {.PPid}
	}
	return
}

_process_info_by_handle :: proc(process: Process, selection: Process_Info_Fields, allocator: runtime.Allocator) -> (info: Process_Info, err: Error) {
	return murk_process_info(u64(process.handle), selection, allocator)
}

_process_info_by_pid :: proc(pid: int, selection: Process_Info_Fields, allocator: runtime.Allocator) -> (info: Process_Info, err: Error) {
	if pid <= 0 {return {}, .Not_Exist}
	return murk_process_info(u64(pid), selection, allocator)
}

_current_process_info :: proc(selection: Process_Info_Fields, allocator: runtime.Allocator) -> (info: Process_Info, err: Error) {
	info.pid = _get_pid()
	if .PPid in selection {
		info.ppid = _get_ppid()
		info.fields += {.PPid}
	}
	if .Executable_Path in selection && len(runtime.args__.([]cstring)) > 0 {
		info.executable_path = _get_absolute_path(string(runtime.args__.([]cstring)[0]), allocator) or_return
		info.fields += {.Executable_Path}
	}
	if .Command_Args in selection {
		arguments := make([]string, len(runtime.args__.([]cstring)), allocator) or_return
		for argument, i in runtime.args__.([]cstring) {arguments[i] = clone_string(string(argument), allocator) or_return}
		info.command_args = arguments
		info.fields += {.Command_Args}
	}
	if .Environment in selection {
		info.environment = _environ(allocator) or_return
		info.fields += {.Environment}
	}
	if .Working_Dir in selection {
		info.working_dir = _get_working_directory(allocator) or_return
		info.fields += {.Working_Dir}
	}
	if .Username in selection {
		if user, found := _lookup_env_alloc("USER", allocator); found {
			info.username = user
			info.fields += {.Username}
		}
	}
	return
}

_process_list :: proc(allocator: runtime.Allocator) -> (list: []int, err: Error) {
	total := murk_process_list(nil, 0)
	if total < 0 {return nil, murk_error(total)}
	records := make([]Murk_Process_Record, int(total), file_allocator()) or_return
	defer delete(records, file_allocator())
	count := murk_process_list(raw_data(records), len(records))
	if count < 0 {return nil, murk_error(count)}
	list = make([]int, min(int(count), len(records)), allocator) or_return
	for &pid, i in list {pid = int(records[i].id)}
	return
}

// Only a child's own parent holds its handle: another program's pid opens
// nothing it may wait on.
_process_open :: proc(pid: int, flags: Process_Open_Flags) -> (process: Process, err: Error) {
	process.pid = pid
	if pid == _get_pid() {
		process.handle = uintptr(pid)
		return
	}
	return process, .Unsupported
}

_process_start :: proc(desc: Process_Desc) -> (process: Process, err: Error) {
	if len(desc.command) == 0 || desc.command[0] == "" {return {}, .Invalid_Command}
	allocator := file_allocator()
	program_buffer, directory_buffer: [MURK_PATH_LIMIT]u8
	program, program_fits := murk_resolve(desc.command[0], program_buffer[:])
	if !program_fits {return {}, .Invalid_Path}
	directory := ""
	if desc.working_dir != "" {
		fits: bool
		directory, fits = murk_resolve(desc.working_dir, directory_buffer[:])
		if !fits {return {}, .Invalid_Path}
	}
	arguments := make([]cstring, len(desc.command), allocator) or_return
	defer {
		for argument in arguments {delete(argument, allocator)}
		delete(arguments, allocator)
	}
	for argument, i in desc.command {arguments[i] = clone_to_cstring(argument, allocator) or_return}
	environment := desc.env
	inherited: []string
	defer {
		for entry in inherited {delete(entry, allocator)}
		delete(inherited, allocator)
	}
	if environment == nil {
		inherited = _environ(allocator) or_return
		environment = inherited
	}
	entries := make([]cstring, len(environment), allocator) or_return
	defer {
		for entry in entries {delete(entry, allocator)}
		delete(entries, allocator)
	}
	for entry, i in environment {entries[i] = clone_to_cstring(entry, allocator) or_return}
	stream :: proc(f: ^File) -> i32 {
		if f == nil || f.impl == nil {return -1}
		return (^File_Impl)(f.impl).fd
	}
	handle: u64
	status := murk_process_spawn(raw_data(program), len(program), raw_data(arguments), len(arguments),
		raw_data(entries), len(entries), raw_data(directory), len(directory),
		stream(desc.stdin), stream(desc.stdout), stream(desc.stderr), &handle)
	if status < 0 {
		if _Platform_Error(-status) == .INVALID {return {}, .Invalid_Command}
		return {}, murk_error(i64(status))
	}
	return {pid = int(handle), handle = uintptr(handle)}, nil
}

_process_wait :: proc(process: Process, timeout: time.Duration) -> (process_state: Process_State, err: Error) {
	process_state.pid = process.pid
	deadline := max(u64)
	if timeout >= 0 {
		now := murk_now_ns()
		span := u64(timeout)
		deadline = now+span if span <= max(u64)-now else max(u64)
	}
	kind: u32
	code: u64
	status := murk_process_wait(u64(process.handle), deadline, &kind, &code)
	if status == MURK_RUNNING {return process_state, .Timeout}
	if status < 0 {return process_state, murk_error(i64(status))}
	process_state.exited = true
	process_state.exit_code = int(i32(u32(code)))
	process_state.success = kind == MURK_EXITED && code == 0
	if kind == MURK_FAULTED {process_state.exit_code = int(code)}
	_ = murk_process_release(u64(process.handle))
	return
}

_process_kill :: proc(process: Process) -> (err: Error) {
	return murk_error(i64(murk_process_kill(u64(process.handle))))
}

_process_terminate :: proc(process: Process) -> (err: Error) {
	return _process_kill(process)
}
