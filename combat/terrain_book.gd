## One terrain commit's (or one gather beat's) applied amounts, per element
## (Heat, Cold, Charge) × [enum Field], flat in [member sums]: the
## telemetry [TerrainLedger] counts (`docs/domain/terrain-ledger.md`). As a
## [TerrainSettle.SettleReader] appended LAST to a commit's readers it sees
## each node's pre ints and final sums and splits them as
## [method TerrainSettle.settled_t] lands them: Heat adds, then Cold adds
## (each part landing on the opposite sign is [code]ONTO_OPPOSITE[/code]),
## then the pull toward zero on the side t ends on ([member pull_field]);
## Charge adds whole, its subtraction clamped at what is there. Gross adds are
## asked per node ([method ask_net_t], [method ask_charge]) and booked under
## [member add_field]; whatever the earlier readers added (a Catalyst
## conversion) is [code]PRODUCED[/code]. A diffusion book books only the Heat
## its flow cancelled onto Cold. Reads, never writes.
class_name TerrainBook
extends TerrainSettle.SettleReader

enum Field { PRODUCED, EFFECT, VOIDED, VOIDED_INCOMING, DECAYED, ONTO_OPPOSITE }
const HEAT := 0
const COLD := 1
const CHARGE := 2
const WIDTH := 6
const SIZE := 18
var sums := PackedInt32Array()
var add_field: int = Field.PRODUCED
var pull_field: int = Field.VOIDED
var diffusion := false
var _asks: Dictionary = {}  # NodeCombat -> [heat, cold, charge add, charge sub]


func _init(at_add := Field.PRODUCED, at_pull := Field.VOIDED, at_diffusion := false) -> void:
	sums.resize(SIZE)
	add_field = at_add
	pull_field = at_pull
	diffusion = at_diffusion


## The row of [param e]'s element: Fire Heat, Ice Cold, Lightning Charge.
static func row_of(e: Element) -> int:
	match Terrain.axis_of(e):
		Terrain.Axis.HEAT:
			return HEAT
		Terrain.Axis.COLD:
			return COLD
	return CHARGE


static func read_of(s: PackedInt32Array, row: int, field: int) -> int:
	var i := row * WIDTH + field
	return s[i] if i < s.size() else 0


static func any(s: PackedInt32Array) -> bool:
	for v in s:
		if v != 0:
			return true
	return false


func at(row: int, field: int) -> int:
	return read_of(sums, row, field)


func book(row: int, field: int, n: int) -> void:
	if n != 0:
		sums[row * WIDTH + field] += n


func merge(other: PackedInt32Array) -> void:
	for i in mini(other.size(), SIZE):
		sums[i] += other[i]


func ask_net_t(node: NodeCombat, delta: int) -> void:
	var a := _ask(node)
	if delta > 0:
		a[0] += delta
	else:
		a[1] -= delta


func ask_charge(node: NodeCombat, delta: int) -> void:
	var a := _ask(node)
	if delta > 0:
		a[2] += delta
	else:
		a[3] -= delta


func _ask(node: NodeCombat) -> Array:
	if not _asks.has(node):
		_asks[node] = [0, 0, 0, 0]
	return _asks[node]


func read(node: NodeCombat, pre_t: int, pre_charge: int,
		_post_t: int, _post_charge: int, s: TerrainSettle.Sums) -> void:
	var a: Array = _asks.get(node, [0, 0, 0, 0])
	var extra_t: int = s.net_t - (int(a[0]) - int(a[1]))
	var extra_c: int = s.charge - (int(a[2]) - int(a[3]))
	if diffusion:
		var base: int = pre_t + int(a[0]) - int(a[1])
		book(HEAT, Field.ONTO_OPPOSITE, maxi(pre_t, 0) - maxi(base, 0))
		_book_t(base, 0, 0, maxi(extra_t, 0), maxi(-extra_t, 0), s.toward_zero_t)
	else:
		_book_t(pre_t, int(a[0]), int(a[1]), maxi(extra_t, 0), maxi(-extra_t, 0), s.toward_zero_t)
	_book_charge(pre_charge, int(a[2]), maxi(extra_c, 0), int(a[3]) + maxi(-extra_c, 0))


## A write that already landed (a head's rider through its row, a degree
## drop's conversion): its ints before and after, booked [code]PRODUCED[/code].
func book_landing(pre_t: int, pre_charge: int, post_t: int, post_charge: int) -> void:
	var dt := post_t - pre_t
	_book_t(pre_t, 0, 0, maxi(dt, 0), maxi(-dt, 0), 0)
	var dc := post_charge - pre_charge
	_book_charge(pre_charge, 0, maxi(dc, 0), maxi(-dc, 0))


func _book_t(pre: int, h: int, c: int, xh: int, xc: int, pull: int) -> void:
	book(HEAT, add_field, h)
	book(HEAT, Field.PRODUCED, xh)
	book(COLD, add_field, c)
	book(COLD, Field.PRODUCED, xc)
	var x := pre
	book(HEAT, Field.ONTO_OPPOSITE, mini(h + xh, maxi(-x, 0)))
	x += h + xh
	book(COLD, Field.ONTO_OPPOSITE, mini(c + xc, maxi(x, 0)))
	x -= c + xc
	var p := mini(absi(x), maxi(pull, 0))
	if x > 0:
		book(HEAT, pull_field, p)
	elif x < 0:
		book(COLD, pull_field, p)


func _book_charge(pre: int, add: int, extra: int, sub: int) -> void:
	book(CHARGE, add_field, add)
	book(CHARGE, Field.PRODUCED, extra)
	book(CHARGE, pull_field, mini(sub, maxi(pre + add + extra, 0)))
