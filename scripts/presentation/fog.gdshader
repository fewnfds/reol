shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D visible_map : filter_linear, repeat_disable;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }
void fragment() {
	// Both visibility and exploration come from the same tile calculation.
	// Filtering only softens tile edges; it performs no extra line-of-sight test.
	float visible = texture(visible_map, world_point / 512.0).r;
	float known = texture(explored_map, world_point / 512.0).r;
	COLOR = vec4(0.015, 0.022, 0.03, mix(1.0, 0.55, known) * (1.0 - visible));
}
