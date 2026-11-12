shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D loss_map : filter_nearest, repeat_disable;
uniform vec2 observer;
uniform float view_range = 24.0;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }
void fragment() {
	vec2 delta = world_point - observer;
	float distance_cells = length(delta);
	float cost = distance_cells;
	if (distance_cells <= view_range + 1.0) {
		float steps = max(abs(delta.x), abs(delta.y));
		vec2 previous = floor(observer);
		for (int i = 1; i < 26; i++) {
			if (float(i) >= steps) { break; }
			vec2 p = observer + delta * (float(i) / max(steps, 1.0));
			vec2 tile = floor(p);
			if (tile != previous) { cost += texture(loss_map, (tile + vec2(0.5)) / 512.0).r * 255.0; }
			previous = tile;
		}
	}
	float visible = 1.0 - smoothstep(view_range - 1.5, view_range + 0.5, cost);
	float known = texture(explored_map, world_point / 512.0).r;
	COLOR = vec4(0.015, 0.022, 0.03, mix(mix(0.97, 0.55, known), 0.0, visible));
}
