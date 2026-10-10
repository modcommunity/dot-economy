# dot-economy design

Why the addon exists, why the defaults are what they are, and the decisions that look arbitrary and are not. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## Why this exists

[dot-loadout](../../dot-loadout) answers "what may this player take in", as a document validated against a schema and entitlements. That is the *permanent* question: what you own, what you have unlocked. It has no answer at all for the *per-round* one: what you can afford this round, given how the last one went.

That question is the whole of the round-based buy genre. It is also the system most commonly reimplemented badly, because the numbers look arbitrary and are not:

- **800 to start and 16000 as a ceiling** (`start_money`, `max_money`) is what makes the first round a pistol round, the second a decision, and the fifth a full buy. Remove the ceiling and a team that saves twice can buy everything for ever; the mode loses its shape.
- **1400 rising by 500 to 3400** (`loss_bonus_base`, `loss_bonus_step`, `loss_bonus_max`) is what stops a team that loses two rounds from losing the rest. Without a ladder the losing team is poorer *because* they are losing, which is a feedback loop with only one outcome.
- **A per-item kill award** (`DotShopItem.kill_award`, -1 meaning the rules' default): in the genre a high-calibre sniper rifle kill pays 100 and a knife kill pays 1500. The cheapest way to make money is the riskiest thing you can do, which is the single most-copied economic idea in the genre.

## The one idea: a shop item is an id and a price

`DotShopItem` has no scene, no mesh, no `DotItem` and no `DotWeaponDef` in it. `bought` carries an id and the game does whatever that means: grant a `DotItem` through dot-loadout, give a weapon id to a `DotWeaponArsenal`, set a boolean.

That is dot-loadout's own rule for dot-loadout's own reason: **a purchase has to validate without loading anything**, because the validation happens on a server that may not have the content, at boot, in a headless process. It is also why dot-economy imports neither dot-loadout nor dot-combat, and why a game wires them together itself in a few lines.

## Decisions

### The loss bonus is per team

The genre's early entries kept **one** loser-bonus counter shared between both sides, which produces the well-known case where breaking your own losing streak raises the other team's bonus. That was a bug that became a feature and then stopped being one. Here each team has its own ladder, which is what every game since does.

### A draw pays nobody and moves no streak

`on_round_end(0)` is a draw. Counting a draw as a loss for both sides hands both a bonus; counting it as a win for both resets both ladders. Neither is what a draw means, and a mode with a draw condition that does either has an economy that drifts every time one happens.

### Money that could not land is reported

`award_capped(key, wanted, landed)` fires when an account is at the ceiling. A game that shows "+3250" when 900 landed has told the player something untrue about a system they are supposed to be planning around, and the ceiling is exactly the thing they are planning around.

### `may_buy` is public and separate from `buy`

A buy menu has to grey out what cannot be bought and say why. A menu that reimplements the test is a menu that disagrees with the server about what is for sale.

### Refunds close with the buy window

Otherwise a player sells their rifle at the end of the round for money they keep, which is not a refund, it is a savings account with extra steps. `refund_within_buy_time` is on, and `DotEconomyRules.validate()` refuses a `refund_ticks` longer than the `buy_time_ticks` it is restricted to.

### A zero buy time means no timer, not no buying

`buy_time_ticks == 0` means the window never closes on its own. The round start always opens the window and `advance()` is what closes it. Reading zero as a condition at round start is the bug in [history](history.md#a-zero-buy-time-meant-no-buying).

### A balance is private, and `to_wire` is per player

Knowing what the other side can afford is the single most valuable piece of information in this genre. A manager that offered "everybody's economy" as one wire form would have made that decision for the game; this one makes the game make it.

### Keyed by `String`, like dot-match

Not a peer id. dot-moderation exists because a peer id dies with its connection, and an economy keyed on one hands a reconnecting player a fresh 800 in the middle of a half.

## Things deliberately not here

- **No buy menu.** dot-ui's rule. `DotShop.for_team()` returns the list, cheapest first, so that every menu drawing it agrees about the order.
- **No granting.** See above; this is the design.
- **No persistent currency.** Money here is per match. A currency that survives a disconnect is an account balance and belongs behind an authenticated backbone, which is dot-auth and dot-stats, and a "buy" against one is a transaction, not a game rule.
- **No per-weapon ammunition economy.** The genre buys ammunition with the gun. A game that wants it declares an item with `requires` set.
- **No auto-buy or rebuy.** They are a client convenience built on `may_buy` and a stored list, and the list is a preference, which is dot-user's.
