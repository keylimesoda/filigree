#version 440

// Filigree satin: the finest-detail filter. Run once per keyframe as its
// bands are composed, never per frame.
//
// Where the wire is packed tighter than a few pixels, the direction it runs
// in changes from one pixel to the next. Each pixel's glint then flickers on
// or off as the view drifts by a fraction of a pixel, and dense lace crawls.
// Real metal worked that finely does not glitter; it takes a satin sheen.
// So for each texel of the wire, the directions around it are averaged over
// a footprint about as wide as the finest detail to keep. The average's
// direction replaces the stored one, and its length, the coherence (1 on a
// single clean wire, near 0 where directions disagree), scales the normal
// on the wire, which the bake leaves pointing away from the set at a fixed
// length, rim (shorter only where a texel's samples disagree). The surface
// widens each glint as the coherence falls,
// keeping its brightness, so fine lace shimmers as one sheen while clean
// curls stay sharp.
//
// Texels keep the layout fractal.frag bakes (see there); only the angle and,
// on the wire itself, the normal change. Directions are averaged as
// (cos, sin) of twice the angle across the wire, so the two sides of a thin
// filament agree.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // this band, in texels
    float aboveRows;  // rows in the band above it, 0 for none
    float belowRows;  // rows in the band below it, 0 for none
    float radius;     // footprint radius in texels, 1 to 4
    vec4 taps;        // footprint weights 1, 2, 3 and 4 texels out (1 at the middle)
    float fibreLevel; // ramp below which the angle is the wire's direction
    float metalCut;   // ramp below which the texel is drawn as wire
    float rim;        // length of the baked normal on the wire
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D above;
layout(binding = 3) uniform sampler2D below;

const float TAU = 6.28318530718;

// (cos, sin) of 2 pi x, to within 0.001 (as in surface.frag).
vec2 circle(float x) {
    vec2 t = fract(vec2(x + 0.25, x) + 0.5) - 0.5;
    vec2 y = 8.0 * t - 16.0 * t * abs(t);
    return 0.225 * (y * abs(y) - y) + y;
}

// A texel of the keyframe, by column and by row counted from this band's
// first; rows past it come from the neighbouring bands.
vec4 texel(int x, int y, int rows) {
    if (y < 0) {
        if (aboveRows > 0.5) return texelFetch(above, ivec2(x, max(int(aboveRows) + y, 0)), 0);
        y = 0;
    } else if (y >= rows) {
        if (belowRows > 0.5) return texelFetch(below, ivec2(x, min(y - rows, int(belowRows) - 1)), 0);
        y = rows - 1;
    }
    return texelFetch(source, ivec2(x, y), 0);
}

void main() {
    ivec2 extent = ivec2(size + 0.5);
    ivec2 c = clamp(ivec2(qt_TexCoord0 * size), ivec2(0), extent - 1);
    vec4 t = texelFetch(source, c, 0);
    fragColor = t;
    // Inside the set, and out where the angle is the tide's, nothing changes.
    float wireTop = fibreLevel - 1.0 / 255.0;
    if (t.b < 0.002 || t.b >= wireTop) return;

    int r = int(radius + 0.5);
    vec2 sum = vec2(0.0);
    float weight = 0.0;
    for (int j = -4; j <= 4; ++j) {
        if (j < -r || j > r) continue;
        float wy = j == 0 ? 1.0 : taps[abs(j) - 1];
        for (int i = -4; i <= 4; ++i) {
            if (i < -r || i > r) continue;
            float w = wy * (i == 0 ? 1.0 : taps[abs(i) - 1]);
            vec4 s = texel(clamp(c.x + i, 0, extent.x - 1), c.y + j, extent.y);
            if (s.b >= 0.002 && s.b < wireTop) {
                sum += w * circle(s.a);
                weight += w;
            }
        }
    }
    vec2 mean = sum / weight;
    float coherence = min(length(mean), 1.0);
    if (coherence < 0.004) coherence = 0.0;
    float angle = coherence > 0.0 ? atan(mean.y, mean.x) : TAU * t.a;
    if (coherence > 0.0) fragColor.a = fract(angle / TAU + 1.0);
    if (t.b < metalCut) {
        // The normal on the wire points away from the set, so its doubled
        // angle is the wire's direction: keep it pointing the same way.
        vec2 across = vec2(cos(0.5 * angle), sin(0.5 * angle));
        if (dot(across, t.rg * 2.0 - 1.0) < 0.0) across = -across;
        fragColor.rg = 0.5 + 0.5 * (rim * coherence) * across;
    }
}
