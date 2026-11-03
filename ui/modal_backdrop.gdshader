shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	vec3 scene = textureLod(screen_texture, SCREEN_UV, 2.3).rgb;
	float vignette = smoothstep(0.15, 0.85, length(SCREEN_UV - vec2(0.5)));
	COLOR = vec4(mix(scene, vec3(0.012, 0.018, 0.021), 0.52 + vignette * 0.22), 1.0);
}
