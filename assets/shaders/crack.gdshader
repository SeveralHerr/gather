shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D crack_texture: source_color;
uniform float threshold = 0.2;

void fragment() {

    vec4 crack = texture(crack_texture, UV * 1.0);
    vec4 sprite = texture(TEXTURE, UV);

    // This line creates the cracking effect, making the cracks appear based on the noise texture's value
    if (crack.r > threshold) {
        // If you want the cracks to be transparent, use the following line
        //sprite.a = 0.0;
        // If you want the cracks to be a certain color, uncomment the following line and set the color
        sprite.rgb = vec3(0.0, 0.0, 0.0); // Black color for the cracks
		//sprite.a = 0.0;
    }

    COLOR = sprite;
}
