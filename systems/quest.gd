class_name Quest
# RefCounted, not Node: quests are pure data built by QuestBoard and held in a dictionary.
# Nothing ever adds one to the tree, so making them Nodes would leak one object per definition
# the way HealthManager used to.
extends RefCounted

## What a quest measures. Every kind is a question about state the game ALREADY tracks, and that
## is the whole design of the quest system — see the class comment on `QuestBoard`.
##
## `HAVE` is the only one that is not a high-water mark: it asks what is in the bag right now,
## and claiming spends it. The others read a counter that never goes down.
enum Kind {
	HAVE,     ## Carry `amount` of `item`. Claiming CONSUMES them.
	KILL,     ## `amount` enemies killed this run.
	RAID,     ## `amount` night raids cleared.
	DAY,      ## Reach day `amount`.
	LEVEL,    ## Reach level `amount`.
	PARCEL,   ## `amount` parcels of land bought.
}

## Stable identifier. This is what the save file stores in the claimed set, so renaming one makes
## an existing save forget that quest was done — add a new id instead.
var id: String

var kind: Kind

## The item a HAVE quest wants. Ignored by every other kind, and `Types.Item.Wood` there is a
## placeholder rather than a meaning.
var item: Types.Item

## How many. Of the item for HAVE; of kills, raids, days, levels or parcels otherwise.
var amount: int

var display_name: String

## One sentence for the card. Written in the board's voice — it is the only flavour text in the
## game and it is doing the job of a tutorial, so it says why as well as what.
var description: String

## The reward. Coins because land is what the player is saving for; xp because the level curve
## should notice that a quest was done.
##
## Deliberately NOT recipe or resource unlocks, even though `Skill` carries those. Unlocks have
## to be applied exactly once and never on load — `Recipes` and `ResourceManager2` persist their
## own lists, so replaying them appends every recipe twice (see the skill-tree note in
## CLAUDE.md). Coins and xp have no such rule: they are paid into the world once and the world
## saves them like anything else.
var reward_coins: int
var reward_xp: int

## Ids that must already be claimed before this one is offered. Empty means it is offered from
## the start. Chains exist so the board reads as a curriculum rather than a wall of tasks.
var requires: Array[String] = []


func _init(
		_id: String,
		_kind: Kind,
		_amount: int,
		_display_name: String,
		_description: String,
		_reward_coins: int,
		_reward_xp: int,
		_item: Types.Item = Types.Item.Wood,
		_requires: Array[String] = []
	):
	self.id = _id
	self.kind = _kind
	self.amount = _amount
	self.display_name = _display_name
	self.description = _description
	self.reward_coins = _reward_coins
	self.reward_xp = _reward_xp
	self.item = _item
	self.requires = _requires


## Whether claiming this quest takes something off the player. Only HAVE does, and the panel says
## so on the button — a player who does not know the planks are about to vanish will be annoyed
## exactly once and never trust the board again.
func consumes() -> bool:
	return kind == Kind.HAVE
