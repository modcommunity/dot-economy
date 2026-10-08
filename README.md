This is the **economy** asset for TMC's **Dot** collection. It adds a round-based buy economy: money, a shop, a buy window, refunds, and more.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
Every player has a balance. A round opens a buy window, and players spend money in the shop while it is open (and, by default, while standing in a buy zone). Kills, round wins and objectives pay out. A team that keeps losing gets a growing loss bonus, so it can still afford to buy. A purchase can be refunded for a short time after it was made.

The shop sells ids. It does not hand out weapons or items itself: when somebody buys something, the `bought` signal fires and your game grants it. This means a server can check a purchase without having the item's scenes or models loaded.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_economy/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it and enable dot-economy in **Project → Project Settings → Plugins**. dot-core is the only dependency.

## Using it

```gdscript
var economy := DotEconomyManager.new()
economy.team_fn = match_node.team_of
economy.alive_fn = world.is_alive
economy.in_buy_zone_fn = func(key): return world.in_buy_zone(key)
economy.setup(shop_items)           # an Array[DotShopItem]
add_child(economy)

economy.bought.connect(func(key, id, price, balance):
    loadouts.grant(key, id))

economy.on_round_start(tick)        # opens the buy window
economy.advance(tick)               # closes it when the buy time runs out
economy.buy("ada", &"rifle")        # a DotResult; bought fires if it went through
economy.on_kill("ada", "bob", &"rifle")
economy.on_round_end(winning_team)  # pays the winners and the loss bonus; 0 is a draw
```

`team_fn` has to be set. Without it nobody is paid at the end of a round, and a warning says so. Teams are numbered from 1, because team 0 means nobody.

A buy menu can ask whether a purchase would go through before it draws the button:

```gdscript
var why := economy.may_buy(key, &"sniper")
button.disabled = not why.ok
button.tooltip_text = "" if why.ok else why.error.message
```

Each `DotShopItem` has an `id`, a `price`, the `teams` that may buy it, per-round and per-life limits, an item it `requires` first, whether it is `refundable`, and an optional `kill_award` that replaces the default for kills made with it. A knife kill can pay 1500 and a sniper kill 100, for example.

The other signals are `refunded`, `balance_changed` (with a reason such as `kill` or `loss_bonus`), `buy_window` (open or closed) and `award_capped`, which fires when money was lost to the ceiling so a HUD does not show more than landed.

A balance is private. `to_wire(key)` gives one player's account and `apply_wire()` loads it on their client, where the manager has `authoritative` set to false.

## Settings
The rules live in a `DotEconomyRules` resource, set on the manager's `rules` (it makes a default one if you do not). Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before `setup()` to apply them:

```gdscript
var rules := DotEconomyRules.new()
rules.load_layered("user://economy.json")
economy.rules = rules
```

```bash
DOT_ECONOMY_START_MONEY=1000 godot --headless -- --economy-max-money=9000
```

Ticks depend on your tick rate. The defaults below assume 64 ticks a second.

| Setting | Default | What it does |
| --- | --- | --- |
| `start_money` | 800 | Balance at the start of a match |
| `max_money` | 16000 | Most a player can hold |
| `keep_on_death` | true | Keep your balance when you die |
| `reset_at_half` | true | Everybody goes back to `start_money` at half time |
| `kill_award` | 300 | Paid for a kill, unless the weapon sets its own |
| `teamkill_penalty` | 3300 | Taken for killing a teammate |
| `suicide_penalty` | 0 | Taken for killing yourself |
| `win_award` | 3250 | Paid to each player on the winning team |
| `loss_bonus_base` | 1400 | Paid to each player on the losing team |
| `loss_bonus_step` | 500 | Added to the loss bonus for each loss in a row |
| `loss_bonus_max` | 3400 | Highest the loss bonus goes |
| `loss_bonus_resets_on_win` | true | A win resets the losing streak |
| `objective_award` | 300 | Paid to each player on a team that completes an objective |
| `buy_time_ticks` | 1280 | How long the buy window stays open (20 seconds). 0 keeps it open all round |
| `require_buy_zone` | true | Only buy while standing in a buy zone |
| `allow_buying_while_dead` | false | Let dead players buy |
| `refund_ticks` | 320 | How long after a purchase it can be refunded (5 seconds). 0 turns refunds off |
| `refund_fraction` | 1.0 | Share of the price a refund gives back |
| `refund_within_buy_time` | true | Refunds only while the buy window is open |

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/economy_selftest.tscn
```

The self-test covers balances and the ceiling, the buy window, buy zones, per-round and per-life limits, refunds, kill and round awards, the loss bonus ladder, half time and the network form of an account.

## License
MIT. See [LICENSE](LICENSE).
