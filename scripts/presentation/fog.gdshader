shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D loss_map : filter_linear, repeat_disable;
uniform vec2 view_origin = vec2(0.0);
uniform float view_range = 0.0;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }
void fragment() {
	// Continuous visual edge; observation and last-seen ground remain CPU-owned.
	vec2 uv = world_point / 512.0;
	vec2 step = vec2(0.65/512.0);
	vec2 delta = world_point - view_origin;
	float margin = view_range - length(delta);
	float visible = 0.0;
	if (view_range > 0.0 && margin > -1.25) {
		float path = max(abs(delta.x), abs(delta.y));
		float span = max(0.0, path - 1.0);
		float amount = 0.0;
		// Fixed visual quadrature; CPU observation still owns entities and memory.
		for (int i = 0; i < 24; i++) {
			float at = (0.5 + (float(i) + 0.5) * span / 24.0) / max(1.0, path);
			amount += texture(loss_map, (view_origin + delta * at) / 512.0).r;
		}
		visible = smoothstep(0.12,0.88,clamp((margin - amount * span / 24.0 + 1.25) / 2.5, 0.0, 1.0));
	}
	float known = texture(explored_map,uv).r*0.4;
	known += (texture(explored_map,uv+vec2(step.x,0)).r+texture(explored_map,uv-vec2(step.x,0)).r+texture(explored_map,uv+vec2(0,step.y)).r+texture(explored_map,uv-vec2(0,step.y)).r)*0.15;
	known = smoothstep(0.12,0.88,known);
	COLOR = vec4(0.015, 0.022, 0.03, mix(1.0, 0.55, known) * (1.0 - visible));
}
