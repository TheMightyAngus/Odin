#+build murk
#+private
package runtime

foreign import murk_heap "system:murk"
foreign murk_heap {
	@(link_name="murk_alloc") murk_alloc :: proc "c" (size: int, zero: bool) -> rawptr ---
	@(link_name="murk_resize") murk_resize :: proc "c" (memory: rawptr, size: int) -> rawptr ---
	@(link_name="murk_free") murk_free :: proc "c" (memory: rawptr) ---
}

_heap_alloc :: proc "contextless" (size: int, zero_memory := true) -> rawptr {
	return murk_alloc(size, zero_memory)
}

_heap_resize :: proc "contextless" (ptr: rawptr, new_size: int) -> rawptr {
	return murk_resize(ptr, new_size)
}

_heap_free :: proc "contextless" (ptr: rawptr) {
	murk_free(ptr)
}
