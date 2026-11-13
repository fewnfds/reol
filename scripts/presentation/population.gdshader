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
varying vec2 sprite_pixel;
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
        // Derive pixels from the local quad, not its backend-oriented UVs.
        // All art pixels and world coordinates now use +Y downward.
        sprite_pixel = VERTEX * 64.0 + vec2(32.0);
        VERTEX = sprite_pixel - anchor;
        known = (!use_fog || texture(visible_map, INSTANCE_CUSTOM.xy / (512.0 * 32.0)).r > 0.5) ? 1.0 : 0.0;
        float sway = float((flags >> 8) & 1) * known;
        // Linear shear about y=0 keeps the root fixed even on a four-vertex quad.
        VERTEX.x += sin(art_time * 1.2 + MODEL_MATRIX[3].x * 0.03) * -VERTEX.y * 0.012 * sway;
        special = float((flags >> 9) & 3);
    } else {
        state = (flags >> 3) & 15;
        anchor = vec2(24.0,42.0);
        sprite_pixel = VERTEX * 48.0 + vec2(24.0);
        VERTEX = sprite_pixel - anchor;
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
    vec2 pixel = sprite_pixel;
    float lift = scenery < 0.5 && (body_flags & 4) != 0 && state != 14 ? 6.0 : 0.0;
    vec4 body = sample_sprite(TEXTURE, pixel + vec2(0.0,lift));
    if (scenery > 0.5 || (body.g > body.r * 1.12 && body.g > body.b * 1.02)) { body.rgb *= tint.rgb; }
    if (scenery < 0.5 && state == 14) { body.rgb = mix(body.rgb, vec3(dot(body.rgb, vec3(0.3,0.55,0.15))), 0.5) * 0.68; }
    // Bounded ground contact, not a compressed second copy of the sprite.
    // It intersects the foot/root pixel and cannot detach from tall foliage.
    vec2 ground = pixel - anchor;
    vec2 spread = scenery > 0.5 ? vec2(10.0, 3.2) : vec2(7.0, 2.5);
    float contact = 1.0 - smoothstep(0.65, 1.0, length(ground / spread));
    vec2 drift = art_sun * 7.0;
    float solar = 1.0 - smoothstep(0.45, 1.0, length((ground - drift) / (spread + vec2(2.0, 0.5))));
    float shadow = max(contact * 0.22, solar * art_sun_strength * 0.16);
    if (scenery > 0.5 && tint.a < 0.9) { shadow = 0.0; }
    float a = body.a + shadow * (1.0-body.a);
    vec3 color = (body.rgb*body.a + vec3(0.10,0.16,0.20)*shadow*(1.0-body.a))/max(a,0.001);
    if (special > 0.5) { color += body.rgb*(0.08+0.06*sin(art_time*3.0)*known); }
    // One known object stays whole over ground fog, including its canopy.
    // Only detached last-observed descriptors reach this batch.
    if (scenery > 0.5) { color = mix(mix(vec3(0.015,0.022,0.03),color,0.45),color,known); }
    COLOR = vec4(color,a*tint.a);
}
