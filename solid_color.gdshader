shader_type canvas_item;

uniform float flash_intensity;
uniform float r = 1; 
uniform float g = 1;
uniform float b = 1;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    COLOR = mix(tex_color, vec4(r,g,b, tex_color.a), flash_intensity);
}