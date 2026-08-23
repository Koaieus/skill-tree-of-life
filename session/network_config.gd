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
