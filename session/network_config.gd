class_name NetworkConfig
extends RefCounted

## What THIS MACHINE does about the wire: listen, dial, or neither.
##
## [b]The per-machine half of a run's setup[/b], and it lives here for exactly
## the reason [SeatPolicy] does — [method RunConfig.to_dict] crosses the wire by
## value, and "I am the host" / "dial 192.168.1.7" is the one thing every peer
## must answer DIFFERENTLY. Putting a role on [RunConfig] would ship the host's
## own role to the client and make it a second host.
##
## Distinct from [SeatPolicy] all the same: a seat policy answers "whose eyes do
## I draw with", which is a view question the roster can derive. This answers
## "how do I reach the other machine", which nothing can derive — a human types
## it. The menu writes it, [GameRoot] reads it once at level start, and nothing
## else reads it at all.
##
## [b]It is not the transport.[/b] Which [NetworkTransport] a level mounts is a
## scene-authoring decision at a fixed node path (see [member GameRoot.transport]);
## this only says what role to bring that transport up in.

## The harness's port, reused so a dev typing a port by hand types the same one
## everywhere. Nothing negotiates it — both peers must agree by convention.
const DEFAULT_PORT := 9099

const DEFAULT_ADDRESS := "127.0.0.1"

var role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE
## Unread as a HOST — a listener binds every interface, it does not dial one.
var address: String = DEFAULT_ADDRESS
var port: int = DEFAULT_PORT


## No wire. The default, and what single-player and hot-seat get.
static func offline() -> NetworkConfig:
	return NetworkConfig.new()


static func host(listen_port: int = DEFAULT_PORT) -> NetworkConfig:
	var cfg := NetworkConfig.new()
	cfg.role = NetworkTransport.Role.HOST
	cfg.port = listen_port
	return cfg


static func join(dial_address: String, dial_port: int = DEFAULT_PORT) -> NetworkConfig:
	var cfg := NetworkConfig.new()
	cfg.role = NetworkTransport.Role.CLIENT
	cfg.address = dial_address
	cfg.port = dial_port
	return cfg


## True when this machine should bring a link up at all. The one question
## [GameRoot] asks before touching the mounted transport.
func is_online() -> bool:
	return role != NetworkTransport.Role.OFFLINE


## For a log line or a lobby caption. Never parsed.
func describe() -> String:
	match role:
		NetworkTransport.Role.HOST:
			return "hosting on port %d" % port
		NetworkTransport.Role.CLIENT:
			return "joining %s:%d" % [address, port]
		_:
			return "offline"


## The address a JOINER should type, picked out of [param addresses] — every
## address this machine answers to, loopback and IPv6 and every virtual adapter
## included (#582 D4).
##
## [b]Prefers the first RFC1918 IPv4[/b] — `192.168.x.x`, `10.x.x.x`,
## `172.16–31.x.x` — because that is the one a second machine on the same LAN
## can actually reach. Failing that it lists every non-loopback IPv4 it found,
## so a player on an unusual network still has something to read off. Loopback
## survives only when it is genuinely all there is: dialling `127.0.0.1` from
## another machine reaches that machine, which is the one failure mode worth
## going out of the way to avoid (acceptance 5).
##
## Pure, and takes the list rather than calling [IP] itself, so the pick is
## testable without a network — [method local_advertised_address] is the one
## that touches the machine.
static func pick_advertised_address(addresses: PackedStringArray) -> String:
	var ipv4: PackedStringArray = []
	for address in addresses:
		if _is_ipv4(address):
			ipv4.append(address)

	for address in ipv4:
		if _is_private_ipv4(address):
			return address

	var routable: PackedStringArray = []
	for address in ipv4:
		if not address.begins_with("127."):
			routable.append(address)
	if not routable.is_empty():
		return ", ".join(routable)

	return ", ".join(ipv4) if not ipv4.is_empty() else DEFAULT_ADDRESS


## [method pick_advertised_address] over this machine's real addresses.
static func local_advertised_address() -> String:
	return pick_advertised_address(IP.get_local_addresses())


## An address and a port, said the way a human reads them.
##
## Pure, and it takes the address, because [method pick_advertised_address]'s
## fallback can hand back SEVERAL — and `"a, b:9099"` reads as though the port
## belonged to `b` alone. A list gets the port said separately instead.
static func describe_endpoint(address: String, endpoint_port: int) -> String:
	if address.contains(","):
		return "one of %s — port %d" % [address, endpoint_port]
	return "%s:%d" % [address, endpoint_port]


## What a host reads out loud so a joiner can type it (#582 acceptance 3).
## Host-side only — a client already knows what it dialled.
func advertised_endpoint() -> String:
	return describe_endpoint(local_advertised_address(), port)


## Dotted quad, four decimal octets. Rules out IPv6 (which carries `:`) and the
## link-local IPv6 forms that come back with a `%zone` suffix.
static func _is_ipv4(address: String) -> bool:
	var octets := address.split(".")
	if octets.size() != 4:
		return false
	for octet in octets:
		if not octet.is_valid_int():
			return false
		var value := octet.to_int()
		if value < 0 or value > 255:
			return false
	return true


## RFC1918. The second octet is compared as a NUMBER for the 172 block, because
## `172.32.x.x` is public and a `begins_with("172.")` would advertise it.
## `169.254.x.x` is link-local, not private — routable enough to list, never
## good enough to prefer.
static func _is_private_ipv4(address: String) -> bool:
	var octets := address.split(".")
	if octets.size() != 4:
		return false
	var first := octets[0].to_int()
	var second := octets[1].to_int()
	if first == 10:
		return true
	if first == 192 and second == 168:
		return true
	return first == 172 and second >= 16 and second <= 31
