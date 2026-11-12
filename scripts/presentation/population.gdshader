shader_type canvas_item;
global uniform vec2 art_sun;
global uniform float art_sun_strength;
global uniform float art_time;
uniform sampler2D world_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D visible_map : filter_nearest, repeat_disable;
uniform bool use_fog = false;
uniform float alpha = 1.0;
uniform float world_ms = 0.0;
varying flat vec2 atlas_offset;
varying flat vec2 anchor;
varying flat int state;
varying flat int body_flags;
varying flat float scenery;
varying flat float known;
varying flat float special;
varying vec4 tint;
void vertex() {
    int flags = int(INSTANCE_CUSTOM.w);
    body_flags = flags;
    scenery = (flags & 128) != 0 ? 1.0 : 0.0;
    known = 1.0;
    special = 0.0;
    tint = COLOR;
    if (scenery > 0.5) {
        anchor = vec2(float((flags >> 11) & 63), float((flags >> 17) & 63));
        int slot = int(INSTANCE_CUSTOM.z);
        atlas_offset = vec2(float(slot % 8), float(slot / 8)) * 64.0;
        state = 0;
        VERTEX = VERTEX * 64.0 + vec2(32.0) - anchor;
        known = (!use_fog || texture(visible_map, INSTANCE_CUSTOM.xy / (512.0 * 32.0)).r > 0.5) ? 1.0 : 0.0;
        float sway = float((flags >> 8) & 1) * known;
        VERTEX.x += sin(art_time * 1.2 + MODEL_MATRIX[3].x * 0.03) * max(0.0, -VERTEX.y) * 0.012 * sway;
        special = float((flags >> 9) & 3);
    } else {
        state = (flags >> 3) & 15;
        anchor = vec2(24.0,42.0);
        VERTEX = VERTEX * 48.0 + vec2(24.0) - anchor;
        if ((flags & 2) != 0) { VERTEX *= 1.6; }
        VERTEX += (INSTANCE_CUSTOM.xy - MODEL_MATRIX[3].xy) * (1.0 - alpha);
        int frame = int(mod(world_ms + float((flags >> 8) & 15) * 83.0, state == 0 ? 1600.0 : 900.0) / (state == 0 ? 400.0 : 225.0));
        if (state == 14 || (state == 2 && (flags & 1) == 0)) { frame = 0; }
        atlas_offset = vec2(INSTANCE_CUSTOM.z * 4.0 + float(frame), float(state)) * 48.0;
    }
}
vec4 sample_sprite(sampler2D actors, vec2 pixel) {
    float cell = scenery > 0.5 ? 64.0 : 48.0;
    vec2 p = clamp(pixel, vec2(0.5), vec2(cell - 0.5));
    vec4 value;
    if (scenery > 0.5) { value = texture(world_atlas, (atlas_offset + p) / vec2(textureSize(world_atlas, 0))); }
    else { value = texture(actors, (atlas_offset + p) / vec2(textureSize(actors, 0))); }
    value.a *= float(all(greaterThanEqual(pixel, vec2(0.0))) && all(lessThan(pixel, vec2(cell))));
    return value;
}
void fragment() {
    float cell = scenery > 0.5 ? 64.0 : 48.0;
    vec2 pixel = vec2(UV.x, 1.0 - UV.y) * cell;
    float lift = scenery < 0.5 && (body_flags & 4) != 0 && state != 14 ? 6.0 : 0.0;
    vec4 body = sample_sprite(TEXTURE, pixel + vec2(0.0,lift));
    if (scenery > 0.5 || (body.g > body.r * 1.12 && body.g > body.b * 1.02)) { body.rgb *= tint.rgb; }
    if (scenery < 0.5 && state == 14) { body.rgb = mix(body.rgb, vec3(dot(body.rgb, vec3(0.3,0.55,0.15))), 0.5) * 0.68; }
    float height = (pixel.y - anchor.y) / max(0.1, art_sun.y);
    vec2 shadow_source = vec2(anchor.x + (pixel.x - anchor.x - art_sun.x * height) / 0.82, anchor.y - height);
    float shadow = sample_sprite(TEXTURE, shadow_source).a * float(height >= 0.0) * art_sun_strength * 0.28;
    shadow *= smoothstep(0.0,2.0,min(pixel.x,cell-pixel.x)) * smoothstep(0.0,2.0,cell-pixel.y);
    float a = body.a + shadow * (1.0-body.a);
    vec3 color = (body.rgb*body.a + vec3(0.10,0.16,0.20)*shadow*(1.0-body.a))/max(a,0.001);
    if (special > 0.5) { color += body.rgb*(0.08+0.06*sin(art_time*3.0)*known); }
    // One known object stays whole over ground fog, including its canopy.
    // Only detached last-observed descriptors reach this batch.
    if (scenery > 0.5) { color = mix(mix(vec3(0.015,0.022,0.03),color,0.45),color,known); }
    COLOR = vec4(color,a*tint.a);
}
