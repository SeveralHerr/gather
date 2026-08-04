shader_type canvas_item;

// The white hit flash.
//
// `tex_color.a *= COLOR.a` and NOT `tex_color *= COLOR`, and the difference is the whole
// comment. COLOR arrives holding the vertex colour, which is where Godot puts a CanvasItem's
// `modulate` AND the canvas-wide `CanvasModulate` that SkyLighting uses for the day/night
// tint. Multiplying all four channels therefore does two things at once, and only one of them
// is wanted:
//
//  - Alpha: makes `modulate:a` work. Enemy._death_pop tweens it to 0 so a corpse fades out;
//    with the original `COLOR = mix(texture(...), ...)` that tween drove a value nothing read,
//    so corpses popped out at full opacity — the very thing the tween was added to fix.
//  - RGB: would put the player and every enemy under the day/night tint for the first time.
//    They have never been, because this shader has always discarded COLOR, and folding them in
//    is a visible change to how the whole cast is lit rather than a bug fix. Measured on the
//    player: (0, 152, 220) before against (0, 91, 190) after, at the same hour.
//
// So alpha is taken and RGB is left alone. If the cast should take world lighting, that is a
// deliberate art decision and this is the line to change — but it is not a side effect to
// acquire while fixing a fade.
uniform float flash_intensity;
uniform float r = 1;
uniform float g = 1;
uniform float b = 1;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    tex_color.a *= COLOR.a;
    COLOR = mix(tex_color, vec4(r, g, b, tex_color.a), flash_intensity);
}
