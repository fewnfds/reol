shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_map : filter_linear, repeat_disable;
uniform sampler2D loss_map : filter_linear, repeat_disable;
uniform vec2 view_origin = vec2(0.0);
uniform float view_range = 0.0;
const float EDGE_INSET = 1.0;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }

float ground_clearance(vec2 point) {
	// Explored texels are nonzero exactly where last-seen ground was cached.
	// Distance to the nearest unknown square rounds corners and reaches full
	// opacity before any missing ground can show through the continuous edge.
	ivec2 cell = ivec2(floor(point));
	float clearance = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 next = cell + ivec2(x, y);
			bool inside = all(greaterThanEqual(next, ivec2(0))) && all(lessThan(next, ivec2(512)));
			if (!inside || texelFetch(explored_map, clamp(next, ivec2(0), ivec2(511)), 0).r == 0.0) {
				vec2 gap = max(abs(point - (vec2(next) + vec2(0.5))) - vec2(0.5), vec2(0.0));
				clearance = min(clearance, length(gap));
			}
		}
	}
	return smoothstep(0.0, 1.0, clearance);
}

void fragment() {
	// Continuous visual edge; observation and last-seen ground remain CPU-owned.
	vec2 uv = world_point / 512.0;
	vec2 step = vec2(0.65/512.0);
	vec2 delta = world_point - view_origin;
	float margin = max(0.0, view_range - EDGE_INSET) - length(delta);
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
	if (known > 0.0 || visible > 0.0) {
		float support = ground_clearance(world_point);
		visible *= support;
		known *= support;
	}
	COLOR = vec4(0.015, 0.022, 0.03, mix(1.0, 0.55, known) * (1.0 - visible));
}
