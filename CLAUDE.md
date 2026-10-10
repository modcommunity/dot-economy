# dot-economy

A round-based buy economy: money, a shop, a buy window, refunds, and a per-team loss-bonus ladder. **It sells ids and grants nothing**: `bought` carries an id and the game decides what that means.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_economy/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored). It imports neither dot-loadout nor dot-combat.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing a default or a rule: why the numbers, ids not items, the decisions, what is deliberately not here |
| [docs/history.md](docs/history.md) | touching the buy window |

## Layout

| Path | What |
| --- | --- |
| `core/dot_economy_rules.gd` | `DotEconomyRules`: every number (balance, awards, loss ladder, buy and refund windows), a layered `DotConfig` |
| `core/dot_shop_item.gd` | `DotShopItem`: id, price, teams, `kill_award`, per-round and per-life limits, `requires`, `refundable` |
| `core/dot_shop.gd` | `DotShop`: the catalogue, validated at boot; `for_team()` cheapest first |
| `core/dot_economy_account.gd` | `DotEconomyAccount`: one player's money and this round's purchases |
| `runtime/dot_economy_manager.gd` | `DotEconomyManager`: the one node a game holds; `may_buy`, `buy`, `refund`, `award`, round hooks, `to_wire(key)` |
| `examples/economy_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_economy/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/economy_selftest.tscn`.

## Rules that bite

- A shop item is an id and a price; never put a scene, item or weapon in it. A purchase validates without loading anything. [design](docs/design.md#the-one-idea-a-shop-item-is-an-id-and-a-price)
- The loss bonus is per team, never one shared counter. [design](docs/design.md#the-loss-bonus-is-per-team)
- A draw (`on_round_end(0)`) pays nobody and moves no streak. [design](docs/design.md#a-draw-pays-nobody-and-moves-no-streak)
- Money that hit the ceiling emits `award_capped`; show what landed. [design](docs/design.md#money-that-could-not-land-is-reported)
- Menus call `may_buy`, never their own copy of the test. [design](docs/design.md#may_buy-is-public-and-separate-from-buy)
- Refunds close with the buy window; `validate()` refuses a refund window longer than it. [design](docs/design.md#refunds-close-with-the-buy-window)
- `buy_time_ticks == 0` means no timer, not no buying. [design](docs/design.md#a-zero-buy-time-means-no-timer-not-no-buying)
- `to_wire` is per player: a balance is private. [design](docs/design.md#a-balance-is-private-and-to_wire-is-per-player)
- Accounts are keyed by `String`, never a peer id. [design](docs/design.md#keyed-by-string-like-dot-match)

Deliberately not here: a buy menu, granting, persistent currency, an ammunition economy, auto-buy. [design](docs/design.md#things-deliberately-not-here)
