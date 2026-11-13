shader_type canvas_item;
uniform sampler2D ground_map : filter_nearest, repeat_disable;
uniform sampler2D tile_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D static_map : filter_nearest, repeat_disable;
uniform sampler2D visible_map : filter_nearest, repeat_disable;
uniform sampler2D explored_map : filter_nearest, repeat_disable;
uniform bool use_fog = true;
uniform vec2 origin = vec2(144.0);
uniform float span = 80.0;
void fragment() {
	vec2 point = origin + UV * span;
	vec2 map_uv = clamp(point / 512.0, vec2(0.000001), vec2(0.999999));
	int flags = int(round(texture(ground_map, map_uv).r * 255.0));
	int surface = flags & 7;
	float kind = surface == 2 ? 4.0 : (surface == 3 ? 2.0 : (surface == 4 ? 3.0 : 1.0));
	if ((flags & 16) != 0) { kind = 0.0; }
	if ((flags & 8) != 0) { kind = 5.0; }
	vec2 local = fract(point);
	float variant = mod(floor(point.x) * 17.0 + floor(point.y) * 29.0, 4.0);
	vec3 color = texture(tile_atlas, (vec2(kind, variant) + clamp(local, vec2(0.04), vec2(0.96))) / vec2(8.0, 4.0)).rgb;
	int object = int(round(texture(static_map, map_uv).r * 255.0));
	if (object == 1) { color = mix(vec3(0.48,0.43,0.32), vec3(0.63,0.59,0.46), step(0.12,local.x)*step(0.12,local.y)); }
	if (object == 2) { color = vec3(0.48,0.34,0.20); }
	if (object == 3 && length(local-vec2(0.5)) < 0.48) { color = mix(vec3(0.12,0.23,0.11),vec3(0.25,0.38,0.15),step(0.18,local.x+local.y)); }
	if (object == 4 && max(abs(local.x-0.5),abs(local.y-0.5)) < 0.38) { color = vec3(0.59,0.43,0.24); }
	if (object == 5) { color = mix(color,vec3(0.32,0.77,0.78),0.55); }
	if (object == 6 && length(local-vec2(0.5)) < 0.36) { color = vec3(0.37,0.47,0.16); }
	if (use_fog) {
		float seen = texture(explored_map,map_uv).r;
		float current = texture(visible_map,map_uv).r;
		color *= current > 0.5 ? 1.0 : 0.46;
		if (seen < 0.001 && current < 0.001) { color = vec3(0.012,0.019,0.024); }
	}
	if (point.x < 0.0 || point.y < 0.0 || point.x >= 512.0 || point.y >= 512.0) { color = vec3(0.012,0.019,0.024); }
	COLOR = vec4(color,1.0);
}
