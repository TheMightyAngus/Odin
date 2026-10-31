#+build murk
#+private
package os

// Paths on Murk: POSIX paths from the namespace root; the working directory
// is the program's own (murk_initial_cwd until changed). Written 27
// September 2026.

import "base:runtime"

_Path_Separator        :: '/'
_Path_Separator_String :: "/"
_Path_List_Separator   :: ':'

_is_path_separator :: proc(c: byte) -> bool {
	return c == _Path_Separator
}

_mkdir :: proc(path: string, perm: Permissions) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	full, fits := murk_resolve(path, buffer[:])
	if !fits {return .Invalid_Path}
	return murk_error(i64(murk_mkdir_mode(raw_data(full), len(full), transmute(u32)perm & 0o7777)))
}

_mkdir_all :: proc(path: string, perm: Permissions) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	full, fits := murk_resolve(path, buffer[:])
	if !fits {return .Invalid_Path}
	for i in 1..=len(full) {
		if i < len(full) && full[i] != '/' {continue}
		part := full[:i]
		status := murk_mkdir_mode(raw_data(part), len(part), transmute(u32)perm & 0o7777)
		if status == 0 {continue}
		err := murk_error(i64(status))
		if err != .Exist {return err}
		kind, size: u64
		if murk_file_stat(raw_data(part), len(part), &kind, &size) != 0 || kind != MURK_KIND_DIRECTORY {
			return .Invalid_Dir if i == len(full) else err
		}
	}
	return nil
}

_remove_all :: proc(path: string) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	full, fits := murk_resolve(path, buffer[:])
	if !fits {return .Invalid_Path}
	return murk_remove_tree(full)
}

// Removes `path` and, for a directory, everything under it first.
@(private = "file")
murk_remove_tree :: proc(path: string) -> Error {
	kind, size: u64
	if status := murk_file_stat(raw_data(path), len(path), &kind, &size); status != 0 {
		err := murk_error(i64(status))
		return nil if err == .Not_Exist else err
	}
	if kind == MURK_KIND_DIRECTORY {
		token: u64
		if status := murk_directory_open(raw_data(path), len(path), &token); status != 0 {return murk_error(i64(status))}
		// Entries are removed as they are listed, so each pass starts over.
		for {
			name: [MURK_NAME_LIMIT]u8
			length, entry_kind, next: u64
			result := murk_directory_next(token, 0, raw_data(name[:]), len(name), &length, &entry_kind, &next)
			if result < 0 {
				_ = murk_directory_close(token)
				return murk_error(i64(result))
			}
			if result == 0 {break}
			entry := string(name[:length])
			buffer: [MURK_PATH_LIMIT]u8
			separator := 0 if path == "/" else 1
			if len(path)+separator+len(entry) > len(buffer) {
				_ = murk_directory_close(token)
				return .Invalid_Path
			}
			copy(buffer[:], path)
			if separator == 1 {buffer[len(path)] = '/'}
			copy(buffer[len(path)+separator:], entry)
			if err := murk_remove_tree(string(buffer[:len(path)+separator+len(entry)])); err != nil {
				_ = murk_directory_close(token)
				return err
			}
		}
		_ = murk_directory_close(token)
	}
	return murk_error(i64(murk_remove(raw_data(path), len(path))))
}

_get_working_directory :: proc(allocator: runtime.Allocator) -> (dir: string, err: Error) {
	return clone_string(murk_current_directory(), allocator)
}

_set_working_directory :: proc(dir: string) -> (err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	full, fits := murk_resolve(dir, buffer[:])
	if !fits {return .Invalid_Path}
	token: u64
	if status := murk_directory_open(raw_data(full), len(full), &token); status != 0 {return murk_error(i64(status))}
	_ = murk_directory_close(token)
	owned := clone_string(full, heap_allocator()) or_return
	if murk_cwd_owned {delete(murk_cwd, heap_allocator())}
	murk_cwd, murk_cwd_owned = owned, true
	return nil
}

// A program's argv[0] is always its absolute path on Murk.
_get_executable_path :: proc(allocator: runtime.Allocator) -> (path: string, err: Error) {
	if len(runtime.args__.([]cstring)) == 0 {return "", .Invalid_Path}
	return _get_absolute_path(string(runtime.args__.([]cstring)[0]), allocator)
}

_get_absolute_path :: proc(path: string, allocator: runtime.Allocator) -> (absolute_path: string, err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	full, fits := murk_resolve(path, buffer[:])
	if !fits {return "", .Invalid_Path}
	return clone_string(full, allocator)
}
