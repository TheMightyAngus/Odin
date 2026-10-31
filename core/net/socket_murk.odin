#+build murk
#+private
package net

// Sockets on Murk, through the hosted runtime's murk_net_* calls to the
// network service (MurkKernel kernel/user/os net.odin; written 3 October
// 2026). A program needs the "net" grant in its manifest [program] record.
//
// A Socket here is a slot in this table, not the service's number: a UDP
// socket exists, unbound, before the service has one (bind, or the first
// send, opens it), as `make_unbound_udp_socket` expects. TCP and UDP over
// IPv4; 127.0.0.0/8 stays on the machine. A non-blocking socket only looks
// (no wait); the receive and send timeouts are kept here and given to each
// request. Not yet: one-way shutdown, broadcast.
//
// Modified 18 October 2026: preserve the requested TCP listener address.
// Modified 7 October 2026 (slice 264): IPv6. The runtime's addresses are
// sixteen bytes (netclient.Address: IPv6, or IPv4 as ::ffff:a.b.c.d), a socket
// takes either family, as a dual-stack socket does, and a listener or bound
// socket takes IPv4 and IPv6 alike; ::1 stays on the machine.

foreign import murk "system:murk"

@(default_calling_convention = "c")
foreign murk {
	murk_socket_shutdown :: proc(number: i32, directions: u32) -> i32 ---
	murk_socket_keepalive :: proc(number: i32, idle_s, interval_s, probes: u32) -> i32 ---
	murk_net_connect :: proc(address: ^[16]u8, port: u16, wait_ms: u32, socket: ^u32) -> i32 ---
	murk_net_listen_at :: proc(address: ^[16]u8, port: u16, backlog: i32, socket: ^u32) -> i32 ---
	murk_net_accept :: proc(listener: u32, wait_ms: u32, socket: ^u32, address: ^[16]u8, port: ^u16) -> i32 ---
	murk_net_send :: proc(socket: u32, data: [^]u8, length: int, sent: ^int) -> i32 ---
	murk_net_receive :: proc(socket: u32, buffer: [^]u8, capacity: int, wait_ms: u32, received: ^int, eof: ^bool) -> i32 ---
	murk_net_close :: proc(socket: u32) -> i32 ---
	murk_net_udp_open_at :: proc(local: ^[16]u8, port: u16, socket: ^u32, bound: ^u16) -> i32 ---
	murk_net_udp_send :: proc(socket: u32, address: ^[16]u8, port: u16, data: [^]u8, length: int) -> i32 ---
	murk_net_udp_receive :: proc(socket: u32, buffer: [^]u8, capacity: int, wait_ms: u32, received: ^int, address: ^[16]u8, port: ^u16) -> i32 ---
}

// murkkernel:user/netclient Status.
MURK_OK :: 0
MURK_INVALID :: 1
MURK_DOWN :: 2
MURK_TIMEOUT :: 3
MURK_REFUSED :: 7
MURK_RESET :: 8
MURK_CLOSED :: 9
MURK_IN_USE :: 10
MURK_NO_ROOM :: 11
MURK_HOP_LIMIT :: 13
MURK_TOO_LARGE :: 14
MURK_WAIT_FOREVER :: max(u32)
// The most one datagram carries (netclient.MAX_DATAGRAM).
MURK_MAX_DATAGRAM :: 1472

_SOCKET_OPTION_BROADCAST                 :: 1
_SOCKET_OPTION_REUSE_ADDRESS             :: 2
_SOCKET_OPTION_KEEP_ALIVE                :: 3
_SOCKET_OPTION_OUT_OF_BOUNDS_DATA_INLINE :: 4
_SOCKET_OPTION_LINGER                    :: 5
_SOCKET_OPTION_RECEIVE_BUFFER_SIZE       :: 6
_SOCKET_OPTION_SEND_BUFFER_SIZE          :: 7
_SOCKET_OPTION_RECEIVE_TIMEOUT           :: 8
_SOCKET_OPTION_SEND_TIMEOUT              :: 9

_SOCKET_OPTION_TCP_NODELAY :: 10

_SOCKET_OPTION_USE_LOOPBACK              :: 11
_SOCKET_OPTION_REUSE_PORT                :: 12
_SOCKET_OPTION_NO_SIGPIPE_FROM_EPIPE     :: 13
_SOCKET_OPTION_REUSE_PORT_LOAD_BALANCING :: 14

_SOCKET_OPTION_EXCLUSIVE_ADDR_USE :: 15
_SOCKET_OPTION_CONDITIONAL_ACCEPT :: 16
_SOCKET_OPTION_DONT_LINGER        :: 17

_SHUTDOWN_MANNER_RECEIVE :: 0
_SHUTDOWN_MANNER_SEND    :: 1
_SHUTDOWN_MANNER_BOTH    :: 2

Murk_Socket_Kind :: enum u8 {Free, TCP, UDP}

Murk_Socket :: struct {
	kind: Murk_Socket_Kind,
	// The service's socket, once there is one.
	service: u32,
	opened: bool,
	non_blocking: bool,
	receive_ms, send_ms: u32,
	local_port: int,
	local_endpoint: Endpoint,
	peer: Endpoint,
	// Created for IPv6: only the address a bound endpoint reports.
	v6: bool,
}

// Slot 0 is never used, so a zero Socket names nothing.
@(private = "file")
murk_sockets: [256]Murk_Socket

@(private = "file")
new_entry :: proc(kind: Murk_Socket_Kind) -> (int, ^Murk_Socket) {
	for i in 1..<len(murk_sockets) {
		entry := &murk_sockets[i]
		if entry.kind != .Free {continue}
		entry^ = {kind = kind, receive_ms = MURK_WAIT_FOREVER, send_ms = MURK_WAIT_FOREVER}
		return i, entry
	}
	return 0, nil
}

@(private = "file")
entry_of :: proc(s: Any_Socket) -> ^Murk_Socket {
	index: i64
	switch v in s {
	case TCP_Socket: index = i64(v)
	case UDP_Socket: index = i64(v)
	}
	if index <= 0 || index >= len(murk_sockets) || murk_sockets[index].kind == .Free {return nil}
	return &murk_sockets[index]
}

// The runtime's sixteen-byte form of an endpoint's address: an IPv4 one is
// ::ffff:a.b.c.d.
@(private = "file")
address_of :: proc(endpoint: Endpoint) -> ([16]u8, bool) {
	switch address in endpoint.address {
	case IP4_Address: return {10 = 0xff, 11 = 0xff, 12 = address[0], 13 = address[1], 14 = address[2], 15 = address[3]}, true
	case IP6_Address: return transmute([16]u8)address, true
	}
	return {}, false
}

// The endpoint a sixteen-byte address and a port name.
@(private = "file")
endpoint_of :: proc(address: [16]u8, port: int) -> Endpoint {
	mapped := true
	for i in 0..<10 {if address[i] != 0 {mapped = false}}
	if mapped && address[10] == 0xff && address[11] == 0xff {
		return {address = IP4_Address{address[12], address[13], address[14], address[15]}, port = port}
	}
	return {address = transmute(IP6_Address)address, port = port}
}

// How long a request on `entry` may wait: nothing when non-blocking.
@(private = "file")
wait_of :: proc(entry: ^Murk_Socket, timeout_ms: u32) -> u32 {
	return 0 if entry.non_blocking else timeout_ms
}

_dial_tcp_from_endpoint :: proc(endpoint: Endpoint, options := DEFAULT_TCP_OPTIONS) -> (sock: TCP_Socket, err: Network_Error) {
	address, ok := address_of(endpoint)
	if !ok || endpoint.port <= 0 || endpoint.port > 65535 {
		err = Dial_Error.Invalid_Argument if ok else Dial_Error.Network_Unreachable
		return
	}
	index, entry := new_entry(.TCP)
	if entry == nil {return 0, Dial_Error.Insufficient_Resources}
	id: u32
	result := murk_net_connect(&address, u16(endpoint.port), MURK_WAIT_FOREVER, &id)
	if result != MURK_OK {
		entry.kind = .Free
		switch result {
		case MURK_REFUSED: err = Dial_Error.Refused
		case MURK_RESET: err = Dial_Error.Reset
		case MURK_TIMEOUT: err = Dial_Error.Timeout
		case MURK_NO_ROOM: err = Dial_Error.Insufficient_Resources
		case MURK_INVALID: err = Dial_Error.Invalid_Argument
		case MURK_DOWN: err = Dial_Error.Network_Unreachable
		case: err = Dial_Error.Unknown
		}
		return
	}
	entry.service, entry.opened, entry.peer = id, true, endpoint
	return TCP_Socket(index), nil
}

_create_socket :: proc(family: Address_Family, protocol: Socket_Protocol) -> (sock: Any_Socket, err: Create_Socket_Error) {
	if family != .IP4 && family != .IP6 {return nil, .Invalid_Argument}
	switch protocol {
	case .UDP:
		index, entry := new_entry(.UDP)
		if entry == nil {return nil, .Insufficient_Resources}
		entry.v6 = family == .IP6
		return UDP_Socket(index), nil
	case .TCP:
		// A TCP socket comes into being connected (dial) or listening.
		return nil, .Invalid_Argument
	}
	return nil, .Invalid_Argument
}

// Opens the service's socket for a UDP entry on `port`.
@(private = "file")
open_udp :: proc(entry: ^Murk_Socket, port: int, local: [16]u8 = {}) -> Bind_Error {
	id: u32
	bound: u16
	local := local
	switch murk_net_udp_open_at(&local, u16(port), &id, &bound) {
	case MURK_OK:
	case MURK_IN_USE: return .Address_In_Use
	case MURK_NO_ROOM: return .Insufficient_Resources
	case MURK_INVALID: return .Invalid_Argument
	case: return .Network_Unreachable
	}
	entry.service, entry.opened, entry.local_port = id, true, int(bound)
	return nil
}

_bind :: proc(skt: Any_Socket, ep: Endpoint) -> (err: Bind_Error) {
	entry := entry_of(skt)
	if entry == nil || entry.kind != .UDP {return .Invalid_Argument}
	if entry.opened {return .Already_Bound}
	local, ok := address_of(ep)
	if !ok {return .Invalid_Argument}
	if ep.port < 0 || ep.port > 65535 {return .Invalid_Argument}
	err = open_udp(entry, ep.port, local)
	if err == nil {entry.local_endpoint = ep; entry.local_endpoint.port = entry.local_port}
	return
}

_listen_tcp :: proc(interface_endpoint: Endpoint, backlog := 1000) -> (skt: TCP_Socket, err: Network_Error) {
	if interface_endpoint.port <= 0 || interface_endpoint.port > 65535 {
		err = Listen_Error.Invalid_Argument
		return
	}
	address, valid := address_of(interface_endpoint)
	if !valid {return 0, Listen_Error.Invalid_Argument}
	index, entry := new_entry(.TCP)
	if entry == nil {return 0, Listen_Error.Insufficient_Resources}
	id: u32
	result := murk_net_listen_at(&address, u16(interface_endpoint.port), i32(max(backlog, 1)), &id)
	if result != MURK_OK {
		entry.kind = .Free
		switch result {
		case MURK_IN_USE: err = Listen_Error.Address_In_Use
		case MURK_NO_ROOM: err = Listen_Error.Insufficient_Resources
		case MURK_DOWN: err = Listen_Error.Network_Unreachable
		case: err = Listen_Error.Unknown
		}
		return
	}
	entry.service, entry.opened, entry.local_port = id, true, interface_endpoint.port
	entry.local_endpoint = interface_endpoint
	_, entry.v6 = interface_endpoint.address.(IP6_Address)
	return TCP_Socket(index), nil
}

_bound_endpoint :: proc(sock: Any_Socket) -> (ep: Endpoint, err: Socket_Info_Error) {
	entry := entry_of(sock)
	if entry == nil {return {}, .Invalid_Argument}
	if entry.local_endpoint.address != nil {return entry.local_endpoint, nil}
	return {address = IP6_Any if entry.v6 else IP4_Any, port = entry.local_port}, nil
}

_peer_endpoint :: proc(sock: Any_Socket) -> (ep: Endpoint, err: Socket_Info_Error) {
	entry := entry_of(sock)
	if entry == nil {return {}, .Invalid_Argument}
	if entry.peer.address == nil {return {}, .Unsupported_Socket}
	return entry.peer, nil
}

_accept_tcp :: proc(sock: TCP_Socket, options := DEFAULT_TCP_OPTIONS) -> (client: TCP_Socket, source: Endpoint, err: Accept_Error) {
	listener := entry_of(sock)
	if listener == nil || !listener.opened {err = .Not_Listening; return}
	id: u32
	address: [16]u8
	port: u16
	switch murk_net_accept(listener.service, wait_of(listener, MURK_WAIT_FOREVER), &id, &address, &port) {
	case MURK_OK:
	case MURK_TIMEOUT: err = .Would_Block if listener.non_blocking else .Timeout; return
	case MURK_NO_ROOM: err = .Insufficient_Resources; return
	case MURK_INVALID: err = .Not_Listening; return
	case MURK_DOWN: err = .Network_Unreachable; return
	case: err = .Unknown; return
	}
	source = endpoint_of(address, int(port))
	index, entry := new_entry(.TCP)
	if entry == nil {
		_ = murk_net_close(id)
		err = .Insufficient_Resources
		return
	}
	entry.service, entry.opened, entry.peer, entry.local_port = id, true, source, listener.local_port
	return TCP_Socket(index), source, nil
}

_close :: proc(skt: Any_Socket) {
	entry := entry_of(skt)
	if entry == nil {return}
	if entry.opened {_ = murk_net_close(entry.service)}
	entry^ = {}
}

_recv_tcp :: proc(skt: TCP_Socket, buf: []byte) -> (bytes_read: int, err: TCP_Recv_Error) {
	entry := entry_of(skt)
	if entry == nil || !entry.opened {return 0, .Not_Connected}
	if len(buf) == 0 {return}
	eof: bool
	switch murk_net_receive(entry.service, raw_data(buf), len(buf), wait_of(entry, entry.receive_ms), &bytes_read, &eof) {
	case MURK_OK: return
	case MURK_TIMEOUT: err = .Would_Block if entry.non_blocking else .Timeout
	case MURK_RESET, MURK_CLOSED: err = .Connection_Closed
	case MURK_INVALID: err = .Not_Connected
	case MURK_DOWN: err = .Network_Unreachable
	case: err = .Unknown
	}
	return
}

_recv_udp :: proc(skt: UDP_Socket, buf: []byte) -> (bytes_read: int, remote_endpoint: Endpoint, err: UDP_Recv_Error) {
	entry := entry_of(skt)
	if entry == nil || entry.kind != .UDP {err = .Invalid_Argument; return}
	// Nothing can arrive before the socket has a port.
	if !entry.opened {err = .Would_Block if entry.non_blocking else .Invalid_Argument; return}
	if len(buf) == 0 {err = .Invalid_Argument; return}
	address: [16]u8
	port: u16
	switch murk_net_udp_receive(entry.service, raw_data(buf), len(buf), wait_of(entry, entry.receive_ms), &bytes_read, &address, &port) {
	case MURK_OK:
		remote_endpoint = endpoint_of(address, int(port))
	case MURK_TIMEOUT: err = .Would_Block if entry.non_blocking else .Timeout
	case MURK_INVALID: err = .Invalid_Argument
	case MURK_TOO_LARGE: err = .Invalid_Argument
	case MURK_REFUSED: err = .Connection_Refused
	case MURK_DOWN, MURK_HOP_LIMIT: err = .Network_Unreachable
	case: err = .Unknown
	}
	return
}

_send_tcp :: proc(skt: TCP_Socket, buf: []byte) -> (bytes_written: int, err: TCP_Send_Error) {
	entry := entry_of(skt)
	if entry == nil || !entry.opened {return 0, .Not_Connected}
	switch murk_net_send(entry.service, raw_data(buf), len(buf), &bytes_written) {
	case MURK_OK:
	case MURK_RESET, MURK_CLOSED: err = .Connection_Closed
	case MURK_INVALID: err = .Not_Connected
	case MURK_DOWN: err = .Network_Unreachable
	case: err = .Unknown
	}
	return
}

_send_udp :: proc(skt: UDP_Socket, buf: []byte, to: Endpoint) -> (bytes_written: int, err: UDP_Send_Error) {
	entry := entry_of(skt)
	if entry == nil || entry.kind != .UDP {return 0, .Invalid_Argument}
	address, ok := address_of(to)
	if !ok || to.port <= 0 || to.port > 65535 || len(buf) > MURK_MAX_DATAGRAM {return 0, .Invalid_Argument}
	// An unbound socket takes a free port first, as elsewhere.
	if !entry.opened && open_udp(entry, 0) != nil {return 0, .Network_Unreachable}
	switch murk_net_udp_send(entry.service, &address, u16(to.port), raw_data(buf), len(buf)) {
	case MURK_OK: return len(buf), nil
	case MURK_INVALID: err = .Invalid_Argument
	case MURK_TOO_LARGE: err = .Invalid_Argument
	case MURK_REFUSED: err = .Connection_Refused
	case MURK_HOP_LIMIT: err = .Network_Unreachable
	case MURK_DOWN: err = .Host_Unreachable
	case: err = .Unknown
	}
	return
}

_shutdown :: proc(skt: Any_Socket, manner: Shutdown_Manner) -> (err: Shutdown_Error) {
	entry := entry_of(skt)
	if entry == nil || entry.kind != .TCP || !entry.opened {return .Invalid_Argument}
	directions: u32
	switch manner {
	case .Receive: directions = 1
	case .Send: directions = 2
	case .Both: directions = 3
	}
	if murk_socket_shutdown(i32(entry.service), directions) != 0 {return .Invalid_Argument}
	return
}

_set_option :: proc(s: Any_Socket, option: Socket_Option, value: any, loc := #caller_location) -> Socket_Option_Error {
	entry := entry_of(s)
	if entry == nil {return .Invalid_Socket}
	#partial switch option {
	case .Receive_Timeout, .Send_Timeout:
		ms: u32
		switch v in value {
		case int: ms = u32(clamp(v, 0, int(max(u32)-1)))
		case i64: ms = u32(clamp(v, 0, i64(max(u32)-1)))
		case u32: ms = min(v, max(u32)-1)
		case: return .Invalid_Value
		}
		// Zero means no timeout.
		if ms == 0 {ms = MURK_WAIT_FOREVER}
		if option == .Receive_Timeout {entry.receive_ms = ms} else {entry.send_ms = ms}
		return nil
	case .Keep_Alive:
		if entry.kind != .TCP || !entry.opened {return .Invalid_Socket}
		enabled, valid := value.(bool)
		if !valid {return .Invalid_Value}
		result: i32
		if enabled {result = murk_socket_keepalive(i32(entry.service), 60, 10, 3)} else {result = murk_socket_keepalive(i32(entry.service), 0, 0, 0)}
		if result != 0 {return .Invalid_Value}
		return nil
	case .TCP_Nodelay, .No_SIGPIPE_From_EPIPE:
		// Every segment is sent at once, a closed peer raises no signal, and
		// ports are free again when their connections end.
		return nil
	}
	return .Invalid_Option
}

_set_blocking :: proc(socket: Any_Socket, should_block: bool) -> (err: Set_Blocking_Error) {
	entry := entry_of(socket)
	if entry == nil {return .Invalid_Argument}
	entry.non_blocking = !should_block
	return
}
