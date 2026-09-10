class_name DotEconomyManager
extends Node

## A round-based buy economy: money, a shop, a buy window and a loss-bonus ladder.
##
## [codeblock]
## var economy := DotEconomyManager.new()
## economy.in_buy_zone_fn = func(key): return world.in_buy_zone(key)
## economy.team_fn = match_node.team_of
## economy.alive_fn = world.is_alive
## var res := economy.setup(shop_items)
## add_child(economy)
##
## economy.on_round_start(tick)          # opens the buy window
## economy.advance(tick)                 # closes it, and expires refunds
## economy.on_kill("ada", "bob", &"ak47")
## economy.on_round_end(1)               # pays the winners and the losers
## [/codeblock]
##
## [b]It sells ids and never grants anything.[/b] `bought` carries an item id and the
## game does whatever that means — [DotLoadoutManager], a [DotArsenal], a boolean. A
## shop that granted things would be one that could not validate a purchase without
## loading a mesh, which is dot-loadout's rule and the same one.
##
## [b]No autoload[/b], for the family's reason: a server and a mirroring client are two
## of these in one process.

## Somebody bought something. The game grants it.
signal bought(key: String, id: StringName, price: int, balance: int)

## …and gave it back inside the window. The game takes it away again.
signal refunded(key: String, id: StringName, amount: int, balance: int)

## A balance changed for any reason. [param reason] is a StringName a HUD can draw:
## [code]&"kill"[/code], [code]&"round_win"[/code], [code]&"loss_bonus"[/code].
signal balance_changed(key: String, balance: int, delta: int, reason: StringName)

## The buy window opened or closed.
signal buy_window(open: bool)

## Money that could not land because the account was at the ceiling.
##
## Emitted rather than swallowed, because a player who is told "+3250" and receives 900
## has been told something untrue about a system they are planning around.
signal award_capped(key: String, wanted: int, landed: int)

@export var rules: DotEconomyRules = null

## What is for sale. Assigning this and calling [method setup] is the whole of loading a
## shop.
@export var catalogue: Array[DotShopItem] = []

@export var authoritative: bool = true

## Whether a player is standing somewhere they may buy.
## [code](key: String) -> bool[/code]. Consulted only when
## [member DotEconomyRules.require_buy_zone] is on.
var in_buy_zone_fn: Callable = Callable()

## Which team somebody is on. [code](key: String) -> int[/code].
var team_fn: Callable = Callable()

## Whether somebody is alive. [code](key: String) -> bool[/code].
var alive_fn: Callable = Callable()

var shop: DotShop = null

var _accounts: Dictionary = {}
var _streaks: Dictionary = {}
var _round_start: int = -1
var _buy_open: bool = false
var _tick: int = 0


func _init() -> void:
	if rules == null:
		rules = DotEconomyRules.new()


func setup(p_items: Array[DotShopItem] = []) -> DotResult:
	if not p_items.is_empty():
		catalogue = p_items
	if rules == null:
		rules = DotEconomyRules.new()

	var res := rules.validate()
	if not res.ok:
		return res.wrap("economy rules")

	var built := DotShop.of(catalogue)
	if not built.ok:
		return built.wrap("shop")
	shop = built.value

	DotLog.info("economy", "%d items for sale" % shop.items.size())
	return DotResult.success(null)


# --- Accounts ----------------------------------------------------------------

## Somebody's account, opened at the starting balance if they have not got one.
func account(key: String) -> DotEconomyAccount:
	var acct: DotEconomyAccount = _accounts.get(key, null)
	if acct == null:
		acct = DotEconomyAccount.new(key, rules.start_money)
		_accounts[key] = acct
	return acct


func balance(key: String) -> int:
	return account(key).balance


func forget(key: String) -> void:
	_accounts.erase(key)


func keys() -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = _accounts.keys()
	ids.sort()
	for id: Variant in ids:
		out.append(str(id))
	return out


## Give somebody money.
func award(key: String, amount: int, reason: StringName = &"award") -> int:
	if amount == 0:
		return 0
	var acct := account(key)
	if amount < 0:
		var taken := acct.debit(-amount)
		balance_changed.emit(key, acct.balance, -taken, reason)
		return -taken
	var landed := acct.credit(amount, rules.max_money)
	if landed < amount:
		award_capped.emit(key, amount, landed)
	balance_changed.emit(key, acct.balance, landed, reason)
	return landed


## Give a whole team money. Returns how many accounts it landed in.
func award_team(team: int, amount: int, reason: StringName = &"award") -> int:
	if not team_fn.is_valid():
		return 0
	var n := 0
	for key in keys():
		if int(team_fn.call(key)) != team:
			continue
		var _got := award(key, amount, reason)
		n += 1
	return n


# --- Buying ------------------------------------------------------------------

func is_buy_window_open() -> bool:
	return _buy_open


## Ticks left in the buy window. -1 when it never closes, 0 when it is shut.
func buy_ticks_remaining() -> int:
	if rules.buy_time_ticks <= 0:
		return -1
	if not _buy_open or _round_start < 0:
		return 0
	return maxi(_round_start + rules.buy_time_ticks - _tick, 0)


## Whether somebody may buy an item right now, and why not when they may not.
##
## Public and separate from [method buy] because a buy menu has to grey out what cannot
## be bought and say why — and a menu that reimplements the test is a menu that
## disagrees with the server about what is for sale.
func may_buy(key: String, id: StringName) -> DotResult:
	var item := shop.item(id) if shop != null else null
	if item == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "Nothing called '%s' is for sale." % id
		)

	if not _buy_open:
		return DotResult.fail(DotError.CODE_STATE, "The buy window is closed.")

	if not rules.allow_buying_while_dead and alive_fn.is_valid() \
			and not bool(alive_fn.call(key)):
		return DotResult.fail(DotError.CODE_STATE, "A dead player buys nothing.")

	if rules.require_buy_zone and in_buy_zone_fn.is_valid() \
			and not bool(in_buy_zone_fn.call(key)):
		return DotResult.fail(DotError.CODE_STATE, "Not in a buy zone.")

	var team := int(team_fn.call(key)) if team_fn.is_valid() else 0
	if not item.available_to(team):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "'%s' is not sold to team %d." % [id, team]
		)

	var acct := account(key)

	if item.requires != &"" and acct.holding(item.requires) <= 0:
		return DotResult.fail(
			DotError.CODE_STATE,
			"'%s' needs '%s' first." % [id, item.requires]
		)

	if item.per_round_limit > 0 and acct.bought_this_round(id) >= item.per_round_limit:
		return DotResult.fail(
			DotError.CODE_QUOTA,
			"Only %d '%s' per round." % [item.per_round_limit, id]
		)

	if item.per_life_limit > 0 and acct.holding(id) >= item.per_life_limit:
		return DotResult.fail(
			DotError.CODE_QUOTA, "Already holding %d '%s'." % [acct.holding(id), id]
		)

	if not acct.can_afford(item.price):
		return DotResult.fail(
			DotError.CODE_STATE,
			"$%d short of '%s'." % [item.price - acct.balance, id]
		)

	return DotResult.success(item)


func buy(key: String, id: StringName) -> DotResult:
	if not authoritative:
		return DotResult.fail(
			DotError.CODE_STATE,
			"A mirroring economy does not sell anything; it is told what was sold."
		)

	var allowed := may_buy(key, id)
	if not allowed.ok:
		return allowed

	var item: DotShopItem = allowed.value
	var acct := account(key)
	var _paid := acct.debit(item.price)
	acct.note_purchase(id, item.price, _tick)
	balance_changed.emit(key, acct.balance, -item.price, &"bought")
	bought.emit(key, id, item.price, acct.balance)
	return DotResult.success(item)


## Give something back inside the refund window.
func refund(key: String, id: StringName) -> DotResult:
	if rules.refund_ticks <= 0:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "This server has refunds turned off."
		)
	if rules.refund_within_buy_time and not _buy_open:
		return DotResult.fail(
			DotError.CODE_STATE,
			(
				"Refunds close with the buy window — otherwise a player sells their "
				+ "rifle at the end of a round for money they keep."
			)
		)

	var item := shop.item(id) if shop != null else null
	if item == null:
		return DotResult.fail(DotError.CODE_INVALID, "No such item '%s'." % id)
	if not item.refundable:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "'%s' cannot be given back." % id
		)

	var acct := account(key)
	var last := acct.last_purchase(id)
	if last.is_empty():
		return DotResult.fail(
			DotError.CODE_STATE, "%s did not buy a '%s' this round." % [key, id]
		)

	var age := _tick - int(last["tick"])
	if age > rules.refund_ticks:
		return DotResult.fail(
			DotError.CODE_STATE,
			"Too late to give back a '%s' (%d ticks, limit %d)."
				% [id, age, rules.refund_ticks]
		)

	var back := int(roundf(float(int(last["price"])) * rules.refund_fraction))
	var _forgot := acct.forget_purchase(id)
	var landed := acct.credit(back, rules.max_money)
	balance_changed.emit(key, acct.balance, landed, &"refund")
	refunded.emit(key, id, landed, acct.balance)
	return DotResult.success(landed)


# --- The round ---------------------------------------------------------------

## A round began. Opens the buy window and starts the purchase list again.
func on_round_start(tick: int) -> void:
	_tick = tick
	_round_start = tick
	for key: Variant in _accounts.keys():
		(_accounts[key] as DotEconomyAccount).begin_round()

	# Always open, and `advance` is what closes it. A zero buy time means "no timer",
	# not "no buying" -- reading it as a condition here made the one configuration a
	# game without a buy timer uses the one where nothing could ever be bought, with
	# every refusal correctly reporting "the buy window is closed".
	_set_buy_open(true)


## A round ended. Pays the winners, and the losers their ladder.
##
## [param winning_team] of 0 is a draw: nobody wins and nobody's streak moves, because a
## draw that counts as a loss for both sides gives both of them a bonus and a draw that
## counts as a win for both resets both ladders. Neither is what a draw means.
func on_round_end(winning_team: int, _reason: StringName = &"") -> void:
	_set_buy_open(false)

	if not team_fn.is_valid():
		DotLog.warn(
			"economy",
			(
				"A round ended and team_fn is not wired, so nobody was paid. An unset "
				+ "Callable answers 0, which is a legitimate team id for nobody."
			)
		)
		return

	if winning_team <= 0:
		return

	var teams := _teams_present()
	for team in teams:
		if team == winning_team:
			if rules.loss_bonus_resets_on_win:
				_streaks[team] = 0
			var _paid := award_team(team, rules.win_award, &"round_win")
		else:
			var streak := int(_streaks.get(team, 0)) + 1
			_streaks[team] = streak
			var _lost := award_team(
				team, rules.loss_bonus_for(streak), &"loss_bonus"
			)


## How many rounds in a row a team has lost. What a HUD shows as "bonus next round".
func loss_streak(team: int) -> int:
	return int(_streaks.get(team, 0))


func next_loss_bonus(team: int) -> int:
	return rules.loss_bonus_for(loss_streak(team) + 1)


## Sides swapped, or a new match. Resets balances if the rules say so.
func on_half_time() -> void:
	_streaks.clear()
	if not rules.reset_at_half:
		return
	for key: Variant in _accounts.keys():
		(_accounts[key] as DotEconomyAccount).reset(rules.start_money)
		balance_changed.emit(str(key), rules.start_money, 0, &"half_time")


func reset_all() -> void:
	_streaks.clear()
	for key: Variant in _accounts.keys():
		(_accounts[key] as DotEconomyAccount).reset(rules.start_money)


# --- Events a game reports ---------------------------------------------------

## Somebody killed somebody. Pays, or fines, whichever it was.
func on_kill(
	killer: String, victim: String, weapon: StringName = &""
) -> int:
	if killer == "":
		return 0

	if killer == victim:
		if rules.suicide_penalty > 0:
			return award(killer, -rules.suicide_penalty, &"suicide")
		return 0

	if team_fn.is_valid() and victim != "":
		var a := int(team_fn.call(killer))
		var b := int(team_fn.call(victim))
		if a > 0 and a == b:
			return award(killer, -rules.teamkill_penalty, &"teamkill")

	var amount := rules.kill_award
	if weapon != &"" and shop != null:
		var item := shop.item(weapon)
		if item != null:
			amount = item.award_for_kill(rules)

	if not rules.keep_on_death and victim != "":
		var acct := account(victim)
		var _lost := acct.debit(acct.balance)
		balance_changed.emit(victim, acct.balance, -_lost, &"died")

	return award(killer, amount, &"kill")


## A team did something the mode pays for: a plant, a capture, a rescue.
func on_objective(team: int, amount: int = -1) -> int:
	var pay := amount if amount >= 0 else rules.objective_award
	return award_team(team, pay, &"objective")


func advance(tick: int) -> void:
	_tick = tick
	if not authoritative:
		return
	if _buy_open and rules.buy_time_ticks > 0 and _round_start >= 0:
		if tick - _round_start >= rules.buy_time_ticks:
			_set_buy_open(false)


func _set_buy_open(open: bool) -> void:
	if _buy_open == open:
		return
	_buy_open = open
	buy_window.emit(open)


func _teams_present() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not team_fn.is_valid():
		return out
	for key in keys():
		var team := int(team_fn.call(key))
		if team > 0 and not out.has(team):
			out.append(team)
	# Sorted, so paying a round out is deterministic and two runs of a suite produce
	# the same order of signals.
	var sorted: Array = Array(out)
	sorted.sort()
	return PackedInt32Array(sorted)


# --- The wire ------------------------------------------------------------------

## One player's own economy. Deliberately not everybody's.
##
## A balance is private: knowing what the other side can afford is the single most
## valuable piece of information in this genre, and a server that broadcast every
## account would be handing it out. A game that wants to show a team-mate's money sends
## this to that team and no further.
func to_wire(key: String) -> Dictionary:
	var acct: DotEconomyAccount = _accounts.get(key, null)
	return {
		"k": key,
		"a": acct.to_wire() if acct != null else {"b": rules.start_money, "p": []},
		"o": _buy_open,
		"t": buy_ticks_remaining(),
	}


func apply_wire(w: Dictionary) -> void:
	var key := str(w.get("k", ""))
	if key == "":
		return
	var acct := account(key)
	var packed: Dictionary = w.get("a", {})
	acct.balance = int(packed.get("b", acct.balance))
	acct.purchases = (packed.get("p", []) as Array).duplicate(true)
	_set_buy_open(bool(w.get("o", _buy_open)))


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"items": shop.items.size() if shop != null else 0,
		"accounts": _accounts.size(),
		"buy_open": _buy_open,
		"tick": _tick,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"DotEconomyManager %s tick=%d buy=%s accounts=%d"
			% [
				"authoritative" if authoritative else "mirroring",
				_tick,
				("open (%d left)" % buy_ticks_remaining()) if _buy_open else "closed",
				_accounts.size(),
			]
	)
	for key in keys():
		var acct: DotEconomyAccount = _accounts[key]
		out.append(
			"  %-16s $%-6d bought %d this round"
				% [key, acct.balance, acct.purchases.size()]
		)
	var teams: Array = _streaks.keys()
	teams.sort()
	for team: Variant in teams:
		out.append(
			"  team %d: %d losses in a row, next bonus $%d"
				% [int(team), int(_streaks[team]), next_loss_bonus(int(team))]
		)
	return out
