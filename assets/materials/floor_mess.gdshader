shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform float stain_seed = 1.0;
uniform vec4 dirt_color : source_color = vec4(0.23, 0.17, 0.10, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + stain_seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x), mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV - 0.5;
	float grain = noise(UV * 80.0);
	float blotch = noise(UV * 11.0) * 0.13 + noise(UV * 26.0) * 0.045;
	float shape = min(length(p * vec2(1.0, 1.35)), length((p - vec2(0.16, -0.10)) * vec2(1.7, 1.6)));
	float stain = 1.0 - smoothstep(0.25 + blotch, 0.32 + blotch, shape);
	vec2 cell = fract(UV * 25.0) - 0.5;
	float crumbs = step(0.86, hash(floor(UV * 25.0))) * (1.0 - smoothstep(0.10, 0.27, length(cell)));
	crumbs *= 1.0 - smoothstep(0.36, 0.48, length(p));
	float streak = noise(UV * vec2(5.0, 65.0));
	ALBEDO = mix(dirt_color.rgb * 0.7, dirt_color.rgb * 1.65, grain * 0.7 + streak * 0.3);
	ALBEDO = mix(ALBEDO, vec3(0.54, 0.45, 0.29), crumbs * 0.7);
	ROUGHNESS = mix(0.45, 0.95, grain);
	SPECULAR = 0.18;
	ALPHA = max(stain * (0.60 + grain * 0.35), crumbs * 0.9);
	ALPHA_SCISSOR_THRESHOLD = 0.04;
}
