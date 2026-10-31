#+build murk
#+private
package sync

import "core:time"

// The first hosted profile has one thread per program. A contended futex
// yields until its observed value changes; later thread support can replace it.
_futex_wait :: proc "contextless" (f: ^Futex, expected: u32) -> bool {
	for u32(atomic_load_explicit(f, .Acquire)) == expected {}
	return true
}

_futex_wait_with_timeout :: proc "contextless" (f: ^Futex, expected: u32, duration: time.Duration) -> bool {
	return u32(atomic_load_explicit(f, .Acquire)) != expected
}

_futex_signal :: proc "contextless" (f: ^Futex) {}
_futex_broadcast :: proc "contextless" (f: ^Futex) {}
_current_thread_id :: proc "contextless" () -> int {return 1}
