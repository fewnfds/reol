#[compute]
#version 450

// Isolated source-field projection. The host must validate and freeze the
// input snapshot, bound dispatch work, and reject results from stale revisions.
// All buffers are scalar std430 arrays in set 0:
//   0: uint params[8] = width, height, slot_capacity, max_radius,
//                        rect_x, rect_y, rect_width, rect_height.
//   1: int heads[width * height], -1 for an empty cell.
//   2: int slots[slot_capacity * 11]: four capacity-sized x, y, radius and
//      next arrays, then seven interleaved strengths per slot (metal, wood,
//      water, fire, earth, hot, cold). next=-1 ends.
//   3: uint kernel weights, concatenated radius-by-radius quadrant tables.
//   4: uint kernel offsets[257], index by radius; UINT_MAX means absent.
//   5: uint output[rect_width * rect_height * 7], tightly packed by cell.
// Inputs obey CPU limits: dimensions 1..4096, slots 0..4194304, radius 1..256,
// strength 0..1e9, weight 0..1e6, and heads form finite, position-matching
// chains of active slots. Each active radius has its exact F0 kernel table:
// weights[offset[r] + abs(dy) * r + abs(dx)], dx,dy < r. Valid output ranges
// 0..1e9. UINT_MAX in all seven channels flags an invalid encountered chain or
// kernel and must not be committed. This shader is not a full input validator.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer ParamsBuffer {
    uint values[];
} params;

layout(set = 0, binding = 1, std430) restrict readonly buffer HeadBuffer {
    int values[];
} heads;

layout(set = 0, binding = 2, std430) restrict readonly buffer SlotBuffer {
    int values[];
} slots;

layout(set = 0, binding = 3, std430) restrict readonly buffer KernelBuffer {
    uint values[];
} kernels;

layout(set = 0, binding = 4, std430) restrict readonly buffer OffsetBuffer {
    uint values[];
} offsets;

layout(set = 0, binding = 5, std430) restrict writeonly buffer OutputBuffer {
    uint values[];
} output_field;

const uint CHANNELS = 7u;
const uint SCALE = 1000000u;
const uint INVALID = 0xffffffffu;


// Exact (strength * weight + 500000) / 1000000 using only uint32.
// For s = high*1e6 + mid*1000 + low, mid,low < 1000:
// A = mid*weight, B = low*weight, so the result is
// high*weight + A/1000 + ((A%1000)*1000 + B + 500000)/1e6.
// strength<=1e9 and weight<=1e6 imply A,B<=999000000, the last
// numerator<=1000499000, and the result<=1e9. No intermediate wraps.
uint scaled_strength(uint strength, uint weight) {
    uint high = strength / SCALE;
    uint tail = strength % SCALE;
    uint mid = tail / 1000u;
    uint low = tail % 1000u;
    uint a = mid * weight;
    uint b = low * weight;
    return high * weight + a / 1000u +
            ((a % 1000u) * 1000u + b + 500000u) / SCALE;
}


// Each traversed source belongs to this source cell. At the receiver's own
// location its peak is known exactly, providing a useful lower bound before
// searching neighbors. Returns false for an encountered invalid projection.
bool visit_cell(int source_x, int source_y, int dx, int dy,
        uint width, uint capacity, uint maximum_radius, inout uint best[7]) {
    int slot = heads.values[uint(source_y) * width + uint(source_x)];
    uint count = 0u;
    while (slot != -1) {
        if (slot < 0 || uint(slot) >= capacity || count >= capacity) {
            return false;
        }
        ++count;
        uint index_slot = uint(slot);
        if (slots.values[index_slot] != source_x || slots.values[capacity + index_slot] != source_y) {
            return false;
        }
        int radius = slots.values[2u * capacity + index_slot];
        int next = slots.values[3u * capacity + index_slot];
        if (radius < 1 || radius > 256 || uint(radius) > maximum_radius) {
            return false;
        }
        if (dx < radius && dy < radius) {
            uint weight = SCALE;
            if (dx != 0 || dy != 0) {
                uint offset = offsets.values[uint(radius)];
                uint index = uint(dy) * uint(radius) + uint(dx);
                if (offset == INVALID || offset >= uint(kernels.values.length()) ||
                        index >= uint(kernels.values.length()) - offset) {
                    return false;
                }
                weight = kernels.values[offset + index];
                if (weight > SCALE) {
                    return false;
                }
            }
            if (weight != 0u) {
                for (uint channel = 0u; channel < CHANNELS; ++channel) {
                    int raw_strength = slots.values[4u * capacity + index_slot * CHANNELS + channel];
                    if (raw_strength < 0 || raw_strength > 1000000000) {
                        return false;
                    }
                    uint strength = uint(raw_strength);
                    // The kernel never increases strength; a value no greater
                    // than the current max cannot win after rounding.
                    if (strength > best[channel]) {
                        uint candidate = weight == SCALE ? strength : scaled_strength(strength, weight);
                        best[channel] = max(best[channel], candidate);
                    }
                }
            }
        }
        slot = next;
    }
    return true;
}


void main() {
    uvec2 local = gl_GlobalInvocationID.xy;
    uint rect_width = params.values[6];
    uint rect_height = params.values[7];
    if (local.x >= rect_width || local.y >= rect_height) {
        return;
    }

    uint width = params.values[0];
    uint height = params.values[1];
    uint capacity = params.values[2];
    uint maximum_radius = params.values[3];
    int x = int(params.values[4] + local.x);
    int y = int(params.values[5] + local.y);
    uint best[7] = uint[7](0u, 0u, 0u, 0u, 0u, 0u, 0u);
    bool valid = true;

    if (maximum_radius > 256u || width == 0u || height == 0u ||
            x < 0 || y < 0 || uint(x) >= width || uint(y) >= height) {
        valid = false;
    } else {
        valid = visit_cell(x, y, 0, 0, width, capacity, maximum_radius, best);
        int reach = int(maximum_radius) - 1;
        if (valid && reach > 0) {
            int min_x = max(0, x - reach);
            int max_x = min(int(width) - 1, x + reach);
            int min_y = max(0, y - reach);
            int max_y = min(int(height) - 1, y + reach);
            for (int sy = min_y; sy <= max_y && valid; ++sy) {
                for (int sx = min_x; sx <= max_x && valid; ++sx) {
                    if (sx == x && sy == y) {
                        continue;
                    }
                    valid = visit_cell(sx, sy, abs(sx - x), abs(sy - y),
                            width, capacity, maximum_radius, best);
                }
            }
        }
    }

    uint output_offset = (local.y * rect_width + local.x) * CHANNELS;
    for (uint channel = 0u; channel < CHANNELS; ++channel) {
        output_field.values[output_offset + channel] = valid ? best[channel] : INVALID;
    }
}
