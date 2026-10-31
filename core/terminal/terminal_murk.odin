#+build murk
// Hosted standard streams are namespace backed console streams.
// Written 23 September 2026. Modified 27 September 2026: a terminal is any
// descriptor the console serves (core:os is_tty).
package terminal

import "core:os"
import "base:runtime"

_is_terminal :: proc "contextless" (file:^os.File) -> bool {
	return os.is_tty(file)
}

_init_terminal :: proc "contextless" () {
	context=runtime.default_context()
	color_depth=get_environment_color()
	is_dumb=get_is_dumb()
}

_fini_terminal :: proc "contextless" () {}
