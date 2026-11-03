shader_type spatial;

uniform vec4 stone_color : source_color = vec4(0.48, 0.47, 0.42, 1.0);
uniform float tile_size = 0.6;
varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = world_position.xz / tile_size;
	vec2 f = fract(uv);
	vec2 edge = min(f, 1.0 - f);
	float distance_to_grout = min(edge.x, edge.y);
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	float grout = 1.0 - smoothstep(0.005 / tile_size, 0.009 / tile_size + aa, distance_to_grout);
	float tile_variation = hash(floor(uv)) * 0.12 - 0.06;
	float aggregate = noise(world_position.xz * 95.0);
	float fine_visible = 1.0 - smoothstep(0.012, 0.04, length(fwidth(world_position.xz)));
	float fleck = smoothstep(0.62, 0.83, aggregate) * fine_visible;
	float grain = (aggregate - 0.5) * 0.09 * fine_visible;
	float wear = noise(world_position.xz * 1.7) * 0.065;
	vec3 stone = stone_color.rgb * (1.0 + tile_variation + grain - wear);
	stone = mix(stone, vec3(0.26, 0.25, 0.22), fleck * 0.45);
	ALBEDO = mix(stone, stone_color.rgb * 0.46, grout);
	ROUGHNESS = mix(0.76, 0.96, grout);
	SPECULAR = 0.22;
	// Shallow bevel catches flashlight light along each tile edge.
	vec2 slope = (step(f, vec2(0.5)) * 2.0 - 1.0) * (1.0 - smoothstep(vec2(0.012), vec2(0.03), edge));
	NORMAL_MAP = normalize(vec3(slope * 0.25, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.55;
}
