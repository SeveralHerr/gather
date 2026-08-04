shader_type canvas_item;

// The white hit flash, and — since gather-8ft — anything that tints one of these sprites.
//
// `tex_color` is multiplied by COLOR before the mix, and that multiply is load-bearing. In a
// canvas_item fragment shader COLOR arrives holding the vertex colour, which is where Godot
// puts a CanvasItem's `modulate`. The original wrote `COLOR = mix(texture(...), ...)` and threw
// that away, so `modulate` on any node using this material did nothing at all — silently, with
// the property still reading back exactly what had been assigned to it.
//
// Two things were broken by that and both looked like bugs somewhere else:
//
//  - The charged skeleton's blue (enemies/charged_bone_enemy.tscn sets Sprite2D.modulate) never
//    appeared. Every property read said the tint was applied, because it was — it just never
//    reached the fragment.
//  - `Enemy._death_pop` tweens `modulate:a` to 0 so a corpse fades. It could not, so corpses
//    still popped out at full opacity, which is the very thing that tween was added to fix.
//
// The flash itself is unchanged: at flash_intensity 0 this is texture * modulate, which is what
// the default canvas_item fragment does anyway, and at 1 it is the solid flash colour.
uniform float flash_intensity;
uniform float r = 1;
uniform float g = 1;
uniform float b = 1;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV) * COLOR;
    COLOR = mix(tex_color, vec4(r, g, b, tex_color.a), flash_intensity);
}
