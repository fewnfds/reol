shader_type canvas_item;

uniform sampler2D sword_far : source_color, filter_nearest, repeat_disable;
uniform sampler2D jade_far : source_color, filter_nearest, repeat_disable;
uniform sampler2D cape_far : source_color, filter_nearest, repeat_disable;
uniform sampler2D body : source_color, filter_nearest, repeat_disable;
uniform sampler2D robe : source_color, filter_nearest, repeat_disable;
uniform sampler2D detail : source_color, filter_nearest, repeat_disable;
uniform sampler2D cape_near : source_color, filter_nearest, repeat_disable;
uniform sampler2D jade_near : source_color, filter_nearest, repeat_disable;
uniform sampler2D sword_near : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_grid;
uniform ivec3 idle_clip;
uniform ivec3 walk_clip;
uniform ivec3 gesture_clip;
uniform ivec3 clip_cursors;
instance uniform ivec4 pose = ivec4(4, 0, 0, 0); // direction, clip, gesture origin, accessories
instance uniform vec4 robe_tint = vec4(1.0);
instance uniform vec4 cape_tint = vec4(1.0, 1.0, 1.0, 0.0);
varying vec4 modulation;
varying flat vec2 atlas_offset;

vec4 over(vec4 below, vec4 above) {
	return vec4(above.rgb * above.a + below.rgb * (1.0 - above.a), above.a + below.a * (1.0 - above.a));
}

void vertex() {
	modulation = COLOR;
	ivec3 clip = idle_clip;
	int cursor = clip_cursors.x;
	if (pose.y == 1) {
		clip = walk_clip;
		cursor = clip_cursors.y;
	} else if (pose.y == 2) {
		clip = gesture_clip;
		cursor = clip_cursors.z - pose.z;
		if (cursor < 0) {
			cursor += clip.z;
		}
	}
	// Exact integer arithmetic, once per vertex. Long game times are reduced
	// by the original integer clock before upload; no shader TIME/float drift.
	int frame = cursor * clip.y / clip.z;
	atlas_offset = vec2(float(clip.x + frame), float(pose.x)) / atlas_grid;
}

void fragment() {
	vec2 uv = UV + atlas_offset;
	vec4 result = vec4(0.0);
	if (pose.w != 0) {
		result = over(result, texture(sword_far, uv));
		result = over(result, texture(jade_far, uv));
	}
	if (cape_tint.a > 0.0) {
		result = over(result, texture(cape_far, uv) * cape_tint);
	}
	result = over(result, texture(body, uv));
	result = over(result, texture(robe, uv) * robe_tint);
	result = over(result, texture(detail, uv));
	if (cape_tint.a > 0.0) {
		result = over(result, texture(cape_near, uv) * cape_tint);
	}
	if (pose.w != 0) {
		result = over(result, texture(jade_near, uv));
		result = over(result, texture(sword_near, uv));
	}
	COLOR = vec4(result.rgb / max(result.a, 0.00001), result.a) * modulation;
}
