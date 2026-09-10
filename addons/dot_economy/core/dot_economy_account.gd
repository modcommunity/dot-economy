class_name DotEconomyAccount
extends RefCounted

## One player's money, and what they have spent it on this round.
##
## Keyed by the same [code]String[/code] key dot-match scores by, and for the same
## reason dot-moderation exists: a peer id dies with its connection, so an economy keyed
## on one hands a reconnecting player a fresh 800 in the middle of a half.

var key: String = ""

var balance: int = 0

## Everything bought since the round began: [code][{id, price, tick}][/code].
## What a refund reads and what a "you bought" summary draws.
var purchases: Array[Dictionary] = []

## Everything held across rounds, per item id, for [member DotShopItem.per_life_limit].
var held: Dictionary = {}

## Lifetime figures, for dot-stats and for a scoreboard column.
var earned: int = 0
var spent: int = 0


func _init(p_key: String = "", p_balance: int = 0) -> void:
	key = p_key
	balance = p_balance


## Add money, respecting a ceiling. Returns what actually landed.
##
## The difference matters: a game that shows "+3250" when 900 landed has told the player
## something untrue about a system they are supposed to be planning around.
func credit(amount: int, ceiling: int) -> int:
	if amount <= 0:
		return 0
	var room := maxi(ceiling - balance, 0)
	var landed := mini(amount, room)
	balance += landed
	earned += landed
	return landed


## Take money. Never below zero, and returns what was actually taken.
func debit(amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, balance)
	balance -= taken
	spent += taken
	return taken


func can_afford(price: int) -> bool:
	return balance >= price


func note_purchase(id: StringName, price: int, tick: int) -> void:
	purchases.append({"id": String(id), "price": price, "tick": tick})
	held[id] = int(held.get(id, 0)) + 1


func bought_this_round(id: StringName) -> int:
	var n := 0
	for row in purchases:
		if StringName(str(row["id"])) == id:
			n += 1
	return n


func holding(id: StringName) -> int:
	return int(held.get(id, 0))


## The most recent purchase of an id, or an empty dictionary.
func last_purchase(id: StringName) -> Dictionary:
	for i in range(purchases.size() - 1, -1, -1):
		if StringName(str(purchases[i]["id"])) == id:
			# Duplicated, not handed out. A Dictionary is a reference in GDScript and
			# this family has shipped that bug five times.
			return (purchases[i] as Dictionary).duplicate()
	return {}


func forget_purchase(id: StringName) -> bool:
	for i in range(purchases.size() - 1, -1, -1):
		if StringName(str(purchases[i]["id"])) != id:
			continue
		purchases.remove_at(i)
		var have := int(held.get(id, 0)) - 1
		if have <= 0:
			held.erase(id)
		else:
			held[id] = have
		return true
	return false


## A new round: the purchase list starts again, the balance does not.
func begin_round() -> void:
	purchases.clear()


## A new half or a new match.
func reset(to: int) -> void:
	balance = to
	purchases.clear()
	held.clear()


func describe() -> Dictionary:
	return {
		"key": key,
		"balance": balance,
		"purchases": purchases.size(),
		"earned": earned,
		"spent": spent,
	}


func to_wire() -> Dictionary:
	return {"b": balance, "p": purchases.duplicate(true)}


func _to_string() -> String:
	return "DotEconomyAccount(%s $%d)" % [key, balance]
