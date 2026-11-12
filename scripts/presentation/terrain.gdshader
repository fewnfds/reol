shader_type canvas_item;
global uniform float art_time;
uniform sampler2D ground_map : filter_nearest, repeat_disable;
uniform sampler2D tile_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D visible_map : filter_nearest, repeat_disable;
uniform bool use_fog = true;
uniform bool debug_markers = false;
varying vec2 world_point;
void vertex() { world_point = VERTEX / 32.0; }
int appearance(vec2 point) { return int(round(texture(ground_map, clamp(point / 512.0, vec2(0.00001), vec2(0.99999))).r * 255.0)); }
void fragment() {
    int flags = appearance(world_point);
    int surface = flags & 7;
    vec2 local = fract(world_point);
    vec2 cell = floor(world_point);
    float variant = mod(cell.x * 17.0 + cell.y * 29.0, 4.0);
    float kind = surface == 2 ? 1.0 : (surface == 3 ? 2.0 : (surface == 4 ? 3.0 : 0.0));
    if (surface == 2 && cell.x >= 300.0) { kind = 4.0; }
    if ((flags & 8) != 0) { kind = 5.0; }
    vec3 color = texture(tile_atlas, (vec2(kind, variant) + clamp(local, vec2(0.03125), vec2(0.96875))) / vec2(8.0, 4.0)).rgb;
    bool current = !use_fog || texture(visible_map, world_point / 512.0).r > 0.5;
    if (surface == 3) {
        float foam = 0.0;
        if ((appearance(cell + vec2(-0.5,0.5)) & 7) != 3 && local.x < 0.12) { foam = 1.0; }
        if ((appearance(cell + vec2(1.5,0.5)) & 7) != 3 && local.x > 0.88) { foam = 1.0; }
        if ((appearance(cell + vec2(0.5,-0.5)) & 7) != 3 && local.y < 0.12) { foam = 1.0; }
        if ((appearance(cell + vec2(0.5,1.5)) & 7) != 3 && local.y > 0.88) { foam = 1.0; }
        color = mix(color, vec3(0.64,0.79,0.73), foam * 0.72);
        if (current) { color += vec3(0.025) * sin(world_point.x * 4.0 + world_point.y * 2.0 + art_time * 1.4); }
    }
    if (debug_markers && ((flags >> 4) & 7) > 0 && distance(local, vec2(0.5)) < 0.13) { color = vec3(0.85,0.55,0.3); }
    COLOR = vec4(surface == 0 ? vec3(0.015, 0.022, 0.03) : color, 1.0);
}
