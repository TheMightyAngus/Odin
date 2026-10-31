#+build murk
package net

// Names on Murk: the network service's resolver, through the hosted runtime
// (MurkKernel kernel/user/os net.odin; written 3 October 2026). Modified 7
// October 2026 (slice 264): A and AAAA records, the service's answer split by
// family (an IPv4 address comes as ::ffff:a.b.c.d), each family in the order
// the service gave, which puts the one this host can use first.

import "core:strings"

foreign import murk "system:murk"

@(default_calling_convention = "c", private = "file")
foreign murk {
	murk_net_resolve :: proc(name: [^]u8, length: int, addresses: [^][16]u8, capacity: int, count: ^int) -> i32 ---
}

@(private)
_get_dns_records_os :: proc(hostname: string, type: DNS_Record_Type, allocator := context.allocator) -> (records: []DNS_Record, err: DNS_Error) {
	if type != .IP4 && type != .IP6 {return}
	if len(hostname) == 0 || len(hostname) > 253 {return nil, .Invalid_Hostname_Error}
	addresses: [8][16]u8
	count: int
	switch murk_net_resolve(raw_data(hostname), len(hostname), &addresses[0], len(addresses), &count) {
	case 0:
	case 4: return nil, nil // not found
	case 1: return nil, .Invalid_Hostname_Error
	case -1, 2: return nil, .Connection_Error
	case: return nil, .Server_Error
	}
	found := make([dynamic]DNS_Record, 0, count, allocator) or_else nil
	for address in addresses[:count] {
		mapped := true
		for i in 0..<10 {if address[i] != 0 {mapped = false}}
		mapped = mapped && address[10] == 0xff && address[11] == 0xff
		if mapped && type == .IP4 {
			append(&found, DNS_Record_IP4{base = {record_name = strings.clone(hostname, allocator)},
				address = IP4_Address{address[12], address[13], address[14], address[15]}})
		} else if !mapped && type == .IP6 {
			append(&found, DNS_Record_IP6{base = {record_name = strings.clone(hostname, allocator)}, address = transmute(IP6_Address)address})
		}
	}
	return found[:], nil
}
