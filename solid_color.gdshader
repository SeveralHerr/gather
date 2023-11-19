shader_type canvas_item;

uniform float flash_intensity;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    COLOR = mix(tex_color, vec4(1.0, 1.0, 1.0, tex_color.a), flash_intensity);
}