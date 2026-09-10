class_name DotShop
extends RefCounted

## What a server sells, as a catalogue it can validate at boot.
##
## The same shape as [DotItemCatalogue], [DotNpcCatalogue] and [DotPropCatalogue], for
## the same reason: a catalogue that can be checked without loading anything is one a
## server checks at boot, in a headless process, at the only moment anybody is watching.

var items: Array[DotShopItem] = []

var _by_id: Dictionary = {}


static func of(p_items: Array[DotShopItem]) -> DotResult:
	var shop := DotShop.new()
	var res := shop.rebuild(p_items)
	if not res.ok:
		return res
	return DotResult.success(shop)


func rebuild(p_items: Array[DotShopItem]) -> DotResult:
	items.clear()
	_by_id.clear()

	for item in p_items:
		var res := add(item)
		if not res.ok:
			return res

	# Requirements are checked after everything is in, because an item may legitimately
	# require one declared later in the list and refusing that would make the order of
	# a catalogue file part of its meaning.
	for item in items:
		if item.requires == &"":
			continue
		if not _by_id.has(item.requires):
			return DotResult.fail(
				DotError.CODE_INVALID,
				(
					"Item '%s' requires '%s', which is not in the shop — so it can "
					+ "never be bought, and nothing would say why."
				) % [item.id, item.requires]
			)

	return DotResult.success(null)


func add(item: DotShopItem) -> DotResult:
	if item == null:
		return DotResult.fail(DotError.CODE_INVALID, "A null shop item.")
	var res := item.validate()
	if not res.ok:
		return res
	if _by_id.has(item.id):
		return DotResult.fail(
			DotError.CODE_INVALID, "Two shop items are called '%s'." % item.id
		)
	_by_id[item.id] = item
	items.append(item)
	return DotResult.success(null)


func item(id: StringName) -> DotShopItem:
	return _by_id.get(id, null)


func has(id: StringName) -> bool:
	return _by_id.has(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for item in items:
		out.append(item.id)
	return out


## Everything one team may buy, cheapest first.
##
## Ordered here rather than in a menu, because every menu that draws this wants the same
## order and a menu that sorts it itself is a second copy of the rule.
func for_team(team: int) -> Array[DotShopItem]:
	var out: Array[DotShopItem] = []
	for item in items:
		if item.available_to(team):
			out.append(item)
	out.sort_custom(func(a: DotShopItem, b: DotShopItem) -> bool:
		if a.price != b.price:
			return a.price < b.price
		return String(a.id) < String(b.id))
	return out


func with_tag(tag: String) -> Array[DotShopItem]:
	var out: Array[DotShopItem] = []
	for item in items:
		if item.has_tag(tag):
			out.append(item)
	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("shop: %d items" % items.size())
	for item in items:
		out.append(
			"  %-20s %6d %s"
				% [
					item.id, item.price,
					"" if item.teams.is_empty() else str(Array(item.teams)),
				]
		)
	return out
