shader_type canvas_item;

uniform sampler2D body : source_color, filter_nearest, repeat_disable;
uniform sampler2D robe : source_color, filter_nearest, repeat_disable;
uniform sampler2D detail : source_color, filter_nearest, repeat_disable;
uniform float alpha = 1.0;
uniform ivec2 cursors;
varying flat vec2 atlas_offset;
varying vec4 tint;

vec4 over(vec4 below, vec4 above) {
	return vec4(above.rgb * above.a + below.rgb * (1.0 - above.a), above.a + below.a * (1.0 - above.a));
}

void vertex() {
	// Coordinates are two committed positions, never a speculative next step.
	vec2 current = MODEL_MATRIX[3].xy;
	int flags = int(INSTANCE_CUSTOM.w);
	if ((flags & 2) != 0) { VERTEX *= 1.6; }
	if ((flags & 4) != 0) { VERTEX.y -= 18.0; }
	VERTEX += (INSTANCE_CUSTOM.xy - current) * (1.0 - alpha);
	int frame = cursors.x * 8 / 1600;
	if ((flags & 1) != 0) {
		frame = 8 + cursors.y * 16 / 900;
	}
	atlas_offset = vec2(float(frame), INSTANCE_CUSTOM.z) / vec2(40.0, 8.0);
	tint = COLOR;
}

void fragment() {
	vec2 uv = UV / vec2(40.0, 8.0) + atlas_offset;
	vec4 result = texture(body, uv);
	result = over(result, texture(robe, uv) * tint);
	result = over(result, texture(detail, uv));
	COLOR = vec4(result.rgb / max(result.a, 0.00001), result.a * tint.a);
}
