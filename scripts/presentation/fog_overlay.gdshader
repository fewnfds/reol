shader_type canvas_item;
render_mode unshaded;
uniform sampler2D fog_mask : filter_linear, repeat_disable;
void fragment() {
	COLOR = vec4(0.015, 0.022, 0.03, texture(fog_mask, SCREEN_UV).r);
}
