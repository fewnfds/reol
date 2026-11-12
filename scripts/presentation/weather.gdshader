shader_type canvas_item;
render_mode unshaded;
uniform int weather_mode = 0;
uniform float world_time = 0.0;
uniform float day_light = 1.0;
uniform sampler2D visible_map : filter_nearest, repeat_disable;
uniform sampler2D shelter_map : filter_nearest, repeat_disable;
uniform bool use_fog = true;
uniform vec2 world_origin;
uniform vec2 world_u;
uniform vec2 world_v;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 world = world_origin + world_u * UV.x + world_v * UV.y;
	// World-anchored patterns follow the camera; the full-screen pass only
	// supplies coverage. Zoom changes their apparent size with the map.
	vec2 uv = world * 12.0;
	float effect = 0.0;
	vec3 color = vec3(0.65, 0.83, 0.91);
	if (weather_mode == 1) {
		vec2 p = uv * vec2(105.0, 50.0) + vec2(world_time * 3.0, world_time * 20.0);
		vec2 cell = floor(p);
		vec2 local = fract(p);
		float random = hash(cell);
		effect = step(0.65, random) * step(abs(local.x - local.y * 0.18 - 0.4), 0.04) * step(0.2, local.y) * 0.38;
	} else if (weather_mode == 2) {
		vec2 p = uv * vec2(55.0, 32.0) + vec2(world_time * 4.0, world_time * 0.6);
		float random = hash(floor(p));
		vec2 local = fract(p);
		effect = step(0.76, random) * step(length(local - vec2(0.5)), 0.07) * 0.55;
		color = vec3(0.86,0.93,0.94);
	} else if (weather_mode == 3) {
		// Warm drifting haze, no screen-texture readback or refraction cost.
		effect = pow(max(0.0, sin(uv.y * 65.0 + sin(uv.x * 7.0 + world_time) * 2.0 - world_time * 2.0)), 16.0) * 0.045;
		color = vec3(1.0,0.75,0.40);
	}
	bool inside = all(greaterThanEqual(world, vec2(0.0))) && all(lessThan(world, vec2(1.0)));
	float known = (!use_fog || texture(visible_map, world).r > 0.5) && inside ? 1.0 : 0.0;
	float exposed = 1.0 - texture(shelter_map, world).r;
	COLOR = vec4(color * day_light, effect * known * exposed * day_light);
}
