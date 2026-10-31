#+build murk
#+private
package os

// Pipes between programs are not yet offered to hosted programs on Murk
// (the file service has pipes; the runtime does not export them).
// Written 27 September 2026.

_pipe :: proc() -> (r, w: ^File, err: Error) {
	err = .Unsupported
	return
}

@(require_results)
_pipe_has_data :: proc(r: ^File) -> (ok: bool, err: Error) {
	err = .Unsupported
	return
}
