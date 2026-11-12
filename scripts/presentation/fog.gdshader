shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D visible_map : filter_linear, repeat_disable;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }
void fragment() {
	// Both visibility and exploration come from the same tile calculation.
	// Filtering only softens tile edges; it performs no extra line-of-sight test.
	vec2 uv = world_point / 512.0;
	vec2 step = vec2(0.65/512.0);
	float visible = texture(visible_map, uv).r*0.4;
	visible += (texture(visible_map,uv+vec2(step.x,0)).r+texture(visible_map,uv-vec2(step.x,0)).r+texture(visible_map,uv+vec2(0,step.y)).r+texture(visible_map,uv-vec2(0,step.y)).r)*0.15;
	visible = smoothstep(0.12,0.88,visible);
	float known = texture(explored_map,uv).r*0.4;
	known += (texture(explored_map,uv+vec2(step.x,0)).r+texture(explored_map,uv-vec2(step.x,0)).r+texture(explored_map,uv+vec2(0,step.y)).r+texture(explored_map,uv-vec2(0,step.y)).r)*0.15;
	known = smoothstep(0.12,0.88,known);
	COLOR = vec4(0.015, 0.022, 0.03, mix(1.0, 0.55, known) * (1.0 - visible));
}
