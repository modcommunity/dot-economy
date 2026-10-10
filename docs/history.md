# dot-economy history

## A zero buy time meant no buying

Found by running it. `buy_time_ticks == 0` means "no timer", and the round start read it as "no buying": `_set_buy_open(rules.buy_time_ticks != 0)` was the wrong condition by one negation. The configuration it broke is the one a game without a buy timer uses: a sandbox shop, a deathmatch with a permanent buy menu, every game in this family that is not a round-based buy game. Nothing errored: every refusal correctly reported "the buy window is closed", which is a true statement about a state that should never have been reached. `on_round_start` now always opens the window and lets `advance()` close it.
