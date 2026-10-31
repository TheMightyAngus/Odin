#+build murk
#+private
package os

// Directory listing on Murk: the entries of a directory token
// (murk_directory_next), each stated by its path. Written 27 September 2026.
// Modified 3 October 2026: an entry that is a symbolic link is listed as the
// link (lstat), as Linux's readdir and fstatat with AT_SYMLINK_NOFOLLOW do.

Read_Directory_Iterator_Impl :: struct {
	prev_fi: File_Info,
	cursor:  u64,
	done:    bool,
}

@(require_results)
_read_directory_iterator :: proc(it: ^Read_Directory_Iterator) -> (fi: File_Info, index: int, ok: bool) {
	if it.f == nil || it.f.impl == nil || it.impl.done {return}
	impl := (^File_Impl)(it.f.impl)
	for {
		name: [MURK_NAME_LIMIT]u8
		length, kind, next: u64
		result := murk_directory_next(impl.directory, it.impl.cursor, raw_data(name[:]), len(name), &length, &kind, &next)
		if result <= 0 {
			if result < 0 {read_directory_iterator_set_error(it, impl.name, murk_error(i64(result)))}
			it.impl.done = true
			return
		}
		it.impl.cursor = next
		entry := string(name[:length])
		if entry == "." || entry == ".." {continue}
		buffer: [MURK_PATH_LIMIT]u8
		separator := 0 if impl.name == "/" else 1
		if len(impl.name)+separator+len(entry) > len(buffer) {
			read_directory_iterator_set_error(it, entry, .Invalid_Path)
			continue
		}
		copy(buffer[:], impl.name)
		if separator == 1 {buffer[len(impl.name)] = '/'}
		copy(buffer[len(impl.name)+separator:], entry)
		path := string(buffer[:len(impl.name)+separator+len(entry)])
		file_info_delete(it.impl.prev_fi, file_allocator())
		info, err := murk_file_info(path, file_allocator(), false)
		if err != nil {
			// Listed but not statable (a name refused to this identity):
			// its name and kind are still known.
			read_directory_iterator_set_error(it, path, err)
			info = {}
			info.fullpath, _ = clone_string(path, file_allocator())
			_, info.name = split_path(info.fullpath)
			info.type = .Directory if kind == MURK_KIND_DIRECTORY else .Symlink if kind == MURK_KIND_SYMLINK else .Regular
		}
		it.impl.prev_fi = info
		index = it.index
		it.index += 1
		return info, index, true
	}
}

_read_directory_iterator_init :: proc(it: ^Read_Directory_Iterator, f: ^File) {
	it.impl.cursor = 0
	it.impl.done = false
	if f == nil || f.impl == nil {
		read_directory_iterator_set_error(it, "", .Invalid_File)
		return
	}
	if (^File_Impl)(f.impl).directory == 0 {
		read_directory_iterator_set_error(it, name(f), .Invalid_Dir)
	}
}

_read_directory_iterator_destroy :: proc(it: ^Read_Directory_Iterator) {
	if it == nil {return}
	file_info_delete(it.impl.prev_fi, file_allocator())
	it.impl.prev_fi = {}
}
