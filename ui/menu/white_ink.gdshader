shader_type canvas_item;
render_mode unshaded;

varying vec4 ink_tint;
void vertex() {
	ink_tint = COLOR;
}

// Keep every original pen stroke; turn black ink white and remove white paper.
void fragment() {
	vec4 drawing = texture(TEXTURE, UV);
	float ink = 1.0 - dot(drawing.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(ink_tint.rgb, ink_tint.a * drawing.a * ink);
}
