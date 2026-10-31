#+build murk
#+private
package os

// The hosted Murk runtime's C ABI (MurkKernel kernel/user/os), which every
// Murk backend file of this package calls. Written 27 September 2026, when
// core:os on Murk became a backend of the common package in place of the
// standalone API of 23 September 2026. Results are 0 (or a count) or a
// negated murkkernel:user/fds Error (_Platform_Error).

foreign import murk "system:murk"

// murk_file_attributes's record (kernel/user/os attributes.odin).
Murk_Attributes :: struct {
	inode, size: u64,
	mode, flags, links, uid, gid, _: u32,
	times: [4]i64,
}
#assert(size_of(Murk_Attributes) == 72)

// murk_identity's record (kernel/user/os identity.odin).
Murk_Identity :: struct {
	uid, gid: u32,
	group_count: u32,
	umask: u32,
	groups: [16]u32,
}
#assert(size_of(Murk_Identity) == 80)

// murk_process_list's record (kernel/user/os process.odin).
Murk_Process_Record :: struct {
	id, parent, pages_used, pages_reserved, cpu_ns: u64,
	state, flags: u8,
	path_length: u16,
	_: u32,
	path: [256]u8,
}
#assert(size_of(Murk_Process_Record) == 304)

@(default_calling_convention = "c")
foreign murk {
	murk_write :: proc(fd: i32, data: [^]u8, size: int) -> int ---
	murk_read :: proc(fd: i32, data: [^]u8, size: int) -> int ---
	murk_exit :: proc(code: i32) -> ! ---
	murk_now_ns :: proc() -> u64 ---
	murk_initial_cwd :: proc(length: ^int) -> [^]u8 ---
	murk_file_open :: proc(path: [^]u8, length: int, options: u64) -> i64 ---
	murk_file_read :: proc(fd: i32, data: [^]u8, size: int) -> i64 ---
	murk_file_write :: proc(fd: i32, data: [^]u8, size: int) -> i64 ---
	murk_file_seek :: proc(fd: i32, offset: i64, whence: u64) -> i64 ---
	murk_file_close :: proc(fd: i32) -> i32 ---
	murk_file_stat :: proc(path: [^]u8, length: int, kind, size: ^u64) -> i32 ---
	murk_file_times :: proc(path: [^]u8, length: int, times: ^[4]i64) -> i32 ---
	murk_file_truncate :: proc(fd: i32, size: i64) -> i32 ---
	murk_file_sync :: proc(fd: i32) -> i32 ---
	murk_file_attributes :: proc(path: [^]u8, length: int, out: ^Murk_Attributes) -> i32 ---
	murk_file_link_attributes :: proc(path: [^]u8, length: int, out: ^Murk_Attributes) -> i32 ---
	murk_symlink :: proc(target: [^]u8, target_length: int, path: [^]u8, length: int) -> i32 ---
	murk_link :: proc(existing: [^]u8, existing_length: int, path: [^]u8, length: int) -> i32 ---
	murk_readlink :: proc(path: [^]u8, length: int, out: [^]u8, capacity: int) -> i64 ---
	murk_file_set_mode :: proc(path: [^]u8, length: int, mode: u32) -> i32 ---
	murk_file_set_owner :: proc(path: [^]u8, length: int, uid, gid: u32) -> i32 ---
	murk_mkdir :: proc(path: [^]u8, length: int) -> i32 ---
	murk_mkdir_mode :: proc(path: [^]u8, length: int, mode: u32) -> i32 ---
	murk_remove :: proc(path: [^]u8, length: int) -> i32 ---
	murk_rename :: proc(old_path: [^]u8, old_length: int, new_path: [^]u8, new_length: int) -> i32 ---
	murk_umask :: proc(set: i32, mask: u32, previous: ^u32) -> i32 ---
	murk_directory_open :: proc(path: [^]u8, length: int, token: ^u64) -> i32 ---
	murk_directory_next :: proc(token, cursor: u64, name: [^]u8, capacity: int, length, kind, next: ^u64) -> i32 ---
	murk_directory_close :: proc(token: u64) -> i32 ---
	murk_env_get :: proc(key: [^]u8, key_len: int, output: [^]u8, capacity: int) -> i64 ---
	murk_env_at :: proc(index: int, output: [^]u8, capacity: int) -> i64 ---
	murk_env_set :: proc(key: [^]u8, key_len: int, value: [^]u8, value_len: int) -> i32 ---
	murk_env_unset :: proc(key: [^]u8, key_len: int) -> i32 ---
	murk_identity :: proc(out: ^Murk_Identity) -> i32 ---
	murk_process_spawn :: proc(path: [^]u8, path_length: int, argv: [^]cstring, argc: int, envp: [^]cstring, envc: int,
		cwd: [^]u8, cwd_length: int, stdin_fd, stdout_fd, stderr_fd: i32, out_handle: ^u64) -> i32 ---
	murk_process_wait :: proc(handle, deadline_ns: u64, exit_kind: ^u32, exit_code: ^u64) -> i32 ---
	murk_process_kill :: proc(handle: u64) -> i32 ---
	murk_process_release :: proc(handle: u64) -> i32 ---
	murk_process_list :: proc(out: [^]Murk_Process_Record, capacity: int) -> i64 ---
	murk_process_self :: proc() -> u64 ---
	murk_terminal_info :: proc(fd: i32, role, number: ^u32) -> i32 ---
}

// The runtime's limits: a path (fd_service PATH_LIMIT with its leading "/"),
// a directory entry's name, an environment entry.
MURK_PATH_LIMIT :: 256
MURK_NAME_LIMIT :: 64
MURK_ENV_ENTRY_LIMIT :: 512

// vfs.Kind as murk_file_stat and murk_directory_next report it.
MURK_KIND_DIRECTORY :: 1
MURK_KIND_FILE :: 2
MURK_KIND_SYMLINK :: 3
// The longest symbolic-link target (MurkFS's).
MURK_LINK_TARGET_LIMIT :: 255

// murk_file_open's options: fd_service OpenPath's access and creation bits.
MURK_OPEN_READ :: u64(1)
MURK_OPEN_WRITE :: u64(2)
MURK_OPEN_APPEND :: u64(4)
MURK_OPEN_CREATE :: u64(1) << 8
MURK_OPEN_EXCLUSIVE :: u64(1) << 9
MURK_OPEN_TRUNCATE :: u64(1) << 10

// A negative runtime result as an Error; nil for zero or a count.
murk_error :: proc "contextless" (code: i64) -> Error {
	if code >= 0 {return nil}
	return _get_platform_error(_Platform_Error(i32(-code)))
}

// The working directory: murk_initial_cwd until set_working_directory.
murk_cwd: string
murk_cwd_owned: bool

murk_current_directory :: proc "contextless" () -> string {
	if murk_cwd != "" {return murk_cwd}
	length: int
	bytes := murk_initial_cwd(&length)
	return string(bytes[:length]) if bytes != nil && length > 0 else "/"
}

// `path` made absolute against the working directory and cleaned ("." and
// ".." resolved, repeated separators joined), in `buffer`; false when it
// does not fit.
murk_resolve :: proc "contextless" (path: string, buffer: []u8) -> (string, bool) {
	if len(buffer) == 0 {return "", false}
	at := 0
	push :: proc "contextless" (buffer: []u8, at: ^int, part: string) -> bool {
		if part == "" || part == "." {return true}
		if part == ".." {
			for at^ > 0 && buffer[at^-1] != '/' {at^ -= 1}
			if at^ > 0 {at^ -= 1}
			return true
		}
		if at^+1+len(part) > len(buffer) {return false}
		buffer[at^] = '/'
		copy(buffer[at^+1:], part)
		at^ += 1+len(part)
		return true
	}
	walk :: proc "contextless" (buffer: []u8, at: ^int, text: string) -> bool {
		start := 0
		for i in 0..=len(text) {
			if i == len(text) || text[i] == '/' {
				if !push(buffer, at, text[start:i]) {return false}
				start = i+1
			}
		}
		return true
	}
	if len(path) == 0 || path[0] != '/' {
		if !walk(buffer, &at, murk_current_directory()) {return "", false}
	}
	if !walk(buffer, &at, path) {return "", false}
	if at == 0 {
		buffer[0] = '/'
		at = 1
	}
	return string(buffer[:at]), true
}
