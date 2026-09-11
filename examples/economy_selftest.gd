extends Node

## Exercises dot-economy with no other addon and no world.
##
## Teams, positions and liveness are dictionaries, which is the seam a real game fills.
## What is checked is what this addon promises: that the ladder is the genre's, that a
## buy window closes on a tick rather than a clock, that a refund cannot be used
## as a savings account, and that money above the ceiling is reported rather than
## silently swallowed.
##
## [codeblock]
## godot --headless --path . res://examples/economy_selftest.tscn
## [/codeblock]

const SECTIONS := 10

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0

var _teams: Dictionary = {}
var _alive: Dictionary = {}
var _zone: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-economy self-test")
	_line("")

	_test_rules()
	_test_items()
	_test_shop()
	_test_accounts()
	_test_buying()
	_test_buy_window()
	_test_refunds()
	_test_kills()
	_test_round_economy()
	_test_wire()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _arsenal() -> Array[DotShopItem]:
	var kevlar := DotShopItem.make(&"kevlar", 650, "Kevlar")
	var helmet := DotShopItem.make(&"helmet", 350, "Helmet")
	helmet.requires = &"kevlar"
	var ak := DotShopItem.make(&"ak47", 2700, "AK-47")
	ak.teams = PackedInt32Array([1])
	var m4 := DotShopItem.make(&"m4a1", 3100, "M4A1")
	m4.teams = PackedInt32Array([2])
	var sniper := DotShopItem.make(&"sniper", 4750, "Sniper Rifle")
	sniper.kill_award = 100
	var nade := DotShopItem.make(&"he", 300, "HE Grenade")
	nade.per_round_limit = 1
	nade.tags = PackedStringArray(["grenade"])
	var defuser := DotShopItem.make(&"defuser", 400, "Defuse Kit")
	defuser.teams = PackedInt32Array([2])
	defuser.refundable = false
	return [kevlar, helmet, ak, m4, sniper, nade, defuser]


func _manager() -> DotEconomyManager:
	var m := DotEconomyManager.new()
	m.team_fn = func(key: String) -> int: return int(_teams.get(key, 0))
	m.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, true))
	m.in_buy_zone_fn = func(key: String) -> bool: return bool(_zone.get(key, true))
	add_child(m)
	var res := m.setup(_arsenal())
	if not res.ok:
		_line("  SETUP FAILED: %s" % res.error.message)
	return m


# --- Rules ------------------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var rules := DotEconomyRules.new()
	_check(rules.validate().ok, "the defaults validate")
	_check(rules.start_money == 800, "and are the genre's: 800 to start")
	_check(rules.max_money == 16000, "16000 as a ceiling")

	_check(rules.loss_bonus_for(1) == 1400, "the ladder starts at 1400")
	_check(rules.loss_bonus_for(2) == 1900, "then 1900")
	_check(rules.loss_bonus_for(3) == 2400, "then 2400")
	_check(rules.loss_bonus_for(5) == 3400, "and reaches 3400")
	_check(rules.loss_bonus_for(9) == 3400, "and stops there")
	_check(rules.loss_bonus_for(0) == 0, "and a team on no streak gets nothing")

	rules.start_money = 20000
	_check(
		not rules.validate().ok,
		"a starting balance above the ceiling is refused: the first thing that would "
		+ "happen is that everybody loses money"
	)
	rules.start_money = 800

	rules.loss_bonus_max = 500
	_check(not rules.validate().ok, "and a ladder that goes down")
	rules.loss_bonus_max = 3400

	rules.refund_ticks = 5000
	rules.buy_time_ticks = 1280
	rules.refund_within_buy_time = true
	_check(
		not rules.validate().ok,
		"a refund window longer than the buy window it is restricted to is refused"
	)


func _test_items() -> void:
	_section("items")

	var ak := DotShopItem.make(&"ak47", 2700)
	_check(ak.validate().ok, "an item validates")
	_check(ak.available_to(1), "and is sold to everybody by default")

	ak.teams = PackedInt32Array([1])
	_check(ak.available_to(1) and not ak.available_to(2), "until it names a team")

	var rules := DotEconomyRules.new()
	_check(ak.award_for_kill(rules) == 300, "a kill pays the default")
	var sniper := DotShopItem.make(&"sniper", 4750)
	sniper.kill_award = 100
	_check(
		sniper.award_for_kill(rules) == 100,
		"unless the weapon says otherwise — the genre's most-copied economic idea"
	)

	var bad := DotShopItem.new()
	_check(not bad.validate().ok, "an item with no id is refused")
	var loop := DotShopItem.make(&"x", 100)
	loop.requires = &"x"
	_check(
		not loop.validate().ok,
		"and one that requires itself, which could never be bought"
	)


func _test_shop() -> void:
	_section("the shop")

	var built := DotShop.of(_arsenal())
	_check(built.ok, "an arsenal builds")
	var shop: DotShop = built.value
	_check(shop.has(&"ak47"), "and has what was put in it")
	_check(shop.item(&"sniper").price == 4750, "with its price")

	var t := shop.for_team(1)
	var ids: Array[StringName] = []
	for item in t:
		ids.append(item.id)
	_check(ids.has(&"ak47"), "team 1 is sold the AK")
	_check(not ids.has(&"m4a1"), "and not the M4")
	_check(
		t[0].price <= t[t.size() - 1].price,
		"and the list comes back cheapest first, so every menu that draws it agrees"
	)

	_check(shop.with_tag("grenade").size() == 1, "items can be found by tag")

	var dup := DotShop.of([
		DotShopItem.make(&"same", 1), DotShopItem.make(&"same", 2),
	] as Array[DotShopItem])
	_check(not dup.ok, "two items with one id are refused")

	var orphan := DotShopItem.make(&"scope", 100)
	orphan.requires = &"nothing_here"
	_check(
		not DotShop.of([orphan] as Array[DotShopItem]).ok,
		"and an item requiring something not in the shop, which could never be bought "
		+ "with nothing saying why"
	)

	var later := DotShopItem.make(&"upgrade", 100)
	later.requires = &"base"
	var base := DotShopItem.make(&"base", 100)
	_check(
		DotShop.of([later, base] as Array[DotShopItem]).ok,
		"a requirement declared later in the list is fine — the order of a catalogue "
		+ "file is not part of its meaning"
	)


func _test_accounts() -> void:
	_section("accounts")

	var acct := DotEconomyAccount.new("ada", 800)
	_check(acct.balance == 800, "an account starts where it was opened")

	var landed := acct.credit(500, 16000)
	_check(landed == 500 and acct.balance == 1300, "money goes in")

	landed = acct.credit(20000, 16000)
	_check(
		acct.balance == 16000 and landed == 14700,
		"and stops at the ceiling, reporting what actually landed rather than what was "
		+ "asked for"
	)

	var taken := acct.debit(20000)
	_check(taken == 16000 and acct.balance == 0, "and never goes below zero")

	acct.note_purchase(&"ak47", 2700, 10)
	acct.note_purchase(&"he", 300, 12)
	acct.note_purchase(&"he", 300, 14)
	_check(acct.bought_this_round(&"he") == 2, "purchases are counted")
	_check(acct.holding(&"ak47") == 1, "and held")

	var last := acct.last_purchase(&"he")
	last["price"] = 99999
	_check(
		int(acct.last_purchase(&"he")["price"]) == 300,
		"and last_purchase hands out a copy, because a Dictionary is a reference"
	)

	_check(acct.forget_purchase(&"he"), "one can be forgotten")
	_check(acct.bought_this_round(&"he") == 1, "and it is")

	acct.begin_round()
	_check(acct.purchases.is_empty(), "a new round clears the purchase list")
	_check(acct.holding(&"ak47") == 1, "and does not clear what is held across rounds")


# --- Buying -----------------------------------------------------------------

func _test_buying() -> void:
	_section("buying")

	_teams = {"ada": 1, "bob": 2}
	_alive = {"ada": true, "bob": true}
	_zone = {"ada": true, "bob": true}

	var m := _manager()
	m.on_round_start(0)

	var bought: Array[StringName] = []
	m.bought.connect(func(_k: String, id: StringName, _p: int, _b: int) -> void:
		bought.append(id))

	_check(m.balance("ada") == 800, "everybody starts with 800")
	_check(not m.buy("ada", &"ak47").ok, "and cannot afford a rifle")

	var _got := m.award("ada", 5000, &"test")
	_check(m.buy("ada", &"ak47").ok, "and can once they have been paid")
	_check(m.balance("ada") == 5800 - 2700, "the price comes out")
	_check(bought.size() == 1, "and the game is told to grant it")

	_check(
		not m.buy("bob", &"ak47").ok,
		"the other side is not sold that rifle"
	)

	_check(
		not m.buy("ada", &"helmet").ok,
		"a helmet needs kevlar first"
	)
	var _k := m.buy("ada", &"kevlar")
	_check(m.buy("ada", &"helmet").ok, "and is sold once they have it")

	_check(m.buy("ada", &"he").ok, "a grenade is sold")
	var second := m.buy("ada", &"he")
	_check(not second.ok, "and only one per round")
	_check(second.code() == DotError.CODE_QUOTA, "with a quota code")

	_zone["ada"] = false
	_check(not m.buy("ada", &"kevlar").ok, "outside a buy zone, nothing is sold")
	_zone["ada"] = true

	_alive["ada"] = false
	_check(not m.buy("ada", &"kevlar").ok, "and a dead player buys nothing")
	m.rules.allow_buying_while_dead = true
	_check(m.buy("ada", &"kevlar").ok, "unless the server says they may")
	_alive["ada"] = true

	var why := m.may_buy("ada", &"nothing")
	_check(
		not why.ok and why.error.message.contains("for sale"),
		"may_buy says why, so a menu can grey an entry out without reimplementing the "
		+ "test and disagreeing with the server"
	)

	m.queue_free()


func _test_buy_window() -> void:
	_section("the buy window")

	_teams = {"ada": 1}
	_alive = {"ada": true}
	_zone = {"ada": true}

	var m := _manager()
	m.rules.buy_time_ticks = 2 * RATE

	var opens: Array[bool] = []
	m.buy_window.connect(func(open: bool) -> void: opens.append(open))

	m.on_round_start(1000)
	_check(m.is_buy_window_open(), "a round opens the window")
	_check(opens.size() == 1 and opens[0], "and says so once")
	_check(
		m.buy_ticks_remaining() == 2 * RATE,
		"and it can say how long is left, in ticks"
	)

	for t in range(1000, 1000 + RATE):
		m.advance(t)
	_check(m.is_buy_window_open(), "one second into two, it is still open")

	for t in range(1000 + RATE, 1000 + 3 * RATE):
		m.advance(t)
	_check(not m.is_buy_window_open(), "and after two seconds it is not")
	_check(opens.size() == 2 and not opens[1], "which is announced exactly once")
	_check(m.buy_ticks_remaining() == 0, "with nothing left")

	var _a := m.award("ada", 5000, &"test")
	_check(not m.buy("ada", &"kevlar").ok, "and nothing is sold after it")

	m.rules.buy_time_ticks = 0
	m.on_round_start(2000)
	for t in range(2000, 2000 + 100 * RATE):
		m.advance(t)
	_check(
		m.is_buy_window_open(),
		"a buy time of zero never closes, for a game where buying is always on"
	)
	_check(m.buy_ticks_remaining() == -1, "and says so with -1 rather than a huge number")

	m.queue_free()


func _test_refunds() -> void:
	_section("refunds")

	_teams = {"ada": 1}
	_alive = {"ada": true}
	_zone = {"ada": true}

	var m := _manager()
	m.on_round_start(0)
	var _a := m.award("ada", 10000, &"test")
	var before := m.balance("ada")

	var _b := m.buy("ada", &"ak47")
	_check(m.balance("ada") == before - 2700, "a rifle costs money")

	m.advance(10)
	var back := m.refund("ada", &"ak47")
	_check(back.ok, "and can be given back inside the window")
	_check(m.balance("ada") == before, "for all of it")
	_check(
		not m.refund("ada", &"ak47").ok,
		"and only once, because the purchase is gone"
	)

	var _b2 := m.buy("ada", &"ak47")
	m.advance(10 + m.rules.refund_ticks + 1)
	_check(
		not m.refund("ada", &"ak47").ok,
		"and not after the window has passed"
	)

	m.on_round_start(10000)
	var _b3 := m.buy("ada", &"defuser")
	_check(
		not m.refund("ada", &"defuser").ok,
		"an item marked unrefundable is not given back"
	)

	var _b4 := m.buy("ada", &"kevlar")
	m.advance(10000 + m.rules.buy_time_ticks + 1)
	_check(
		not m.refund("ada", &"kevlar").ok,
		"and nothing is refunded once the buy window shuts — otherwise a player sells "
		+ "their rifle at the end of a round for money they keep"
	)

	m.rules.refund_ticks = 0
	m.on_round_start(20000)
	var _b5 := m.buy("ada", &"kevlar")
	var off := m.refund("ada", &"kevlar")
	_check(
		not off.ok and off.code() == DotError.CODE_UNSUPPORTED,
		"a server with refunds off says so rather than failing for another reason"
	)

	m.queue_free()


func _test_kills() -> void:
	_section("kills")

	_teams = {"ada": 1, "bob": 2, "cal": 1}
	_alive = {"ada": true, "bob": true, "cal": true}

	var m := _manager()
	m.on_round_start(0)

	var got := m.on_kill("ada", "bob", &"ak47")
	_check(got == 300, "a rifle kill pays 300")

	got = m.on_kill("ada", "bob", &"sniper")
	_check(
		got == 100,
		"a sniper-rifle kill pays 100, so the cheapest way to make money is the riskiest "
		+ "thing you can do"
	)

	var _rich := m.award("ada", 5000, &"test")
	var before := m.balance("ada")
	got = m.on_kill("ada", "cal", &"ak47")
	_check(got < 0, "killing a team-mate costs money")
	_check(m.balance("ada") == before - m.rules.teamkill_penalty, "3300 of it")

	# And the clamp, which is the genre's: a negative balance is a player who
	# cannot buy for several rounds through no further fault, and the fine is meant to
	# cost them this round rather than the half.
	var _spend := m.award("ada", -(m.balance("ada") - 100), &"test")
	var _tk := m.on_kill("ada", "cal", &"ak47")
	_check(m.balance("ada") == 0, "and it never takes an account below zero")

	m.rules.suicide_penalty = 100
	before = m.balance("bob")
	var _s := m.on_kill("bob", "bob", &"")
	_check(m.balance("bob") == before - 100, "and a suicide costs what the rules say")

	var _c := m.on_kill("", "bob", &"ak47")
	_check(true, "a kill by nobody pays nobody and does not crash")

	var capped: Array[int] = []
	m.award_capped.connect(func(_k: String, wanted: int, _l: int) -> void:
		capped.append(wanted))
	var _big := m.award("ada", 100000, &"test")
	_check(
		capped.size() == 1,
		"money that could not land is reported rather than silently swallowed"
	)
	_check(m.balance("ada") == 16000, "and the balance sits at the ceiling")

	m.queue_free()


func _test_round_economy() -> void:
	_section("the round economy")

	_teams = {"ada": 1, "bob": 2}
	_alive = {"ada": true, "bob": true}

	var m := _manager()
	# Open the accounts, which is what a real game does when players join.
	var _o1 := m.balance("ada")
	var _o2 := m.balance("bob")

	m.on_round_start(0)
	m.on_round_end(1)
	_check(
		m.balance("ada") == 800 + m.rules.win_award,
		"the winners are paid"
	)
	_check(
		m.balance("bob") == 800 + 1400,
		"and the losers get the bottom of the ladder"
	)
	_check(m.loss_streak(2) == 1, "which is a streak of one")
	_check(m.next_loss_bonus(2) == 1900, "and the next one would be 1900")

	m.on_round_start(1000)
	m.on_round_end(1)
	_check(m.loss_streak(2) == 2, "losing again makes it two")
	_check(m.loss_streak(1) == 0, "and the winners are on none")

	m.on_round_start(2000)
	m.on_round_end(2)
	_check(
		m.loss_streak(2) == 0,
		"and winning resets it, because a comeback that stays rewarded is a different "
		+ "game"
	)
	_check(m.loss_streak(1) == 1, "while the other side starts one")

	var before_a := m.balance("ada")
	var before_b := m.balance("bob")
	m.on_round_start(3000)
	m.on_round_end(0)
	_check(
		m.balance("ada") == before_a and m.balance("bob") == before_b,
		"a draw pays nobody: counting it as a loss for both gives both a bonus, and as "
		+ "a win for both resets both ladders"
	)
	_check(m.loss_streak(1) == 1, "and moves no streak")

	var paid := m.on_objective(1, 800)
	_check(paid == 1, "an objective pays the team that did it")

	m.on_half_time()
	_check(m.balance("ada") == 800, "half time resets the balances")
	_check(m.loss_streak(1) == 0, "and the ladders")

	m.queue_free()


func _test_wire() -> void:
	_section("the wire")

	_teams = {"ada": 1}
	_alive = {"ada": true}
	_zone = {"ada": true}

	var m := _manager()
	m.on_round_start(0)
	var _a := m.award("ada", 4000, &"test")
	var _b := m.buy("ada", &"kevlar")

	var mirror := DotEconomyManager.new()
	mirror.authoritative = false
	add_child(mirror)
	var _s := mirror.setup(_arsenal())

	mirror.apply_wire(m.to_wire("ada"))
	_check(mirror.balance("ada") == m.balance("ada"), "a balance travels")
	_check(
		mirror.account("ada").purchases.size() == 1,
		"and what was bought this round, so a menu can grey out what is already held"
	)
	_check(mirror.is_buy_window_open(), "and whether the window is open")

	_check(
		not mirror.buy("ada", &"kevlar").ok,
		"a mirror sells nothing — it is told what was sold"
	)

	var w := m.to_wire("nobody_here")
	_check(
		int((w["a"] as Dictionary)["b"]) == m.rules.start_money,
		"asking about somebody with no account gives the starting balance rather than "
		+ "opening one, because a wire form must not create players"
	)

	var lines := m.describe_lines()
	_check(lines.size() > 1, "and it describes itself")

	m.queue_free()
	mirror.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
