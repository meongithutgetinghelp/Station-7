shader_type canvas_item;
render_mode unshaded;

// Still, perspective platform silhouettes with a slow drifting veil of mist.
uniform bool motion_enabled = true;
float line(float p, float width) { return 1.0 - smoothstep(0.0, width, abs(p)); }

void fragment() {
	vec2 p = UV;
	vec2 vanishing = vec2(0.71, 0.44);
	vec3 color = mix(vec3(0.018, 0.027, 0.032), vec3(0.062, 0.089, 0.093), p.y);
	float glow = exp(-length((p - vanishing) * vec2(2.0, 3.0)) * 4.0);
	color += vec3(0.17, 0.21, 0.19) * glow;
	float depth = max(p.y - vanishing.y, 0.0);
	float rails = line(p.x - vanishing.x + depth * 0.28, 0.002)
		+ line(p.x - vanishing.x - depth * 0.63, 0.003);
	color += vec3(0.17, 0.20, 0.18) * rails * smoothstep(0.0, 0.2, depth);
	float platform = smoothstep(0.003, 0.0, p.x - vanishing.x + depth * 1.4) * step(0.44, p.y);
	color = mix(color, vec3(0.026, 0.037, 0.038), platform * 0.85);
	color += vec3(0.25, 0.20, 0.11) * line(p.x - vanishing.x + depth * 1.4, 0.004) * step(0.44, p.y);
	// Receding columns and ceiling lamps.
	for (int i = 0; i < 5; i++) {
		float d = pow(0.57, float(i));
		float x = vanishing.x + 0.44 * d;
		float column = step(x, p.x) * step(p.x, x + 0.024 * d)
			* step(0.44 - 0.44 * d, p.y) * step(p.y, 0.44 + 0.5 * d);
		color = mix(color, vec3(0.012, 0.020, 0.023), column);
		float lamp = line(p.y - (0.44 - 0.33 * d), 0.0025)
			* step(vanishing.x - 0.04 * d, p.x) * step(p.x, vanishing.x + 0.15 * d);
		color += vec3(0.47, 0.51, 0.40) * lamp * d;
	}
	float time = motion_enabled ? TIME * 0.025 : 0.0;
	float mist = sin(p.x * 9.0 + p.y * 5.0 + time) * sin(p.y * 13.0 - time);
	color += vec3(0.025, 0.032, 0.030) * mist * glow;
	float grain = fract(sin(dot(floor(p * vec2(1920.0, 1080.0)), vec2(12.9898, 78.233))) * 43758.5453);
	color += (grain - 0.5) * 0.018;
	color *= smoothstep(0.0, 0.62, p.x) * (1.0 - 0.45 * length(p - vec2(0.55)));
	COLOR = vec4(color, 1.0);
}
