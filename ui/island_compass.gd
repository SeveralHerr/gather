extends Control
class_name IslandCompass

## Edge markers pointing at the islands the player cannot see.
##
## The viewport is 1920x1080 at camera zoom 8, so about 15x8 tiles are on screen at
## once. The nearest island sits 20 tiles from the home island's centre and the furthest
## 36, which means all three are off screen from anywhere the player can stand early on.
## Without a marker they are not content the player has not reached yet - they are content
## the player has no idea exists, until they happen to buy enough land and wander far
## enough in the right direction.
##
## Each marker is pinned to the screen edge in the island's direction and carries its
## distance in tiles, so the islands read as somewhere to go rather than as a surprise.

## Colour per island id, and the fallback for anything added to IslandManager.ISLANDS
## later without a colour of its own.
const MARKER_COLORS := {
	"forest": Color("4a9c3f"),
	"ore": Color("c88a3a"),
	"boss": Color("c04040"),
}
const DEFAULT_COLOR := Color("d0d0d0")

## How far in from the viewport edge a marker sits, and how big it is drawn. Both in
## screen pixels, and both independent of window size - the markers are HUD furniture,
## not world objects, so they must not scale with the camera.
const EDGE_MARGIN := 46.0
const MARKER_RADIUS := 11.0

## A marker only appears once the island is genuinely off screen; inside this band the
## island itself is visible and an arrow pointing at it would just be clutter.
const ON_SCREEN_PADDING := 24.0

const TILE_SIZE := 16.0

var tile_map_handler: TileMapHandler
var island_manager: IslandManager

var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The compass sits over the whole screen; without this it would swallow every click
	# meant for the world or for the panels underneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if island_manager == null or tile_map_handler == null:
		return

	var player := PlayerManager.player
	if player == null:
		return

	var to_screen := get_viewport().get_canvas_transform()
	var view := get_viewport_rect().size

	for id in island_manager.islands:
		var island: Dictionary = island_manager.islands[id]
		var world: Vector2 = tile_map_handler.tileMap.map_to_local(island["centre"])
		var screen_point: Vector2 = to_screen * world

		if _is_on_screen(screen_point, view):
			continue

		var tiles_away := int(player.global_position.distance_to(world) / TILE_SIZE)
		_draw_marker(id, screen_point, view, tiles_away)


func _is_on_screen(point: Vector2, view: Vector2) -> bool:
	return (
		point.x > ON_SCREEN_PADDING
		and point.y > ON_SCREEN_PADDING
		and point.x < view.x - ON_SCREEN_PADDING
		and point.y < view.y - ON_SCREEN_PADDING
	)


## Where an off-screen point's marker goes: along the line from the middle of the screen
## toward it, stopped at the edge. Computed from the viewport rect every frame rather than
## from a stored size, so it stays correct when the window is resized - the window is
## explicitly not stretched, so growing it reveals more world and moves every one of these.
func _draw_marker(id: String, target: Vector2, view: Vector2, tiles_away: int) -> void:
	var centre := view * 0.5
	var direction := (target - centre)
	if direction.length() < 0.001:
		return
	direction = direction.normalized()

	var usable := centre - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	# The distance along `direction` at which it first leaves the box, i.e. whichever axis
	# runs out first.
	var scale_x: float = usable.x / absf(direction.x) if absf(direction.x) > 0.001 else INF
	var scale_y: float = usable.y / absf(direction.y) if absf(direction.y) > 0.001 else INF
	var at := centre + direction * minf(scale_x, scale_y)

	var color: Color = MARKER_COLORS.get(id, DEFAULT_COLOR)

	draw_circle(at, MARKER_RADIUS, Color(0, 0, 0, 0.45))
	draw_circle(at, MARKER_RADIUS - 2.0, color)

	# A triangle on the outer side of the dot, so the marker reads as pointing rather than
	# merely sitting there.
	var tip := at + direction * (MARKER_RADIUS + 8.0)
	var across := Vector2(-direction.y, direction.x) * 6.0
	draw_colored_polygon(
		PackedVector2Array([tip, at + direction * MARKER_RADIUS + across, at + direction * MARKER_RADIUS - across]),
		color
	)

	var label := "%dm" % tiles_away
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var text_at := at - direction * 0.0 + Vector2(-text_size.x * 0.5, MARKER_RADIUS + text_size.y + 2.0)
	draw_string(_font, text_at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.6))
	draw_string(_font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
