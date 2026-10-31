#+build murk
#+private
package os

// File attributes on Murk (murk_file_attributes): the type and permission
// bits of the Linux st_mode MurkFS and the RAM namespace keep, and the four
// file times. Written 27 September 2026.

import "base:runtime"
import "core:time"

// st_mode's type field, shifted down twelve bits.
@(private = "file")
murk_file_type :: proc "contextless" (mode: u32) -> File_Type {
	switch (mode >> 12) & 0xf {
	case 1: return .Named_Pipe
	case 2: return .Character_Device
	case 4: return .Directory
	case 6: return .Block_Device
	case 8: return .Regular
	case 10: return .Symlink
	case 12: return .Socket
	}
	return .Undetermined
}

// The attributes of an absolute `path`, as File_Info, with `fullpath` a copy:
// of what a final symbolic link names, or with follow false of the link
// itself (3 October 2026).
murk_file_info :: proc(path: string, allocator: runtime.Allocator, follow := true) -> (fi: File_Info, err: Error) {
	record: Murk_Attributes
	status: i32
	if follow {
		status = murk_file_attributes(raw_data(path), len(path), &record)
	} else {
		status = murk_file_link_attributes(raw_data(path), len(path), &record)
	}
	if status != 0 {
		// A name the console serves (/dev/console, /dev/ptmx) has a kind
		// and size but no record of attributes.
		kind, size: u64
		if murk_file_stat(raw_data(path), len(path), &kind, &size) != 0 {return {}, murk_error(i64(status))}
		record = {size = size, mode = 0o040755 if kind == MURK_KIND_DIRECTORY else 0o020620}
	}
	if record.size > u64(max(i64)) {return {}, Platform_Error(.CORRUPT)}
	fi.fullpath = clone_string(path, allocator) or_return
	_, fi.name = split_path(fi.fullpath)
	fi.inode = u128(record.inode)
	fi.size = i64(record.size)
	fi.type = murk_file_type(record.mode)
	fi.mode = transmute(Permissions)(record.mode & 0o777)
	fi.access_time = time.Time{record.times[0]}
	fi.modification_time = time.Time{record.times[1]}
	fi.creation_time = time.Time{record.times[3]}
	return
}

_fstat :: proc(f: ^File, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	if f == nil || f.impl == nil {return {}, .Invalid_File}
	impl := (^File_Impl)(f.impl)
	if impl.name == "" {
		// A descriptor with no known path (a standard stream).
		fi.type = .Character_Device if _is_tty(f) else .Undetermined
		return
	}
	return murk_file_info(impl.name, allocator)
}

_stat :: proc(name: string, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return {}, .Invalid_Path}
	return murk_file_info(path, allocator)
}

// A symbolic link's own attributes, not its target's (3 October 2026).
_lstat :: proc(name: string, allocator: runtime.Allocator) -> (fi: File_Info, err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return {}, .Invalid_Path}
	return murk_file_info(path, allocator, false)
}

_same_file :: proc(fi1, fi2: File_Info) -> bool {
	return fi1.fullpath == fi2.fullpath
}

_is_reserved_name :: proc(path: string) -> bool {
	return false
}
