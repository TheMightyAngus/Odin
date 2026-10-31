#+build murk
#+private
package os

import "base:runtime"

// The hosted runtime's heap (MurkKernel kernel/user/os heap.odin).
_heap_allocator_proc :: runtime.heap_allocator_proc
