#+build murk
#+private
package os

// Files on Murk: descriptors of the program's namespace session, through the
// hosted runtime. Written 27 September 2026.
//
// A descriptor has no position of its own for read_at and write_at, so they
// move it and put it back. A directory opened read-only is held as a
// directory token (murk_directory_open) for read_directory. Times cannot be
// set (chtimes is Unsupported). Symbolic and hard links (3 October 2026) are
// MurkFS's; a symbolic link's target is stored as given, and the namespace
// follows links as Linux does.

import "base:runtime"
import "core:io"
import "core:time"

File_Impl :: struct {
	file:      File,
	name:      string, // the absolute path it was opened by
	fd:        i32,    // -1 for a directory
	directory: u64,    // murk_directory_open's token, or 0
	standard:  bool,   // 0, 1 or 2 as the program started with them
	allocator: runtime.Allocator,
}

_stdin := File{stream = {procedure = _file_stream_proc}}
_stdout := File{stream = {procedure = _file_stream_proc}}
_stderr := File{stream = {procedure = _file_stream_proc}}

@(init)
_standard_stream_init :: proc "contextless" () {
	new_std :: proc "contextless" (impl: ^File_Impl, fd: i32) -> ^File {
		impl.file.impl = impl
		impl.fd = fd
		impl.standard = true
		impl.allocator = runtime.nil_allocator()
		impl.file.stream = {data = impl, procedure = _file_stream_proc}
		return &impl.file
	}
	@(static) files: [3]File_Impl
	stdin = new_std(&files[0], 0)
	stdout = new_std(&files[1], 1)
	stderr = new_std(&files[2], 2)
}

_open :: proc(name: string, flags: File_Flags, perm: Permissions) -> (f: ^File, err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return nil, .Invalid_Path}
	// A new file takes the requested mode less the umask, as open(2); the
	// file service creates it with the default mode, so a new file with
	// another requested mode is changed once it exists.
	set_mode := .Create in flags && perm != Permissions_Default_File
	if set_mode && .Excl not_in flags {
		kind, size: u64
		set_mode = murk_file_stat(raw_data(path), len(path), &kind, &size) != 0
	}
	options: u64
	if .Read in flags {options |= MURK_OPEN_READ}
	if .Write in flags {options |= MURK_OPEN_WRITE}
	if .Append in flags {options |= MURK_OPEN_APPEND | MURK_OPEN_WRITE}
	if .Create in flags {options |= MURK_OPEN_CREATE}
	if .Excl in flags {options |= MURK_OPEN_EXCLUSIVE}
	if .Trunc in flags {options |= MURK_OPEN_TRUNCATE}
	if options & (MURK_OPEN_READ | MURK_OPEN_WRITE) == 0 {options |= MURK_OPEN_READ}
	number := murk_file_open(raw_data(path), len(path), options)
	if number < 0 {
		// A directory opens read-only, for reading its entries.
		if flags & {.Write, .Create, .Trunc, .Append} == {} {
			token: u64
			if murk_directory_open(raw_data(path), len(path), &token) == 0 {
				f, err = _new_impl(-1, token, path, file_allocator())
				if err != nil {_ = murk_directory_close(token)}
				return
			}
		}
		return nil, murk_error(number)
	}
	if set_mode {
		mask: u32
		if murk_umask(0, 0, &mask) == 0 {
			_ = murk_file_set_mode(raw_data(path), len(path), transmute(u32)perm &~ mask)
		}
	}
	f, err = _new_impl(i32(number), 0, path, file_allocator())
	if err != nil {_ = murk_file_close(i32(number))}
	return
}

_new_impl :: proc(fd: i32, directory: u64, name: string, allocator: runtime.Allocator) -> (f: ^File, err: Error) {
	impl := new(File_Impl, allocator) or_return
	defer if err != nil {free(impl, allocator)}
	impl.name = clone_string(name, allocator) or_return
	impl.file.impl = impl
	impl.fd = fd
	impl.directory = directory
	impl.allocator = allocator
	impl.file.stream = {data = impl, procedure = _file_stream_proc}
	return &impl.file, nil
}

// A descriptor number the program already holds (from a parent, or
// murk_file_open); it has no known path.
_new_file :: proc(handle: uintptr, name: string, allocator: runtime.Allocator) -> (f: ^File, err: Error) {
	if handle > uintptr(max(i32)) {return nil, .Invalid_File}
	return _new_impl(i32(handle), 0, name, allocator)
}

// The runtime cannot duplicate a descriptor; a named file is opened again.
_clone :: proc(f: ^File) -> (clone: ^File, err: Error) {
	if f == nil || f.impl == nil {return}
	impl := (^File_Impl)(f.impl)
	if impl.standard || impl.name == "" {return nil, .Unsupported}
	return _open(impl.name, {.Read} if impl.directory != 0 else {.Read, .Write}, Permissions_Default_File)
}

_destroy :: proc(f: ^File_Impl) -> Error {
	if f == nil || f.standard {return nil}
	a := f.allocator
	err0 := delete(f.name, a)
	err1 := free(f, a)
	err0 or_return
	return err1
}

_close :: proc(f: ^File_Impl) -> Error {
	if f == nil {return nil}
	status: i32
	if f.directory != 0 {
		status = murk_directory_close(f.directory)
	} else if f.fd >= 0 {
		status = murk_file_close(f.fd)
	}
	if _Platform_Error(-status) == .BAD_DESCRIPTOR {return murk_error(i64(status))}
	destroy_error := _destroy(f)
	if status < 0 {return murk_error(i64(status))}
	return destroy_error
}

_fd :: proc(f: ^File) -> uintptr {
	if f == nil || f.impl == nil {return ~uintptr(0)}
	impl := (^File_Impl)(f.impl)
	return ~uintptr(0) if impl.fd < 0 else uintptr(impl.fd)
}

// Any end the console serves: its own terminal or a pseudo-terminal's.
_is_tty :: proc "contextless" (f: ^File) -> bool {
	if f == nil || f.impl == nil {return false}
	impl := (^File_Impl)(f.impl)
	if impl.fd < 0 {return false}
	role, number: u32
	return murk_terminal_info(impl.fd, &role, &number) == 0 && role != 0
}

_name :: proc(f: ^File) -> string {
	return (^File_Impl)(f.impl).name if f != nil && f.impl != nil else ""
}

_seek :: proc(f: ^File_Impl, offset: i64, whence: io.Seek_From) -> (ret: i64, err: Error) {
	switch whence {
	case .Start, .Current, .End:
	case:
		return 0, .Invalid_Whence
	}
	if f.fd < 0 || f.standard {return 0, .Invalid_File}
	n := murk_file_seek(f.fd, offset, u64(whence))
	if n < 0 {
		if _Platform_Error(-n) == .INVALID {return 0, .Invalid_Offset}
		return 0, murk_error(n)
	}
	return n, nil
}

_read :: proc(f: ^File_Impl, p: []byte) -> (i64, Error) {
	if len(p) <= 0 {return 0, nil}
	if f.fd < 0 {return 0, .Invalid_File}
	n: i64
	if f.standard && f.fd == 0 {
		n = i64(murk_read(0, raw_data(p), len(p)))
		if n < 0 {return 0, .Invalid_File}
	} else {
		n = murk_file_read(f.fd, raw_data(p), len(p))
		if n < 0 {return 0, murk_error(n)}
	}
	return n, io.Error.EOF if n == 0 else nil
}

_read_at :: proc(f: ^File_Impl, p: []byte, offset: i64) -> (n: i64, err: Error) {
	if len(p) <= 0 {return 0, nil}
	if offset < 0 {return 0, .Invalid_Offset}
	previous := _seek(f, 0, .Current) or_return
	_seek(f, offset, .Start) or_return
	n, err = _read(f, p)
	_, restore := _seek(f, previous, .Start)
	if err == nil {err = restore}
	return
}

_write :: proc(f: ^File_Impl, p: []byte) -> (nt: i64, err: Error) {
	if f.fd < 0 {return 0, .Invalid_File}
	if f.standard && (f.fd == 1 || f.fd == 2) {
		// murk_write reports to the kernel log when the program has no
		// namespace session (an init-started service).
		for nt < i64(len(p)) {
			n := murk_write(f.fd, raw_data(p[nt:]), len(p)-int(nt))
			if n <= 0 {return nt, .Invalid_File}
			nt += i64(n)
		}
		return
	}
	for nt < i64(len(p)) {
		n := murk_file_write(f.fd, raw_data(p[nt:]), len(p)-int(nt))
		if n < 0 {return nt, murk_error(n)}
		if n == 0 {return nt, io.Error.Short_Write}
		nt += n
	}
	return
}

_write_at :: proc(f: ^File_Impl, p: []byte, offset: i64) -> (nt: i64, err: Error) {
	if offset < 0 {return 0, .Invalid_Offset}
	previous := _seek(f, 0, .Current) or_return
	_seek(f, offset, .Start) or_return
	nt, err = _write(f, p)
	_, restore := _seek(f, previous, .Start)
	if err == nil {err = restore}
	return
}

_file_size :: proc(f: ^File_Impl) -> (n: i64, err: Error) {
	if f.directory != 0 {return 0, .No_Size}
	previous := _seek(f, 0, .Current) or_return
	n = _seek(f, 0, .End) or_return
	_, err = _seek(f, previous, .Start)
	return
}

_sync :: proc(f: ^File) -> Error {
	if f == nil || f.impl == nil {return .Invalid_File}
	impl := (^File_Impl)(f.impl)
	if impl.fd < 0 || impl.standard {return nil}
	return murk_error(i64(murk_file_sync(impl.fd)))
}

_flush :: proc(f: ^File_Impl) -> Error {
	return nil
}

_truncate :: proc(f: ^File, size: i64) -> Error {
	if f == nil || f.impl == nil {return .Invalid_File}
	impl := (^File_Impl)(f.impl)
	if impl.fd < 0 || impl.standard {return .Invalid_File}
	return murk_error(i64(murk_file_truncate(impl.fd, size)))
}

_remove :: proc(name: string) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return .Invalid_Path}
	return murk_error(i64(murk_remove(raw_data(path), len(path))))
}

_rename :: proc(old_path, new_path: string) -> Error {
	from_buffer, to_buffer: [MURK_PATH_LIMIT]u8
	from, from_fits := murk_resolve(old_path, from_buffer[:])
	to, to_fits := murk_resolve(new_path, to_buffer[:])
	if !from_fits || !to_fits {return .Invalid_Path}
	return murk_error(i64(murk_rename(raw_data(from), len(from), raw_data(to), len(to))))
}

_link :: proc(old_name, new_name: string) -> Error {
	from_buffer, to_buffer: [MURK_PATH_LIMIT]u8
	from, from_fits := murk_resolve(old_name, from_buffer[:])
	to, to_fits := murk_resolve(new_name, to_buffer[:])
	if !from_fits || !to_fits {return .Invalid_Path}
	return murk_error(i64(murk_link(raw_data(from), len(from), raw_data(to), len(to))))
}

// old_name is the target, kept as given (relative to the link's directory
// when relative); new_name is the link.
_symlink :: proc(old_name, new_name: string) -> Error {
	if len(old_name) == 0 || len(old_name) > MURK_LINK_TARGET_LIMIT {return .Invalid_Path}
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(new_name, buffer[:])
	if !fits {return .Invalid_Path}
	return murk_error(i64(murk_symlink(raw_data(old_name), len(old_name), raw_data(path), len(path))))
}

_read_link :: proc(name: string, allocator: runtime.Allocator) -> (s: string, err: Error) {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return "", .Invalid_Path}
	target: [MURK_LINK_TARGET_LIMIT]u8
	length := murk_readlink(raw_data(path), len(path), raw_data(target[:]), len(target))
	if length < 0 {return "", murk_error(length)}
	return clone_string(string(target[:length]), allocator)
}

_chdir :: proc(name: string) -> Error {
	return _set_working_directory(name)
}

_fchdir :: proc(f: ^File) -> Error {
	if f == nil || f.impl == nil {return .Invalid_File}
	impl := (^File_Impl)(f.impl)
	if impl.directory == 0 {return .Invalid_Dir}
	return _set_working_directory(impl.name)
}

_chmod :: proc(name: string, mode: Permissions) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return .Invalid_Path}
	return murk_error(i64(murk_file_set_mode(raw_data(path), len(path), transmute(u32)mode)))
}

_fchmod :: proc(f: ^File, mode: Permissions) -> Error {
	if f == nil || f.impl == nil || _name(f) == "" {return .Invalid_File}
	return _chmod(_name(f), mode)
}

// -1 keeps the uid or the gid, as chown(2).
_chown :: proc(name: string, uid, gid: int) -> Error {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return .Invalid_Path}
	if uid < -1 || gid < -1 || uid > int(max(u32)) || gid > int(max(u32)) {return .Invalid_Callback}
	owner := max(u32) if uid == -1 else u32(uid)
	group := max(u32) if gid == -1 else u32(gid)
	return murk_error(i64(murk_file_set_owner(raw_data(path), len(path), owner, group)))
}

// MurkFS has no symbolic links, so every name is its own target.
_lchown :: proc(name: string, uid, gid: int) -> Error {
	return _chown(name, uid, gid)
}

_fchown :: proc(f: ^File, uid, gid: int) -> Error {
	if f == nil || f.impl == nil || _name(f) == "" {return .Invalid_File}
	return _chown(_name(f), uid, gid)
}

_chtimes :: proc(name: string, atime, mtime: time.Time) -> Error {
	return .Unsupported
}

_fchtimes :: proc(f: ^File, atime, mtime: time.Time) -> Error {
	return .Unsupported
}

_exists :: proc(name: string) -> bool {
	buffer: [MURK_PATH_LIMIT]u8
	path, fits := murk_resolve(name, buffer[:])
	if !fits {return false}
	kind, size: u64
	return murk_file_stat(raw_data(path), len(path), &kind, &size) == 0
}

@(private = "package")
_file_stream_proc :: proc(stream_data: rawptr, mode: File_Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From,
	allocator: runtime.Allocator) -> (n: i64, err: Error) {
	f := (^File_Impl)(stream_data)
	switch mode {
	case .Read:
		n, err = _read(f, p)
		return
	case .Read_At:
		n, err = _read_at(f, p, offset)
		return
	case .Write:
		n, err = _write(f, p)
		return
	case .Write_At:
		n, err = _write_at(f, p, offset)
		return
	case .Seek:
		n, err = _seek(f, offset, whence)
		return
	case .Size:
		n, err = _file_size(f)
		return
	case .Flush:
		err = _flush(f)
		return
	case .Close, .Destroy:
		err = _close(f)
		return
	case .Query:
		return io.query_utility({.Read, .Read_At, .Write, .Write_At, .Seek, .Size, .Flush, .Close, .Destroy, .Query})
	case .Fstat:
		err = file_stream_fstat_utility(f, p, allocator)
		return
	}
	return 0, .Unsupported
}
