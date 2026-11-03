shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec2 uv = (floor(SCREEN_UV / SCREEN_PIXEL_SIZE / 2.0) + 0.5) * SCREEN_PIXEL_SIZE * 2.0;
	vec3 color = texture(screen_texture, uv).rgb;
	float dither = (mod(floor(FRAGCOORD.x), 2.0) * 2.0 + mod(floor(FRAGCOORD.y), 2.0)) / 4.0 - 0.375;
	COLOR = vec4(clamp(floor(color * 28.0 + dither * 0.6) / 28.0, 0.0, 1.0), 1.0);
}
