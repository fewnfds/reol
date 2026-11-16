shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.0;
uniform vec2 output_size = vec2(1280.0, 720.0);
uniform vec2 source_size = vec2(1280.0, 720.0);
void fragment() {
    // Inverse of p/(1-k*p.y); one common denominator keeps a homography.
    vec2 p = UV * 2.0 - 1.0;
    vec2 source = p / (1.0 + strength * p.y);
    vec2 uv = (source * output_size * 0.5 + source_size * 0.5) / source_size;
    COLOR = texture(TEXTURE, uv);
}
