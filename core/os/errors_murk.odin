#+build murk
#+private
package os

// Murk's platform errors are murkkernel:user/fds Error values, which the
// hosted runtime returns negated. Written 27 September 2026.
_Platform_Error :: enum i32 {
	NONE           = 0,
	INVALID        = 1,
	BAD_DESCRIPTOR = 2,
	DENIED         = 3,
	NO_CAPACITY    = 4,
	STALE          = 5,
	RANGE          = 6,
	BUSY           = 7,
	EXHAUSTED      = 8,
	CORRUPT        = 9,
	WOULD_BLOCK    = 10,
	BROKEN_PIPE    = 11,
	IO             = 12,
	LOOP           = 13, // more symbolic links than may be followed (ELOOP)
}

@(rodata)
_murk_error_strings := [_Platform_Error]string{
	.NONE           = "",
	.INVALID        = "Invalid argument",
	.BAD_DESCRIPTOR = "Bad file descriptor",
	.DENIED         = "Permission denied",
	.NO_CAPACITY    = "No space left or too many open files",
	.STALE          = "No such file or directory",
	.RANGE          = "Result out of range",
	.BUSY           = "File exists or resource busy",
	.EXHAUSTED      = "Resource exhausted",
	.CORRUPT        = "Corrupt data",
	.WOULD_BLOCK    = "Resource temporarily unavailable",
	.BROKEN_PIPE    = "Broken pipe",
	.IO             = "Input/output error",
	.LOOP           = "Too many levels of symbolic links",
}

_error_string :: proc(errno: i32) -> string {
	if errno >= 0 && errno <= i32(max(_Platform_Error)) {
		return _murk_error_strings[_Platform_Error(errno)]
	}
	return "Unknown Error"
}

// The file service reports a name that is not there as Stale, and creating
// or renaming onto an existing name as Busy (Linux's EEXIST).
_get_platform_error :: proc "contextless" (errno: _Platform_Error) -> Error {
	#partial switch errno {
	case .NONE:
		return nil
	case .DENIED:
		return .Permission_Denied
	case .STALE:
		return .Not_Exist
	case .BUSY:
		return .Exist
	case .BAD_DESCRIPTOR:
		return .Invalid_File
	case .BROKEN_PIPE:
		return .Broken_Pipe
	}
	return Platform_Error(errno)
}
