shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ground_map : filter_nearest, repeat_disable;
varying vec2 world_point;

void vertex() { world_point = VERTEX / 32.0; }

void fragment() {
	// Last observed appearance: low 3 bits = surface, bit 3 = floor,
	// bits 4..6 = development source marker. No live terrain is sampled.
	int appearance = int(round(texture(ground_map, world_point / 512.0).r * 255.0));
	int surface = appearance & 7;
	vec3 color = vec3(0.11, 0.17, 0.13);
	if (surface == 2) { color = vec3(0.42, 0.36, 0.22); }
	if (surface == 3) { color = vec3(0.13, 0.32, 0.47); }
	if (surface == 4) { color = vec3(0.27, 0.34, 0.37); }
	vec2 local = fract(world_point) * 32.0;
	if (all(greaterThanEqual(world_point, vec2(160.0))) && all(lessThan(world_point, vec2(280.0))) && min(local.x, local.y) < 0.6) {
		color = vec3(0.16, 0.22, 0.17);
	}
	if ((appearance & 8) != 0 && all(greaterThanEqual(local, vec2(1.0))) && all(lessThan(local, vec2(31.0)))) {
		color = vec3(0.29, 0.25, 0.21);
	}
	int marker = (appearance >> 4) & 7;
	if (marker > 0 && distance(local, vec2(16.0)) < 5.0) {
		if (marker == 1) { color = vec3(1.0, 0.27, 0.0); }
		if (marker == 2) { color = vec3(0.53, 0.81, 0.92); }
		if (marker == 3) { color = vec3(0.75); }
		if (marker == 4) { color = vec3(0.2, 0.8, 0.2); }
		if (marker == 5) { color = vec3(0.12, 0.56, 1.0); }
		if (marker == 6) { color = vec3(1.0, 0.0, 0.0); }
		if (marker == 7) { color = vec3(0.96, 0.64, 0.38); }
	}
	COLOR = vec4(surface == 0 ? vec3(0.015, 0.022, 0.03) : color, 1.0);
}
