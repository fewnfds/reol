shader_type canvas_item;
global uniform vec2 art_sun;
global uniform float art_sun_strength;
global uniform float art_time;
uniform sampler2D visible_map : filter_nearest, repeat_disable;
uniform bool use_fog = false;
varying flat vec2 atlas_cell;
varying flat float sway;
varying flat float special;
varying flat float animate;
varying vec4 tint;
void vertex() {
    atlas_cell = INSTANCE_CUSTOM.xy;
    sway = INSTANCE_CUSTOM.z;
    special = INSTANCE_CUSTOM.w;
    animate = (!use_fog || texture(visible_map, MODEL_MATRIX[3].xy / (512.0 * 32.0)).r > 0.5) ? 1.0 : 0.0;
    tint = COLOR;
    float height = max(0.0, -VERTEX.y);
    VERTEX.x += sin(art_time * 1.2 + MODEL_MATRIX[3].x * 0.03) * height * 0.018 * sway * animate;
}
vec4 sample_cell(sampler2D tex, vec2 pixel, vec2 atlas_size) {
    vec2 p = clamp(pixel, vec2(0.5), vec2(63.5));
    vec4 col = texture(tex, (atlas_cell * 64.0 + p) / atlas_size);
    col.a *= float(all(greaterThanEqual(pixel, vec2(0.0))) && all(lessThan(pixel, vec2(64.0))));
    return col;
}
void fragment() {
    vec2 pixel = vec2(UV.x, 1.0 - UV.y) * 64.0;
    vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
    vec4 body = sample_cell(TEXTURE, pixel, size);
    float h = (pixel.y - 56.0) / max(0.10, art_sun.y);
    vec2 shadow_source = vec2(32.0 + (pixel.x - 32.0 - art_sun.x * h) / 0.85, 56.0 - h);
    float shadow = sample_cell(TEXTURE, shadow_source, size).a * float(h >= 0.0) * art_sun_strength * 0.28;
    shadow *= smoothstep(0.0, 3.0, min(pixel.x, 64.0 - pixel.x)) * smoothstep(0.0, 2.0, 64.0 - pixel.y);
    float a = body.a + shadow * (1.0 - body.a);
    vec3 col = (body.rgb * tint.rgb * body.a + vec3(0.10, 0.16, 0.18) * shadow * (1.0 - body.a)) / max(a, 0.001);
    if (special > 0.5) { col += body.rgb * (0.08 + 0.06 * sin(art_time * 3.0) * animate); }
    COLOR = vec4(col, a * tint.a);
}
