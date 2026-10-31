#+build murk
#+private
package runtime

foreign import murk "system:murk"
foreign murk {
	@(link_name="murk_write") murk_write :: proc "c" (fd: i32, data: [^]u8, size: int) -> int ---
	@(link_name="murk_exit") murk_exit :: proc "c" (code: i32) -> ! ---
	// The kernel's RDRAND source through the hosted runtime (MurkKernel
	// kernel/user/os random.odin; 3 October 2026).
	@(link_name="murk_random_bytes") murk_random_bytes :: proc "c" (out: [^]u8, length: int) -> i32 ---
}

_HAS_RAND_BYTES :: true

_rand_bytes :: proc "contextless" (dst: []byte) {
	if murk_random_bytes(raw_data(dst), len(dst)) != 0 {
		panic_contextless("base/runtime: the Murk entropy source failed")
	}
}

_stderr_write :: proc "contextless" (data: []byte) -> (int, _OS_Errno) {
	count := murk_write(2, raw_data(data), len(data))
	return count, 0 if count >= 0 else _OS_Errno(-count)
}

_exit :: proc "contextless" (code: int) -> ! {
	murk_exit(i32(code))
}
