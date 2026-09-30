#version 440

// Filigree field, the float64 variant. Rendered once per keyframe, exactly as
// fractal.frag; this is the bake for the descent, where a plain focus (not a
// self-similar Misiurewicz point) is followed in float64 so the iteration
// stays exact past the float32 wall (a keyframe span near 1e-12 instead of
// 1e-5). The iteration runs in dvec2; the relief, grooves and ramp only need
// a few digits, so the float64 state is reduced to float32 for the rest.
//
// The focus and the Julia constant cannot ride in the std140 buffer at
// float64, so they come in as high+low float32 splits (centerHigh/centerLow,
// juliaConstantHigh/juliaConstantLow) and are reconstructed here.
//
// Output is the same RGBA8 as fractal.frag (normal, distance, angle), so the
// surface reads it identically.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec2 frame;
    vec2 center;
    vec2 anchor;
    vec2 turn;
    vec2 juliaConstant;
    vec2 refOffset;
    float span;
    float juliaMode;
    float iterationLimit;
    float samples;
    float rays;
    float relief;
    float wire;
    float bevel;
    float spacing;
    float tidePeriod;
    float refMode;
    float refStart;
    float refPre;
    float refPeriod;
    // The focus and the Julia constant as high+low float32 splits, so the
    // descent reaches the iteration at float64 precision.
    vec2 centerHigh;
    vec2 centerLow;
    vec2 juliaConstantHigh;
    vec2 juliaConstantLow;
};

const float TAU = 6.28318530718;
const float LN10 = 2.30258509299;
// Rotated-grid supersampling: four samples, no two sharing a row or column.
const vec2 RGSS[4] = vec2[](vec2(-0.375, -0.125), vec2(0.125, -0.375), vec2(0.375, 0.125), vec2(-0.125, 0.375));

vec2 cmul(vec2 a, vec2 b) { return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x); }
dvec2 cmul64(dvec2 a, dvec2 b) { return dvec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x); }

struct Sample {
    vec2 normal;
    vec2 fibre;   // twice the direction away from the set, as (cos, sin)
    float ramp;
    float mu;
    float inside;
};

Sample insideSample() {
    Sample s;
    s.normal = vec2(0.0);
    s.fibre = vec2(0.0);
    s.ramp = 0.0;
    s.mu = 0.0;
    s.inside = 1.0;
    return s;
}

// One point of the plane, iterated in float64.
Sample fieldAt(vec2 q, float pixel, float shorter, float wirePx, float groovePx) {
    // The local offset is small (a fraction of the span) and stays exact in
    // float32; the focus itself is the float64 part.
    vec2 local = cmul(q - anchor, turn) * span;
    dvec2 center64 = dvec2(centerHigh.x + centerLow.x, centerHigh.y + centerLow.y);
    dvec2 point64 = center64 + dvec2(local.x, local.y);
    dvec2 julia64 = dvec2(juliaConstantHigh.x + juliaConstantLow.x,
                          juliaConstantHigh.y + juliaConstantLow.y);
    dvec2 c64 = mix(point64, julia64, double(juliaMode));
    dvec2 z64 = mix(dvec2(0.0), point64, double(juliaMode));
    dvec2 d64 = dvec2(double(juliaMode), 0.0);
    float inc = 1.0 - juliaMode;
    double r2 = 0.0;
    float n = 0.0;
    float dexp = 0.0;
    const double escape2 = 1e10;
    // Plain iteration about a plain focus: no reference orbit, so float64
    // carries the whole value and holds far past the float32 wall.
    for (int i = 0; i < 5000; ++i) {
        if (float(i) >= iterationLimit) break;
        d64 = 2.0 * cmul64(z64, d64) + dvec2(double(inc), 0.0);
        z64 = cmul64(z64, z64) + c64;
        r2 = dot(z64, z64);
        n += 1.0;
        if (r2 > escape2) break;
        // Keep the derivative in range; dexp carries the exponent.
        if (dot(d64, d64) > 1e24) { d64 *= 1e-12; inc *= 1e-12; dexp += 12.0; }
    }
    if (!(r2 > escape2)) return insideSample();

    // The relief, the grooves and the ramp need only a few digits.
    vec2 z = vec2(float(z64.x), float(z64.y));
    vec2 d = vec2(float(d64.x), float(d64.y));
    float r2f = float(r2);
    Sample s;
    s.inside = 0.0;
    float logEscape = 0.5 * log(1e10);
    float lz = 0.5 * log(r2f);
    float degree = 2.0;
    float branch = max(2.0, floor(degree + 0.5));
    // nu runs from 0 at a band's outer equipotential to 1 at its inner one.
    float nu = 1.0 - log(lz / logEscape) / log(degree);
    s.mu = n - 1.0 + nu;

    // Both vectors are normalized before multiplying.
    vec2 dn = d * inversesqrt(max(dot(d, d), 1e-30));
    vec2 zn = z * inversesqrt(r2f);
    vec2 w = cmul(dn, vec2(zn.x, -zn.y));
    // Directions are found in the plane; turn them into screen space.
    vec2 outward = normalize(cmul(vec2(w.x, -w.y), vec2(turn.x, -turn.y)));
    vec2 around = vec2(-outward.y, outward.x);
    s.fibre = vec2(outward.x * outward.x - outward.y * outward.y, 2.0 * outward.x * outward.y);
    float logRate = 0.5 * log(max(dot(d, d), 1e-30)) + dexp * LN10 - lz + log(pixel);
    float rate = exp(clamp(logRate, -80.0, 80.0));
    float distancePx = 0.5 * lz / rate;
    s.ramp = log2(max(distancePx / shorter, 1e-9)) / 16.0 + 1.0;

    // Grooves follow external rays, as in fractal.frag.
    float theta = atan(z.y, z.x) / TAU * rays;
    float period = TAU / (rays * rate);
    float level = max(nu, log2(period / groovePx) / log2(branch));
    float base = floor(level);
    float blend = level - base;
    float scale0 = pow(branch, base);
    float u0 = fract(theta * scale0);
    float u1 = fract(theta * scale0 * branch);
    float p0 = period / scale0;
    float p1 = p0 / branch;
    float a0 = smoothstep(3.0, 5.0, p0);
    float a1 = smoothstep(3.0, 5.0, p1);
    float edge = 0.5 * wirePx;
    float fillet = max(2.5, 0.8 * wirePx);
    float cut = relief * smoothstep(edge, edge + fillet, distancePx);
    float slope = cut * ((1.0 - blend) * a0 * sin(TAU * u0) + blend * a1 * sin(TAU * u1));
    vec2 gradient = slope * around - outward * (bevel * exp(-max(distancePx - edge, 0.0) / fillet));
    s.normal = -gradient * inversesqrt(1.0 + dot(gradient, gradient));
    return s;
}

float hash(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec2 size = max(resolution, vec2(1.0));
    vec2 screen = max(frame, vec2(1.0));
    float shorter = min(screen.x, screen.y);
    float pixel = span / shorter;
    vec2 p = (qt_TexCoord0 - 0.5) * size / shorter;
    float wirePx = max(2.6, wire * shorter);
    // Finer than ~7 px the cuts alias against the pixel grid into moire.
    float groovePx = max(7.0, spacing * shorter);
    int count = samples > 1.5 ? 4 : 1;
    vec2 normal = vec2(0.0);
    vec2 fibre = vec2(0.0);
    vec2 tide = vec2(0.0);
    float ramp = 0.0;
    float outside = 0.0;
    for (int k = 0; k < 4; ++k) {
        if (k >= count) break;
        vec2 offset = count > 1 ? RGSS[k] : vec2(0.0);
        Sample s = fieldAt(p + offset / shorter, pixel, shorter, wirePx, groovePx);
        if (s.inside > 0.5) continue;
        outside += 1.0;
        normal += s.normal;
        fibre += s.fibre;
        ramp += s.ramp;
        float angle = TAU * s.mu / max(tidePeriod, 0.01);
        tide += vec2(cos(angle), sin(angle));
    }
    if (outside < 0.5) {
        fragColor = vec4(0.5, 0.5, 0.0, 0.0);
        return;
    }
    normal /= outside;
    ramp /= outside;
    float fibreLevel = log2((0.5 * wirePx + 1.5) / shorter) / 16.0 + 1.0;
    vec2 direction = ramp < fibreLevel ? fibre : tide;
    float phase = fract(atan(direction.y, direction.x) / TAU + 1.0);
    float dither = (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    float code = outside < float(count) - 0.5 ? 0.2 * outside / float(count)
                                              : max(ramp, 0.2 + 1.0 / 255.0) + dither;
    fragColor = vec4(normal * 0.5 + 0.5 + dither, code, phase);
}
