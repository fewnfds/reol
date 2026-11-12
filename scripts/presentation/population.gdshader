shader_type canvas_item;
global uniform vec2 art_sun;
global uniform float art_sun_strength;
uniform float alpha = 1.0;
uniform float world_ms = 0.0;
varying flat vec2 atlas_offset;
varying flat int state;
varying flat int body_flags;
varying vec4 tint;
void vertex() {
    vec2 current = MODEL_MATRIX[3].xy;
    int flags = int(INSTANCE_CUSTOM.w);
    body_flags = flags;
    state = (flags >> 3) & 15;
    if ((flags & 2) != 0) { VERTEX *= 1.6; }
    VERTEX += (INSTANCE_CUSTOM.xy - current) * (1.0 - alpha);
    int frame = int(mod(world_ms + float(INSTANCE_ID % 11) * 83.0, state == 0 ? 1600.0 : 900.0) / (state == 0 ? 400.0 : 225.0));
    if (state == 14 || (state == 2 && (flags & 1) == 0)) { frame = 0; }
    atlas_offset = vec2(INSTANCE_CUSTOM.z * 4.0 + float(frame), float(state)) / vec2(32.0, 16.0);
    tint = COLOR;
}
vec4 sample_frame(sampler2D tex, vec2 pixel) {
    vec2 limited = clamp(pixel, vec2(0.5), vec2(47.5)) / 48.0;
    vec4 value = texture(tex, atlas_offset + limited / vec2(32.0, 16.0));
    value.a *= float(all(greaterThanEqual(pixel, vec2(0.0))) && all(lessThan(pixel, vec2(48.0))));
    return value;
}
void fragment() {
    vec2 pixel = vec2(UV.x, 1.0 - UV.y) * 48.0;
    float lift = (body_flags & 4) != 0 && state != 14 ? 6.0 : 0.0;
    vec4 body = sample_frame(TEXTURE, pixel + vec2(0.0, lift));
    if (body.g > body.r * 1.12 && body.g > body.b * 1.02) { body.rgb *= tint.rgb; }
    if (state == 14) {
        float gray = dot(body.rgb, vec3(0.3, 0.55, 0.15));
        body.rgb = mix(body.rgb, vec3(gray), 0.5) * 0.68;
    }
    float height = (pixel.y - 42.0) / max(0.1, art_sun.y);
    vec2 shadow_source = vec2(24.0 + (pixel.x - 24.0 - art_sun.x * height) / 0.82, 42.0 - height);
    float shadow = sample_frame(TEXTURE, shadow_source).a * float(height >= 0.0) * art_sun_strength * 0.30;
    shadow *= smoothstep(0.0, 2.0, min(pixel.x, 48.0 - pixel.x)) * smoothstep(0.0, 2.0, 48.0 - pixel.y);
    vec4 below = vec4(0.10, 0.16, 0.20, shadow);
    float out_alpha = body.a + below.a * (1.0 - body.a);
    vec3 color = (body.rgb * body.a + below.rgb * below.a * (1.0 - body.a)) / max(out_alpha, 0.001);
    COLOR = vec4(color, out_alpha * tint.a);
}
