#+build murk
#+private
package os

// The environment lives in the program's namespace session (fd_service's
// environment operations); these reach it through the hosted runtime.
// Written 27 September 2026.

import "base:runtime"

@(require_results)
_lookup_env_alloc :: proc(key: string, allocator: runtime.Allocator) -> (value: string, found: bool) {
	if len(key) == 0 {return}
	buffer: [MURK_ENV_ENTRY_LIMIT]u8
	count := murk_env_get(raw_data(key), len(key), raw_data(buffer[:]), len(buffer))
	if count < 0 {return}
	cloned, clone_error := clone_string(string(buffer[:count]), allocator)
	return cloned, clone_error == nil
}

_lookup_env_buf :: proc(buf: []u8, key: string) -> (value: string, error: Error) {
	if len(key) == 0 {return "", .Env_Var_Not_Found}
	count := murk_env_get(raw_data(key), len(key), raw_data(buf), len(buf))
	switch {
	case count >= 0:
		return string(buf[:count]), nil
	case _Platform_Error(-count) == .STALE:
		return "", .Env_Var_Not_Found
	case _Platform_Error(-count) == .RANGE:
		return "", .Short_Buffer
	}
	return "", murk_error(count)
}

_lookup_env :: proc{_lookup_env_alloc, _lookup_env_buf}

@(require_results)
_set_env :: proc(key, value: string) -> (err: Error) {
	if len(key) == 0 {return .Invalid_Path}
	return murk_error(i64(murk_env_set(raw_data(key), len(key), raw_data(value), len(value))))
}

@(require_results)
_unset_env :: proc(key: string) -> bool {
	if len(key) == 0 {return false}
	status := murk_env_unset(raw_data(key), len(key))
	return status == 0 || _Platform_Error(-status) == .STALE
}

_clear_env :: proc() {
	entry: [MURK_ENV_ENTRY_LIMIT]u8
	for {
		count := murk_env_at(0, raw_data(entry[:]), len(entry))
		if count <= 0 {return}
		text := string(entry[:count])
		key := text
		for i in 0..<len(text) {
			if text[i] == '=' {key = text[:i]; break}
		}
		if !_unset_env(key) {return}
	}
}

@(require_results)
_environ :: proc(allocator: runtime.Allocator) -> (environ: []string, err: Error) {
	entries := make([dynamic]string, 0, 16, allocator) or_return
	defer if err != nil {
		for entry in entries {delete(entry, allocator)}
		delete(entries)
	}
	entry: [MURK_ENV_ENTRY_LIMIT]u8
	for index := 0; ; index += 1 {
		count := murk_env_at(index, raw_data(entry[:]), len(entry))
		if count < 0 {
			// Past the last entry is Stale; anything else is a failure.
			if _Platform_Error(-count) != .STALE {err = murk_error(count)}
			break
		}
		append(&entries, clone_string(string(entry[:count]), allocator) or_return) or_return
	}
	if err != nil {return}
	return entries[:], nil
}
