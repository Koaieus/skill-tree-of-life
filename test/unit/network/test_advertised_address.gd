extends GutTest

## #582 D4 — which of this machine's addresses a HOST reads out so a joiner can
## type it.
##
## [b]Driven by synthetic lists, never by the machine[/b] (acceptance 4). The
## real `IP.get_local_addresses()` returns whatever the test runner's box
## happens to have — loopback on a CI container, a dozen virtual adapters on a
## dev laptop — so asserting against it would pin the runner, not the pick.
## [method NetworkConfig.local_advertised_address] is the one call that touches
## the machine, and it is a one-line composition over the pure function tested
## here.

const _LOOPBACK := "127.0.0.1"
const _LINK_LOCAL := "169.254.14.2"
const _IPV6 := "fe80::1c9a:5eff:fe1b:2a11"
const _IPV6_ZONED := "fe80::1c9a:5eff:fe1b:2a11%eth0"


func _pick(addresses: Array) -> String:
	return NetworkConfig.pick_advertised_address(PackedStringArray(addresses))


func test_the_rfc1918_address_wins_over_everything_else_present() -> void:
	# Acceptance 4, stated as its own case: loopback, link-local, IPv6 and one
	# private address in the list, and the private one comes back ALONE — not
	# first in a list, not annotated. It is what a human types.
	assert_eq(_pick([_LOOPBACK, _IPV6, _LINK_LOCAL, "192.168.1.7"]), "192.168.1.7")


func test_every_rfc1918_block_counts() -> void:
	assert_eq(_pick([_LOOPBACK, "10.0.0.4"]), "10.0.0.4", "10/8")
	assert_eq(_pick([_LOOPBACK, "192.168.50.3"]), "192.168.50.3", "192.168/16")
	assert_eq(_pick([_LOOPBACK, "172.16.0.9"]), "172.16.0.9", "172.16/12, bottom")
	assert_eq(_pick([_LOOPBACK, "172.31.255.4"]), "172.31.255.4", "172.16/12, top")


func test_the_172_block_is_a_range_and_not_a_prefix() -> void:
	# `172.32.x.x` is public, and so is `172.15.x.x`. A `begins_with("172.")`
	# would advertise a public address as the LAN one — the reason the second
	# octet is compared as a number.
	assert_ne(_pick(["172.32.4.4", _LOOPBACK]), _LOOPBACK,
			"a public address still beats loopback")
	assert_eq(_pick([_LOOPBACK, "172.32.4.4", "192.168.1.7"]), "192.168.1.7",
			"but it never beats a real private one")
	assert_eq(_pick([_LOOPBACK, "172.15.0.1", "10.1.2.3"]), "10.1.2.3")


func test_loopback_never_wins_while_any_other_ipv4_exists() -> void:
	# Acceptance 5. Link-local is not private, so it does not take the fast
	# path — and it must still displace loopback, because 127.0.0.1 typed on
	# ANOTHER machine reaches that machine, which is the one failure worth
	# going out of the way to avoid.
	assert_eq(_pick([_LOOPBACK, _LINK_LOCAL]), _LINK_LOCAL)
	assert_eq(_pick([_LOOPBACK, "203.0.113.9"]), "203.0.113.9")


func test_several_unclassifiable_addresses_are_all_offered() -> void:
	# The fallback D4 names: "listing the IPv4 addresses found". A player on an
	# unusual network gets something to read rather than a confident wrong pick.
	var picked := _pick([_LOOPBACK, "203.0.113.9", _IPV6, "198.51.100.4"])
	assert_string_contains(picked, "203.0.113.9")
	assert_string_contains(picked, "198.51.100.4")
	assert_false(picked.contains(_LOOPBACK), "and loopback is not among them")


func test_ipv6_is_never_offered() -> void:
	# Nothing in the transport dials one, and no player is typing that.
	assert_false(_pick([_IPV6, _IPV6_ZONED, "192.168.1.7"]).contains(":"))
	assert_eq(_pick([_IPV6, _IPV6_ZONED]), NetworkConfig.DEFAULT_ADDRESS,
			"an all-IPv6 machine falls back rather than printing one")


func test_a_loopback_only_machine_says_loopback() -> void:
	# The single case where 127.0.0.1 is the honest answer: there is nothing
	# else. Two clients on one machine is a real LAN-cut scenario.
	assert_eq(_pick([_LOOPBACK]), _LOOPBACK)
	assert_eq(_pick([]), NetworkConfig.DEFAULT_ADDRESS, "and an empty list is not a crash")


func test_junk_octets_are_not_ipv4() -> void:
	assert_eq(_pick(["192.168.1", "1.2.3.4.5", "300.1.1.1", "a.b.c.d", "10.0.0.4"]),
			"10.0.0.4")


func test_the_endpoint_a_host_reads_out_carries_its_port() -> void:
	# What the lobby prints. The address half is the machine's real answer here
	# — unassertable — so this pins only that the typed PORT reaches the caption
	# and that the address it goes with is the one the picker chose.
	var caption := NetworkConfig.host(7777).advertised_endpoint()
	assert_string_contains(caption, "7777")
	assert_string_contains(caption, NetworkConfig.local_advertised_address())


func test_a_single_address_is_read_out_as_one_thing_to_type() -> void:
	assert_eq(NetworkConfig.describe_endpoint("192.168.1.7", 7777), "192.168.1.7:7777")


func test_a_fallback_LIST_never_glues_the_port_onto_its_last_entry() -> void:
	# `"203.0.113.9, 198.51.100.4:9099"` reads as though only the second address
	# used that port. D4 authorised the list; it did not authorise saying it
	# that way.
	var caption := NetworkConfig.describe_endpoint("203.0.113.9, 198.51.100.4", 9099)
	assert_false(caption.contains("198.51.100.4:9099"))
	assert_string_contains(caption, "port 9099")
