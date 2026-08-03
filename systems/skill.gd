class_name Skill
# RefCounted, not Node: skills are pure data built by SkillTree and held in a
# dictionary. Nothing ever adds one to the tree, so making them Nodes would leak
# one object per definition the way HealthManager used to.
extends RefCounted

## Stable identifier. This is what the save file stores, so renaming one breaks
## every existing save's taken set — add a new id instead.
var id: String

## Which column of the panel this sits in, and how far down that column. Tier is
## also the visual row, so two skills in the same branch must not share one.
##
## Tier is also the price: see cost().
var branch: String
var tier: int

var display_name: String

## Full sentence for the detail pane at the bottom of the panel.
var description: String

## Short label printed on the node card itself. Authored rather than derived from
## `effects` so each one can be worded for its node; keep it under ~22 characters
## or the four columns start wrapping.
var summary: String

## Item whose atlas tile is used as the node icon, so skill art comes from the
## existing spritesheet rather than a second set of assets to keep in sync.
var icon: Types.Item

## Ids that must already be taken. Empty means the node is offered from the start.
var requires: Array[String] = []

## Stat name -> delta, summed by PlayerStats over every taken skill. Keys must
## match a field on PlayerStats; unknown keys are reported rather than ignored.
var effects: Dictionary = {}

## Recipes this skill adds, as {"product": Types.Item, "station": Types.Item}.
var recipes: Array = []

## Resource types this skill starts spawning in the world.
var resources: Array = []


func _init(
		_id: String,
		_branch: String,
		_tier: int,
		_display_name: String,
		_description: String,
		_summary: String,
		_icon: Types.Item,
		_requires: Array[String] = [],
		_effects: Dictionary = {},
		_recipes: Array = [],
		_resources: Array = []
	):
	self.id = _id
	self.branch = _branch
	self.tier = _tier
	self.display_name = _display_name
	self.description = _description
	self.summary = _summary
	self.icon = _icon
	self.requires = _requires
	self.effects = _effects
	self.recipes = _recipes
	self.resources = _resources


## What this skill costs in banked skill points.
##
## Derived from the tier rather than authored per skill, deliberately: the price is a
## statement about depth, and a hand-written number per node is a number that drifts out
## of step with the row it is drawn in. tier 0 -> 1 point, tier 3 -> 4.
##
## Before this, every node cost exactly one point, so the whole 16-node tree cost 16
## points and clearing it took 578 XP — a capstone was priced like an opener, and four
## points into one branch bought its capstone outright. That is what made the Industry
## beeline to gold the dominant opening (`gather-7p4`). Charging by depth makes the tree
## 40 points without touching the XP curve, so the *opening* is unchanged (the first
## skill still costs one point at 40 XP) and only depth got expensive.
func cost() -> int:
	return tier + 1


## True when this node changes nothing about the player's numbers — used by the UI
## to label a node as an unlock rather than a bonus.
func is_unlock() -> bool:
	return effects.is_empty()
