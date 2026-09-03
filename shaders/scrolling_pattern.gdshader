shader_type canvas_item;

uniform float density = 0.15;
uniform vec2 scroll_direction = vec2(0.05, 0.05);
uniform vec4 background_color = vec4(0.15, 0.15, 0.30, 0.18);
uniform vec4 shape_color = vec4(0.75, 0.75, 0.95, 0.45);
uniform float shape_size = 0.14;
uniform int shape_type = 0;  // 0=Circle, 1=Square, 2=Triangle, 3=Star, 4=Diamond
uniform bool use_pattern = false;
uniform float pattern_seed = 0.0;

void fragment() {
    if (!use_pattern) {
        COLOR = texture(TEXTURE, UV);
    } else {
        vec2 scroll_uv = UV + TIME * scroll_direction + vec2(pattern_seed, pattern_seed * 0.7);
        vec2 cell_uv = scroll_uv / density;
        vec2 cell_id = floor(cell_uv);
        vec2 local_uv = fract(cell_uv);

        // Stagger alternate rows by half a cell for diagonal flow
        float stagger = mod(cell_id.y, 2.0);
        local_uv.x = fract(local_uv.x + stagger * 0.5);

        vec2 p = local_uv - vec2(0.5);
        float s = shape_size;

        bool in_shape = false;
        if (shape_type == 0) {
            // Circle
            in_shape = length(p) < s;
        } else if (shape_type == 1) {
            // Square (Chebyshev)
            in_shape = max(abs(p.x), abs(p.y)) < s;
        } else if (shape_type == 3) {
            // Star (5-point): polar edge radius pulses 5 times per turn
            // (|cos(2.5a)| peaks at 5 angles over [-pi, pi]). Points face
            // outward at full size; valleys sit at the inner ratio.
            float ang = atan(p.y, p.x);
            float r = length(p);
            float star_s = s * mix(0.42, 1.0, pow(abs(cos(2.5 * ang)), 0.9));
            in_shape = r < star_s;
        } else if (shape_type == 4) {
            // Diamond (rhombus, vertices on the axes)
            in_shape = abs(p.x) + abs(p.y) < s;
        } else {
            // Triangle pointing up — minimum apex width for clean rendering
            float half_w = max((p.y + s) * 0.5, s * 0.15);
            in_shape = (p.y >= -s) && (p.y <= s) && (abs(p.x) < half_w);
        }

        if (in_shape) {
            COLOR = shape_color;
        } else {
            COLOR = background_color;
        }
    }
}
