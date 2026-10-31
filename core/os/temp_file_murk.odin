#+build murk
#+private
package os

// A program's temporary directory: $TMPDIR, else /tmp, which the namespace
// makes each account's own /tmp/UID (MurkKernel DESIGN.md, "File ownership
// and permissions"). Written 27 September 2026.

import "base:runtime"

_temp_dir :: proc(allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	buffer: [MURK_ENV_ENTRY_LIMIT]u8
	if count := murk_env_get(raw_data(string("TMPDIR")), len("TMPDIR"), raw_data(buffer[:]), len(buffer)); count > 0 {
		return clone_string(string(buffer[:count]), allocator)
	}
	return clone_string("/tmp", allocator)
}
