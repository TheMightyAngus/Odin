#+private
#+build murk
package time

import "base:runtime"

foreign import murk_clock "system:murk"
foreign murk_clock {
	@(link_name="murk_now_ns") murk_now_ns :: proc "c" () -> u64 ---
	@(link_name="murk_sleep_until") murk_sleep_until :: proc "c" (deadline_ns: u64) ---
	@(link_name="murk_wall_now_ns") murk_wall_now_ns :: proc "c" () -> i64 ---
}

_IS_SUPPORTED :: true

_now :: proc "contextless" () -> Time {
	wall := murk_wall_now_ns()
	if wall < 0 {runtime.exit(99)}
	return Time{wall}
}

_sleep :: proc "contextless" (d: Duration) {
	if d <= 0 {return}
	start := murk_now_ns()
	span := u64(d)
	deadline := start+span
	if deadline < start {deadline = max(u64)}
	murk_sleep_until(deadline)
}

_tick_now :: proc "contextless" () -> Tick {
	return Tick{i64(murk_now_ns())}
}

_yield :: proc "contextless" () {
	murk_sleep_until(murk_now_ns())
}
