#version 440

// Filigree field. Rendered once per keyframe and screen size; theme colours
// and all animation are applied later by surface.frag, so this never reruns
// while the wallpaper plays or when the theme changes.
//
// Output, one RGBA8 texel per screen pixel:
//   r,g  surface normal (x right, y down) of the engraved relief, n * 0.5 + 0.5
//   b    below 0.2, how much of the texel lies inside the set: 0 for all of
//        it, 0.05 more for each quarter outside. From 0.2 up, the distance to
//        the set, log2(d / shorter side) / 16 + 1.
//   a    on and beside the wire (b below the level at the wire's edge plus
//        1.5 px), the direction across it, away from the set, as
//        fract(angle / pi); elsewhere the tide phase,
//        fract(smooth escape count / tidePeriod)
//
// Every feature is shaped to be a couple of pixels across before it is lit:
// the grooves are sine corrugations that fade out before they would be finer
// than the pixel grid, the wire is never thinner than 2.6 px, and it rises
// out of a fillet whose slope changes slowly enough that a reflection off it
// is about two pixels wide. Four rotated-grid samples per texel do the rest.
//
// This file is also the template for custom equations: build-shaders writes
// it out as fractal-template.glsl with CUSTOM_EQUATION defined, where
// equation-compiler.py fills in the iteration.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec2 frame;      // the screen, in texels; smaller than resolution for a margin
    vec2 center;
    vec2 anchor;
    vec2 turn;
    vec2 juliaConstant;
    vec2 refOffset;  // center minus the reference point, when refMode is on
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
    float refMode;   // 1: follow each pixel as an offset from a reference orbit
    float refStart;  // where that orbit starts in ORBIT
    float refPre;    // steps before it repeats
    float refPeriod; // length of the repeating part
};

const float TAU = 6.28318530718;
const float LN10 = 2.30258509299;
// Rotated-grid supersampling: four samples, no two sharing a row or column.
const vec2 RGSS[4] = vec2[](vec2(-0.375, -0.125), vec2(0.125, -0.375), vec2(0.375, 0.125), vec2(-0.125, 0.375));

vec2 cmul(vec2 a, vec2 b) { return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x); }

#ifdef CUSTOM_EQUATION
vec2 cdiv(vec2 a, vec2 b) { return cmul(a, vec2(b.x, -b.y)) / max(dot(b, b), 1e-20); }
vec2 cpow(vec2 a, int n) {
    vec2 result = vec2(1.0, 0.0);
    for (int j = 0; j < 8; ++j) { if (j >= n) break; result = cmul(result, a); }
    return result;
}
vec2 cexp(vec2 z) { return exp(clamp(z.x, -20.0, 20.0)) * vec2(cos(z.y), sin(z.y)); }
vec2 csin(vec2 z) {
    float e = exp(clamp(z.y, -20.0, 20.0));
    return vec2(sin(z.x) * (e + 1.0/e) * 0.5, cos(z.x) * (e - 1.0/e) * 0.5);
}
vec2 ccos(vec2 z) {
    float e = exp(clamp(z.y, -20.0, 20.0));
    return vec2(cos(z.x) * (e + 1.0/e) * 0.5, -sin(z.x) * (e - 1.0/e) * 0.5);
}
vec2 cconj(vec2 z) { return vec2(z.x, -z.y); }
vec2 cabs(vec2 z) { return vec2(length(z), 0.0); }
vec2 cabs2(vec2 z) { return vec2(abs(z.x), abs(z.y)); }
vec2 iterate(vec2 z, vec2 c) { return /* EQUATION */; }
#else
// Reference orbits of the dive points, written by divepoints.py: the
// critical orbit of each Misiurewicz point (for a Julia set, its repelling
// fixed point) up to where it starts repeating. The last entry is zero and
// its own successor; following it is plain iteration.
// ORBIT BEGIN
const int ORBIT_LENGTH = 32;
// Starts: filigree 0, seahorse 5, julia 30; the last entry is plain iteration.
const vec2 ORBIT[ORBIT_LENGTH] = vec2[](
    vec2(0.000000000e+00, 0.000000000e+00),
    vec2(-1.010963638e-01, 9.562865108e-01),
    vec2(-1.005359780e+00, 7.629323327e-01),
    vec2(3.275861787e-01, -5.777564533e-01),
    vec2(-3.275861787e-01, 5.777564533e-01),
    vec2(0.000000000e+00, 0.000000000e+00),
    vec2(-7.756837680e-01, 1.364673683e-01),
    vec2(-1.926218027e-01, -7.524367660e-02),
    vec2(-7.442422200e-01, 1.654545135e-01),
    vec2(-2.491624820e-01, -1.098091007e-01),
    vec2(-7.256598642e-01, 1.911879844e-01),
    vec2(-2.856543750e-01, -1.410075253e-01),
    vec2(-7.139684683e-01, 2.170262013e-01),
    vec2(-3.130331664e-01, -1.734323608e-01),
    vec2(-7.077727885e-01, 2.450475304e-01),
    vec2(-3.347897400e-01, -2.104085795e-01),
    vec2(-7.078713683e-01, 2.773526355e-01),
    vec2(-3.515263783e-01, -2.561926110e-01),
    vec2(-7.177476272e-01, 3.165842897e-01),
    vec2(-3.607477241e-01, -3.179878772e-01),
    vec2(-7.466611376e-01, 3.658941742e-01),
    vec2(-3.520594603e-01, -4.099305525e-01),
    vec2(-8.197809623e-01, 4.251072264e-01),
    vec2(-2.843590959e-01, -5.605222540e-01),
    vec2(-1.009008870e+00, 4.552465710e-01),
    vec2(3.516569093e-02, -7.822282879e-01),
    vec2(-1.386328237e+00, 8.145217187e-02),
    vec2(1.139587755e+00, -8.937152330e-02),
    vec2(5.149892145e-01, -6.722601893e-02),
    vec2(-5.149892145e-01, 6.722601893e-02),
    vec2(-5.275031186e-01, 7.591217835e-02),
    vec2(0.0, 0.0)
);
// ORBIT END
const int PLAIN = ORBIT_LENGTH - 1;
#endif

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

// One point of the plane: grooves cut along the external rays, a raised wire
// along the boundary of the set, and a tide coordinate on the equipotentials.
Sample fieldAt(vec2 q, float pixel, float shorter, float wirePx, float groovePx) {
    vec2 local = cmul(q - anchor, turn) * span;
    vec2 point = center + local;
    vec2 c = mix(point, juliaConstant, juliaMode);
    vec2 z = mix(vec2(0.0), point, juliaMode);
    vec2 d = vec2(juliaMode, 0.0);
    float inc = 1.0 - juliaMode;
    float dexp = 0.0;
    float r2 = 0.0;
    float n = 0.0;
#ifdef CUSTOM_EQUATION
    float escape2 = 1e6;
    float previous = 0.0;
#else
    float escape2 = 1e10;
    // The main cardioid and period-2 bulb are known to be inside; skipping
    // them keeps whole-set views from spending the full iteration budget.
    if (juliaMode < 0.5) {
        vec2 k = point - vec2(0.25, 0.0);
        float r = dot(k, k);
        if (r * (r + k.x) < 0.25 * point.y * point.y) return insideSample();
        vec2 b = point + vec2(1.0, 0.0);
        if (dot(b, b) < 0.0625) return insideSample();
    }
    // Deep in a dive, float32 cannot tell neighbouring pixels apart, so each
    // pixel is followed as an offset from the dive point's exactly known
    // orbit (z = ORBIT[j] + delta), which float32 holds to full precision.
    // A pixel that wanders off that orbit is rebased: its whole value becomes
    // the offset from the orbit's zero entry, and deltaC, the small offset of
    // c, is kept, so c is never rounded to float32. A Julia set's constant is
    // the same for every pixel, so there plain iteration takes over.
    int j = PLAIN, loopStart = PLAIN, orbitEnd = PLAIN + 1, restart = PLAIN;
    vec2 delta = z, deltaC = c;
    if (refMode > 0.5) {
        j = int(refStart + 0.5);
        loopStart = j + int(refPre + 0.5);
        orbitEnd = loopStart + int(refPeriod + 0.5);
        vec2 offset = refOffset + local;
        restart = juliaMode > 0.5 ? PLAIN : j;
        delta = juliaMode > 0.5 ? offset : vec2(0.0);
        deltaC = juliaMode > 0.5 ? vec2(0.0) : offset;
    }
    vec2 reference = ORBIT[j];
#endif
    for (int i = 0; i < 5000; ++i) {
        if (float(i) >= iterationLimit) break;
#ifdef CUSTOM_EQUATION
        vec2 hz = vec2(max(1e-4, 1e-3 * length(z)), 0.0);
        vec2 hc = vec2(max(1e-4, 1e-3 * length(c)), 0.0);
        vec2 dz = (iterate(z + hz, c) - iterate(z - hz, c)) / (2.0 * hz.x);
        vec2 dc = (iterate(z, c + hc) - iterate(z, c - hc)) / (2.0 * hc.x);
        d = cmul(dz, d) + inc * dc;
        previous = r2;
        z = iterate(z, c);
#else
        d = 2.0 * cmul(reference + delta, d) + vec2(inc, 0.0);
        delta = cmul(2.0 * reference + delta, delta) + deltaC;
        j = j + 1 < orbitEnd ? j + 1 : loopStart;
        reference = ORBIT[j];
        z = reference + delta;
        // Apart from the zero entries, every orbit value is at least 0.2
        // from zero (divepoints.py checks), so an offset under 0.05 can
        // never swamp z.
        if (dot(delta, delta) > 0.0025) {
            delta = z;
            j = restart;
            reference = vec2(0.0);
            if (restart == PLAIN) {
                deltaC = c;
                loopStart = PLAIN;
                orbitEnd = PLAIN + 1;
            }
        }
#endif
        r2 = dot(z, z);
        n += 1.0;
        if (r2 > escape2) break;
        // Keep the derivative inside float range; dexp carries the exponent.
        if (dot(d, d) > 1e24) { d *= 1e-12; inc *= 1e-12; dexp += 12.0; }
    }
    if (!(r2 > escape2)) return insideSample();

    Sample s;
    s.inside = 0.0;
    float logEscape = 0.5 * log(escape2);
    float lz = 0.5 * log(r2);
    float degree = 2.0;
#ifdef CUSTOM_EQUATION
    degree = clamp(log(r2) / max(log(max(previous, 1.0001)), 0.05), 1.5, 8.0);
#endif
    float branch = max(2.0, floor(degree + 0.5));
    // nu runs from 0 at a band's outer equipotential to 1 at its inner one.
    float nu = 1.0 - log(lz / logEscape) / log(degree);
    s.mu = n - 1.0 + nu;

    // Both vectors are normalized before multiplying: their raw product
    // overflows deep in a band and would tear the field at band edges.
    vec2 dn = d * inversesqrt(max(dot(d, d), 1e-30));
    vec2 zn = z * inversesqrt(r2);
    vec2 w = cmul(dn, vec2(zn.x, -zn.y));
    // Directions are found in the plane; turn them into screen space.
    vec2 outward = normalize(cmul(vec2(w.x, -w.y), vec2(turn.x, -turn.y)));
    vec2 around = vec2(-outward.y, outward.x);
    s.fibre = vec2(outward.x * outward.x - outward.y * outward.y, 2.0 * outward.x * outward.y);
    float logRate = 0.5 * log(max(dot(d, d), 1e-30)) + dexp * LN10 - lz + log(pixel);
    float rate = exp(clamp(logRate, -80.0, 80.0));
    float distancePx = 0.5 * lz / rate;
    s.ramp = log2(max(distancePx / shorter, 1e-9)) / 16.0 + 1.0;

    // Grooves follow external rays. Each band doubles the ray count; the new
    // grooves are grown continuously across the band so there are no seams.
    // Far from the set, extra levels keep the cut at the requested spacing.
    // The cut is a sine, so its slope never jumps, and it fades out before
    // it gets fine enough to alias.
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
    // The wire rises out of a fillet: its slope decays over a few pixels,
    // so the rim reflections are soft and wide, and the grooves run out on it.
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
