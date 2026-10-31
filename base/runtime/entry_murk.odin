#+build murk
#+private
package runtime

import "base:intrinsics"

// The freestanding Murk personality calls this after establishing its
// namespace session and heap. The compiler still generates the program entry.
@(link_name="murk_runtime_run", linkage="strong", require)
murk_runtime_run :: proc "c" (argc: i32, argv: [^]cstring) -> ! {
	args__ = argv[:argc]
	context = default_context()
	_startup_runtime()
	intrinsics.__entry_point()
	_cleanup_runtime()
	_exit(0)
}
