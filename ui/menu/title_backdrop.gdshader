shader_type canvas_item;
render_mode unshaded;

// Render the original lettering unchanged; replace only the surrounding paper.
uniform vec4 background_color : source_color = vec4(0.018, 0.022, 0.021, 1.0);
const float LEFT[8] = float[8](41.0, 145.0, 249.0, 354.0, 458.0, 562.0, 666.0, 771.0);

float rounded_box(vec2 point, vec2 center, vec2 half_size, float radius) {
	vec2 q = abs(point - center) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 point = UV * vec2(1920.0, 1080.0);
	float distance_to_tile = 10000.0;
	for (int index = 0; index < 8; index++) {
		distance_to_tile = min(distance_to_tile, rounded_box(point, vec2(LEFT[index] + 49.5, 166.0), vec2(49.5, 77.0), 8.0));
	}
	vec3 artwork = texture(TEXTURE, UV).rgb;
	float outline = smoothstep(-2.0, -0.5, distance_to_tile);
	artwork = mix(artwork, vec3(0.13, 0.145, 0.14), outline);
	float mask = 1.0 - smoothstep(-0.5, 0.8, distance_to_tile);
	COLOR = vec4(mix(background_color.rgb, artwork, mask), 1.0);
}
