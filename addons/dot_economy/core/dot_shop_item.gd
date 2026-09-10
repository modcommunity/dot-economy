@tool
class_name DotShopItem
extends Resource

## Something that can be bought, as a document with no content in it.
##
## [b]It is an id and a price, and deliberately not an item.[/b] What the id *means* is
## [DotItem]'s business in dot-loadout, or a weapon's in dot-combat, or a game's own —
## and a shop that resolved ids into things would be a shop that could not validate a
## purchase without loading a mesh. That is dot-loadout's rule and it is the same rule:
## a server checks what a player may have before anything is built.
##
## dot-economy therefore never imports dot-loadout, and a game wires the two together in
## about four lines: buy here, grant there.

@export var id: StringName = &""

@export var display_name: String = ""

@export_range(0, 1000000, 1) var price: int = 0

## Which teams may buy it. Empty means everybody.
##
## The Counter-Strike case, and it is a genuine rule rather than a cosmetic one: half
## the arsenal is one side's only.
@export var teams: PackedInt32Array = PackedInt32Array()

## What killing with this is worth, overriding
## [member DotEconomyRules.kill_award]. Negative means "use the default".
##
## Counter-Strike's most-copied economic idea: an AWP kill pays 100 and a knife kill
## pays 1500, so the cheapest way to make money is the riskiest thing you can do.
@export_range(-1, 100000, 1) var kill_award: int = -1

## How many may be bought per round. Zero means no limit.
@export_range(0, 64, 1) var per_round_limit: int = 0

## How many may be held at once, across rounds. Zero means no limit.
@export_range(0, 64, 1) var per_life_limit: int = 0

## Free-form labels. A buy menu's tabs, and what a "buy all grenades" command matches.
@export var tags: PackedStringArray = PackedStringArray()

## An id the player must already have bought. A scope for a rifle, ammunition for a gun.
@export var requires: StringName = &""

## Whether it can be given back inside the refund window.
@export var refundable: bool = true

## Which loadout slot it lands in, if the game has slots. Passed through untouched.
@export var slot: StringName = &""


static func make(
	p_id: StringName, p_price: int, p_name: String = ""
) -> DotShopItem:
	var item := DotShopItem.new()
	item.id = p_id
	item.price = p_price
	item.display_name = p_name if p_name != "" else String(p_id).capitalize()
	return item


func available_to(team: int) -> bool:
	if teams.is_empty():
		return true
	return teams.has(team)


func award_for_kill(rules: DotEconomyRules) -> int:
	if kill_award >= 0:
		return kill_award
	return rules.kill_award


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func validate() -> DotResult:
	if String(id).strip_edges() == "":
		return DotResult.fail(DotError.CODE_INVALID, "A shop item needs an id.")
	if price < 0:
		return DotResult.fail(
			DotError.CODE_INVALID, "Item '%s' has a negative price." % id
		)
	if requires == id:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Item '%s' requires itself, so it can never be bought." % id
		)
	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"price": price,
		"teams": Array(teams),
		"tags": Array(tags),
	}
