This is the **economy** asset for TMC's **Dot** collection. It adds a round-based buy economy: money, a shop, a buy window, refunds, and more.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Why the numbers matter
A buy economy looks arbitrary and is not. Every default here is a number the round-based competitive shooters have converged on over twenty years, and each one is load-bearing:

- **800 to start, 16000 as a ceiling.** The first round is a pistol round, the second is a decision, the fifth is a full buy. Remove the ceiling and a team that saves twice buys everything for ever.
- **A loss bonus of 1400 rising by 500 to 3400.** Without it the losing team is poorer *because* they are losing, which is a feedback loop with one outcome.
- **A sniper-rifle kill pays 100 and a knife kill pays 1500.** The cheapest way to make money is the riskiest thing you can do.

## It sells ids and grants nothing

```gdscript
economy.bought.connect(func(key, id, price, balance):
    loadouts.grant(key, id))          # or an arsenal, or a boolean
```

A shop item has no scene, no mesh and no `DotItem` in it, so a purchase validates on a server that does not have the content, which is the same rule `dot-loadout` is built on.

## Using it

```gdscript
var economy := DotEconomyManager.new()
economy.team_fn = match_node.team_of
economy.alive_fn = world.is_alive
economy.in_buy_zone_fn = func(key): return world.in_buy_zone(key)
economy.setup(arsenal)
add_child(economy)

economy.on_round_start(tick)        # opens the buy window
economy.advance(tick)               # closes it on time
economy.on_kill("ada", "bob", &"rifle")
economy.on_round_end(winning_team)  # pays the winners and the ladder
```

A buy menu asks before it draws:

```gdscript
var why := economy.may_buy(key, &"sniper")
button.disabled = not why.ok
button.tooltip_text = "" if why.ok else why.error.message
```

## Installing

Copy `addons/dot_economy/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-economy in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## License

MIT.
