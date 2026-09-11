@tool
class_name DotEconomyRules
extends DotConfig

## Every number in a round-based economy, in one layered configuration.
##
## [b]The defaults are the round-based competitive shooters', and every one of them is
## load-bearing.[/b] A buy economy is the most carefully tuned system in that genre and
## the numbers are not roundable: 800 to start and 16000 as a ceiling is what makes the
## first round a pistol round and the fifth a full one; 1400 rising by 500 to 3400 is
## what stops a team that loses twice from losing the other thirteen.
##
## Where a value differs between the genre's early entries and their successors, this
## takes the later one and says so. The most visible is the loss bonus: the early ones
## keep [b]one[/b] shared counter for both teams, which produces the well-known case
## where breaking your own losing streak raises the other side's bonus. That is a bug
## that became a feature and then stopped being one; here each team has its own ladder.

@export_group("Balance")

## What everybody starts a match with. The genre's 800.
@export_range(0, 100000, 1) var start_money: int = 800

## The ceiling. Money above it is not banked, it is lost.
##
## The ceiling is what makes an economy a decision — without one, a team that saves
## twice can buy everything for ever and the mode has no shape.
@export_range(1, 1000000, 1) var max_money: int = 16000

## Whether a player keeps their balance through their own death.
##
## On. The genre's economy is per round, not per life: dying is punished by not having
## a gun next round, which is enough.
@export var keep_on_death: bool = true

## Whether balances reset when the sides swap at half time.
@export var reset_at_half: bool = true

@export_group("Awards")

## What a kill is worth when the weapon does not say.
##
## The genre prices this per weapon — 300 for a rifle, 100 for a high-calibre sniper
## rifle, 1500 for a knife — and [DotShopItem.kill_award] is where that lives. This is
## the fallback.
@export_range(0, 100000, 1) var kill_award: int = 300

## Taken from somebody who kills a team-mate. The genre's 3300.
@export_range(0, 100000, 1) var teamkill_penalty: int = 3300

## Taken from somebody who kills themselves.
@export_range(0, 100000, 1) var suicide_penalty: int = 0

## Paid to every member of the winning team.
@export_range(0, 100000, 1) var win_award: int = 3250

## The losing team's consolation, for the first loss in a streak.
@export_range(0, 100000, 1) var loss_bonus_base: int = 1400

## Added for each further consecutive loss.
@export_range(0, 100000, 1) var loss_bonus_step: int = 500

## The ceiling on the ladder. 1400, 1900, 2400, 2900, 3400 and no further.
@export_range(0, 100000, 1) var loss_bonus_max: int = 3400

## Whether a team's ladder resets to the bottom when it wins.
##
## On. Off makes a comeback permanent, which is a different game.
@export var loss_bonus_resets_on_win: bool = true

## Paid to a team for completing an objective, on top of anything the objective itself
## awards. What the genre pays for a plant that is then defused.
@export_range(0, 100000, 1) var objective_award: int = 300

@export_group("Buying")

## Ticks after a round starts during which buying is allowed. Zero means always.
##
## The genre's twenty seconds. It is what makes a buy a decision made under the same
## information as everybody else's rather than a reaction to what they bought.
@export_range(0, 1000000, 1) var buy_time_ticks: int = 1280

## Whether a player has to be standing in a buy zone.
##
## The game answers [member DotEconomyManager.in_buy_zone_fn]; this only says whether it
## is asked. Off for a game with no zones, which is most of them outside this genre.
@export var require_buy_zone: bool = true

## Whether a dead player may buy for next round. In the genre: no.
@export var allow_buying_while_dead: bool = false

## Ticks after a purchase during which it may be refunded in full.
##
## Zero disables refunds. The modern entries' five seconds, which exists because a
## misclick in the buy menu is a lost round and everybody has done it.
@export_range(0, 1000000, 1) var refund_ticks: int = 320

## How much of the price comes back. 1.0 is everything.
@export_range(0.0, 1.0, 0.01) var refund_fraction: float = 1.0

## Refunds are only allowed while the buy window is open.
##
## On. Otherwise a player refunds their rifle at the end of the round for money they
## keep, which is not a refund, it is a savings account with extra steps.
@export var refund_within_buy_time: bool = true


func env_prefix() -> String:
	return "DOT_ECONOMY_"


func cli_prefix() -> String:
	return "economy-"


func validate() -> DotResult:
	if start_money > max_money:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Everybody starts with %d against a ceiling of %d, so the first thing "
				+ "that happens is that everybody loses money."
			) % [start_money, max_money]
		)

	if loss_bonus_max < loss_bonus_base:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"The loss bonus ladder starts at %d and is capped at %d, so it goes "
				+ "down."
			) % [loss_bonus_base, loss_bonus_max]
		)

	if refund_ticks > 0 and buy_time_ticks > 0 and refund_within_buy_time \
			and refund_ticks > buy_time_ticks:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"The refund window (%d) is longer than the buy window (%d) and refunds "
				+ "are restricted to the buy window, so the last part of it can never "
				+ "be used. One of the two numbers is not the one that was meant."
			) % [refund_ticks, buy_time_ticks]
		)

	return DotResult.success(null)


## What a team gets for losing, given how many it has lost in a row.
##
## [param streak] is 1 for the first loss. The ladder is 1400, 1900, 2400, 2900, 3400.
func loss_bonus_for(streak: int) -> int:
	if streak <= 0:
		return 0
	var value := loss_bonus_base + loss_bonus_step * (streak - 1)
	return mini(value, loss_bonus_max)
