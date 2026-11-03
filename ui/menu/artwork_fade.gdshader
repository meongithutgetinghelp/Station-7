shader_type canvas_item;
render_mode unshaded;

// Blend the left edge of the right-hand illustration into the dark menu.
uniform float fade_end : hint_range(0.01, 1.0) = 0.34;

void fragment() {
	vec4 artwork = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(artwork.rgb, artwork.a * smoothstep(0.0, fade_end, UV.x));
}
