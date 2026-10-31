#+build murk
// Murk does not expose topology, memory totals or an OS release query yet.
// Written 23 September 2026.
package sysinfo

import "base:runtime"

@(private)
_cpu_core_count :: proc "contextless" () -> (physical,logical: int,ok: bool) {return 0,0,false}

@(private)
_ram_stats :: proc "contextless" () -> (total_ram,free_ram,total_swap,free_swap:i64,ok:bool) {
	return 0,0,0,0,false
}

@(private)
_os_version :: proc(allocator:runtime.Allocator,loc:=#caller_location) -> (result:OS_Version,ok:bool) {
	return {},false
}
