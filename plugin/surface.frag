#version 440

// Filigree surface: one read of the baked field per pixel, then light.
// Everything here is plain arithmetic (no transcendental functions) because
// the desktop may be rendered on the CPU. Colour products that do not vary
// per pixel arrive precomputed from QML.
//
// Built five times: plain; with DIVE for a diving or scaled view, where the
// field comes from the baked keyframe just above the current zoom, magnified
// onto the screen by a similarity about the focus; with DIVE and BLEND while
// the keyframe just below it, minified, fades in; with DISSOLVE too for the
// step where a loop that does not repeat itself returns to its start: there
// the two keyframes hold different pictures, so each is lit and the results
// are cross-faded; and with DIVE and STRETCH while a keyframe baked for other
// settings stands in, stretched into place, for one that is still baking.
// A software rasteriser pays for code it skips, so each build holds only
// what it runs. Keyframes are sampled with filtering;
// the angle channel wraps, so it is also fetched unfiltered, and the filtered
// value is only trusted where the two agree.
//
// Nothing is allowed to be thinner than the pixel grid can carry. Pools are
// antialiased by how much of each texel they cover, the wire's edge over a
// fixed width in pixels, and the wire is lit as a bundle of fine fibres, so
// its highlight depends only on which way it runs and glides along it as the
// lights turn. Where the wire's direction changes faster than the finest
// detail kept, satin.frag has averaged it and left its coherence as the
// length of the normal; there each glint is widened into a sheen of the same
// brightness, so fine lace shimmers instead of crawling. The tide and the
// colour flow stay out of the tight bands next to the set, where they would
// crawl.
//
// Dark themes use dark-field lighting, the way engraved metal is shot in a
// studio: flat polish stays dark and every cut glows where its flank mirrors
// one of the lights. Light themes use bright-field lighting instead, so the
// same cuts read as coloured ink on a pale ground, like an intaglio print.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec3 keyDirection;
    vec3 fillDirection;
    vec3 thirdDirection;
    // A fibre t lying across angle a (the wire runs at a + 90 deg) meets a
    // light's half vector h with (t.h)^2 = dot(keyFibre, (1, cos 2a, sin 2a)).
    vec3 keyFibre;
    vec3 fillFibre;
    vec3 thirdFibre;
    vec2 aspect;
    vec2 focal;
    vec2 originA;    // the focus, in keyframe A's shorter-side units
    vec2 originB;
    vec2 viewA;      // screen -> keyframe A about the focus, as a complex factor
    vec2 viewB;      // screen -> keyframe B
    vec2 invExtentA; // 1 / keyframe size in shorter-side units (a keyframe has a margin)
    vec2 invExtentB;
    vec2 texelsA;    // keyframe size in texels
    vec2 texelsB;
    float blendB;    // weight of keyframe B
    float phaseA;    // tide phase offsets that keep a looping dive continuous
    float phaseB;
    float flow;      // amount of palette flow along the bands (0 = off)
    float flowPhase; // palette position, advancing with time
    float flowScale; // palette cycles per tide period
    float tide;
    float tideStrength;
    float metalLevel; // distance ramp at the wire's edge
    float metalEdge;  // ramp over which that edge is antialiased
    float tideNear;   // ramp where the tide and colour flow begin
    float tideFar;    // ramp where they reach full strength
    // Satin: 1 when the field holds the wire's coherence (see satin.frag).
    // The means of each light's glints over every direction the wire can
    // run, as (E16 / E4, E16, E64 / E16, E128 / E64), where Es is the mean
    // of q^s, keep a widened glint as bright as the glitter it replaces.
    float satin;
    float metalCut;   // ramp below which texels carry the coherence
    float invRim;     // 1 / length of the normal on a clean wire
    vec4 keyMeans;
    vec4 fillMeans;
    vec4 thirdMeans;
    // Flat wire as the eye sees the glitter, less the flat wire from the
    // means, at the scale e it is drawn at: a cubic in e, lowest power
    // first, added as far as the glints have flattened.
    vec3 satinShift0;
    vec3 satinShift1;
    vec3 satinShift2;
    vec3 satinShift3;
    // The same for the share of that glitter which was dull, having lost its
    // direction where a magnified field's normals cancel; added where they
    // still do (zero unless satin is on).
    vec3 satinDull0;
    vec3 satinDull1;
    vec3 satinDull2;
    vec3 satinDull3;
    float dome;
    float brightField;
    float thirdStrength;
    float vignette;
    vec3 ground;     // theme background
    vec3 key;        // warm key light
    vec3 fill;       // cool fill light
    vec3 third;      // third light (iridescent mode, or vivid colour)
    vec3 enamel;     // tint of the tilted plate
    vec3 gold;       // the raised filigree
    vec3 pearl;      // hottest glints
    vec3 keySheen;   // deepened broad lobes of each light
    vec3 fillSheen;
    vec3 thirdSheen;
    vec3 wireDeep;   // filigree facing away from every light
    vec3 wireKey;    // filigree under the key
    vec3 wireThird;  // filigree under the third light
    vec3 wireHot;    // hottest point of the filigree
    vec3 glassBase;  // the pools inside the set
    vec3 flow0;      // palette flowing along the bands, as a loop of six
    vec3 flow1;      // colours of equal brightness; flow1..6 are stored as
    vec3 flow2;      // differences from the previous stop
    vec3 flow3;
    vec3 flow4;
    vec3 flow5;
    vec3 flow6;
};
layout(binding = 1) uniform sampler2D field;
layout(binding = 2) uniform sampler2D fieldB;

vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }

// Mirror reflection of the view ray (0, 0, 1) about n, against light l.
float mirror(vec3 n, vec3 l) {
    return max(2.0 * n.z * dot(n, l) - l.z, 0.0);
}

// (cos, sin) of 2 pi x, to within 0.001.
vec2 circle(float x) {
    vec2 t = fract(vec2(x + 0.25, x) + 0.5) - 0.5;
    vec2 y = 8.0 * t - 16.0 * t * abs(t);
    return 0.225 * (y * abs(y) - y) + y;
}

// The wire's direction, as (cos, sin) of twice the angle across it. The bake
// stores it in the angle channel of the texel t. A magnified keyframe takes
// it from the filtered normal g instead, which on the wire points straight
// away from the set and glides smoothly between texels; only across a
// filament finer than a pixel, where the normals of its two sides cancel,
// does the stored angle, which cannot cancel, take over.
vec2 direction(vec4 t, vec4 g, out float trust) {
#ifdef DIVE
    vec2 n = g.rg * 2.0 - 1.0;
    float m = dot(n, n);
    vec2 fromNormal = vec2(n.x * n.x - n.y * n.y, 2.0 * n.x * n.y) / max(m, 1e-4);
    // A texel inside the set holds no angle.
    trust = t.b < 0.002 ? 1.0 : smoothstep(0.02, 0.08, m);
    return mix(circle(t.a), fromNormal, trust);
#else
    trust = 1.0;
    return circle(t.a);
#endif
}

// How well the wire keeps one direction across the finest detail kept, from
// the unfiltered texel t: 1 on a clean wire, falling towards 0 in lace too
// fine to glint. Only the wire's own texels carry it.
float coherence(vec4 t) {
    vec2 n = t.rg * 2.0 - 1.0;
    float k = min(sqrt(dot(n, n)) * invRim, 1.0);
    return t.b >= 0.002 && t.b < metalCut ? k : 1.0;
}

// A glint of sharpness s, widened: the share w of it that the wire's
// coherence keeps stays sharp, and the rest goes to the next broader lobe,
// scaled to the same mean over all directions, so the widened glint is as
// bright on average as the glitter it replaces.
float widen(float sharp, float broader, float scale, float w) {
    return broader * scale + w * (sharp - broader * scale);
}

#ifdef DIVE
// The tide phase wraps, so the filtered value is garbage where the four
// texels straddle the wrap; there, and where the phase is steep, the
// unfiltered texel is used.
float tideOf(float filtered, float nearest) {
    return abs(filtered - nearest) < 0.08 ? filtered : nearest;
}
#endif

vec3 palette(float phase) {
    float h = fract(phase * flowScale - flowPhase) * 6.0;
    return flow0 + flow1 * clamp(h, 0.0, 1.0) + flow2 * clamp(h - 1.0, 0.0, 1.0)
         + flow3 * clamp(h - 2.0, 0.0, 1.0) + flow4 * clamp(h - 3.0, 0.0, 1.0)
         + flow5 * clamp(h - 4.0, 0.0, 1.0) + flow6 * clamp(h - 5.0, 0.0, 1.0);
}

// Inside the set: a pool of enamel within the gold, curved more than the
// plate so each pool holds part of one broad, soft reflection that wanders
// with the lights.
vec3 glass(vec2 p) {
    vec2 bxy = 0.55 * p;
    vec3 bowl = vec3(bxy, sqrt(max(1.0 - dot(bxy, bxy), 0.0)));
    float bk = mirror(bowl, keyDirection);
    float bf = mirror(bowl, fillDirection);
    float bt = 0.0;
    bk *= bk; bk *= bk; bk *= bk;
    bf *= bf; bf *= bf; bf *= bf;
    if (thirdStrength > 0.0) {
        bt = mirror(bowl, thirdDirection);
        bt *= bt; bt *= bt; bt *= bt;
        bt *= thirdStrength;
    }
    if (brightField < 0.5)
        return glassBase + key * (0.3 * bk) + fill * (0.22 * bf) + third * (0.22 * bt);
    return glassBase + (vec3(1.0) - glassBase) * (bk * 0.35 + bf * 0.25 + bt * 0.25);
}

// Outside the set: the engraved plate and the raised wire. g.a is the tide
// phase; t is the unfiltered texel, for the wire's direction and coherence.
vec3 plate(vec4 g, vec4 t, vec2 p) {
    // ramp = log2(distance / shorter side) / 16 + 1; nearer than 0.2 only
    // coverage is known, and that is the wire's inner edge.
    float ramp = max(g.b, 0.2);
    // The plate is very slightly domed, so reflections drift across it.
    vec2 nxy = g.rg * 2.0 - 1.0 + dome * p;
    float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
    vec3 n = vec3(nxy, nz);
    float tilt = 1.0 - nz;
    float metal = 1.0 - smoothstep(metalLevel - 0.5 * metalEdge, metalLevel + 0.5 * metalEdge, ramp);
    float quiet = smoothstep(0.84, 0.97, ramp);
    float near = 1.0 - smoothstep(metalLevel, metalLevel + 0.12, ramp);
    float lace = smoothstep(0.2, metalLevel, ramp);
    float open = smoothstep(tideNear, tideFar, ramp);

    float rk = mirror(n, keyDirection);
    float rf = mirror(n, fillDirection);
    float rk2 = rk * rk, rk4 = rk2 * rk2, rk8 = rk4 * rk4, rk16 = rk8 * rk8, rk32 = rk16 * rk16;
    float rf2 = rf * rf, rf4 = rf2 * rf2, rf8 = rf4 * rf4, rf16 = rf8 * rf8, rf32 = rf16 * rf16;
    float rk64 = rk32 * rk32;
    float rt8 = 0.0, rt32 = 0.0;
    if (thirdStrength > 0.0) {
        float rt = mirror(n, thirdDirection);
        float rt2 = rt * rt, rt4 = rt2 * rt2;
        rt8 = rt4 * rt4;
        float rt16 = rt8 * rt8;
        rt32 = rt16 * rt16 * thirdStrength;
        rt8 *= thirdStrength;
    }

    // A slow tide of light runs down the equipotentials into the lace.
    float wave = fract(g.a - tide);
    float pulse = wave * (1.0 - wave) * 4.0;
    pulse *= pulse;
    float cutGain = (1.0 - 0.6 * quiet) * (1.0 + tideStrength * open * pulse * pulse * (1.0 - quiet));

    vec3 color;
    if (brightField < 0.5) {
        // Broad lobes use a deepened tint so dim cuts stay saturated; the
        // narrow cores carry the pure theme colour.
        vec3 sheen = keySheen * rk8 + key * (1.2 * rk32)
                   + fillSheen * rf8 + fill * rf32
                   + thirdSheen * rt8 + third * rt32;
        if (flow > 0.0) {
            // Colour runs along the bands like heat tint on steel: the cuts
            // keep their brightness and take the palette's hue.
            sheen = mix(sheen, palette(g.a) * dot(sheen, vec3(0.2126, 0.7152, 0.0722)), flow * open);
        }
        color = ground * (1.0 - 0.35 * near) + enamel * (0.4 * tilt)
              + sheen * cutGain + pearl * (0.4 * rk64);
    } else {
        // Bright field: cuts are inked in the light's colour on a pale ground.
        float cutK = 0.3 * rk8 + 1.2 * rk32;
        float cutF = 0.25 * rf8 + rf32;
        float cutT = 0.25 * rt8 + rt32;
        color = ground * (1.0 - 0.1 * near - 1.3 * tilt);
        vec3 inkK = key, inkF = fill;
        if (flow > 0.0) {
            vec3 tint = palette(g.a);
            inkK = mix(key, tint, flow * open);
            inkF = mix(fill, tint, flow * open);
        }
        color = mix(color, inkK * 0.85, clamp(cutK * cutGain * 0.55, 0.0, 0.8));
        color = mix(color, inkF * 0.85, clamp(cutF * cutGain * 0.5, 0.0, 0.8));
        color = mix(color, third * 0.85, clamp(cutT * cutGain * 0.5, 0.0, 0.8));
    }

    if (metal > 0.0) {
        // The wire is lit as drawn gold wire, a bundle of fibres along its
        // length (Kajiya-Kay). A fibre can only mirror a light whose half vector it
        // crosses at right angles, so each light picks out the stretches
        // of wire that run across it, and those glints glide along the
        // curls as the lights turn. Gold is deep where nothing catches
        // (gold squared, as after several bounces): copper under the key,
        // clean gold under the fill, near white at the hottest point.
        float trust;
        vec3 f = vec3(1.0, direction(t, g, trust));
        float qk = 1.0 - dot(keyFibre, f);
        float qf = 1.0 - dot(fillFibre, f);
        float qk2 = qk * qk, qk4 = qk2 * qk2, qk8 = qk4 * qk4, qk16 = qk8 * qk8;
        float qk32 = qk16 * qk16, qk64 = qk32 * qk32, qk128 = qk64 * qk64;
        float qf2 = qf * qf, qf4 = qf2 * qf2, qf8 = qf4 * qf4, qf16 = qf8 * qf8;
        float qf64 = qf16 * qf16; qf64 *= qf64;
        // Rounded across its width: brightest along the middle, darker at
        // the rims where it curves away from the lights.
        float body = 1.0 - 0.45 * lace * lace;
        // Lace finer than the finest detail kept is lit as satin: as the
        // coherence k falls, the broadest glint flattens to its mean over
        // all directions and each sharper one hands part of itself to the
        // one below it. At k = 1 every glint is left exactly as it was.
        float k = 1.0, k2 = 1.0, k4 = 1.0;
        vec3 shift = vec3(0.0);
        if (satin > 0.5) {
            k = coherence(t);
            k2 = k * k;
            k4 = k2 * k2;
            float k16 = k4 * k4;
            k16 *= k16;
            qk16 = widen(qk16, keyMeans.y + k * (keyMeans.x * qk4 - keyMeans.y), 1.0, k2);
            qk64 = widen(qk64, qk16, keyMeans.z, k4 * k);
            qk128 = widen(qk128, qk64, keyMeans.w, k16);
            qf16 = widen(qf16, fillMeans.y + k * (fillMeans.x * qf4 - fillMeans.y), 1.0, k2);
            qf64 = widen(qf64, qf16, fillMeans.z, k4);
            float e = clamp(body * (1.0 - vignette * smoothstep(0.05, 0.9, dot(p, p))), 0.3, 1.0);
            shift = (satinShift0 + e * (satinShift1 + e * (satinShift2 + e * satinShift3))) * (1.0 - k4 * k)
                  + (satinDull0 + e * (satinDull1 + e * (satinDull2 + e * satinDull3))) * (1.0 - trust);
        }
        vec3 wire;
        if (brightField < 0.5) {
            wire = wireDeep * 0.3
                 + wireKey * (0.3 * qk16 + 1.2 * qk64)
                 + gold * (0.18 * qf16 + 0.8 * qf64)
                 + wireHot * (0.9 * qk128)
                 + shift;
            if (thirdStrength > 0.0) {
                float qt = 1.0 - dot(thirdFibre, f);
                float qt2 = qt * qt, qt4 = qt2 * qt2, qt8 = qt4 * qt4, qt16 = qt8 * qt8;
                float qt64 = qt16 * qt16; qt64 *= qt64;
                if (satin > 0.5) {
                    qt16 = widen(qt16, thirdMeans.y + k * (thirdMeans.x * qt4 - thirdMeans.y), 1.0, k2);
                    qt64 = widen(qt64, qt16, thirdMeans.z, k4);
                }
                wire += wireThird * ((0.2 * qt16 + 0.8 * qt64) * thirdStrength);
            }
            wire *= body;
        } else {
            float lit = 0.6 * qk16 + 0.4 * qf16;
            wire = gold * ((0.4 + 0.7 * lit) * body) + wireHot * ((0.6 * qk64 + 0.35 * qf64) * body)
                 + shift * body;
        }
        color = mix(color, wire, metal);
    }
    return color;
}

vec3 shade(vec4 g, vec4 t, vec2 p) {
    // Below 0.2 the field codes how much of the texel lies outside the set.
    float pool = 1.0 - clamp(g.b * 5.0, 0.0, 1.0);
    vec3 color = vec3(0.0);
    if (pool < 1.0) color = plate(g, t, p);
    if (pool > 0.0) color = mix(color, glass(p), pool);
    return color;
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * aspect - focal;
#ifdef DIVE
    vec2 uva = (originA + cmul(p, viewA)) * invExtentA + 0.5;
    vec4 g = textureLod(field, uva, 0.0);
    vec4 ta = texelFetch(field, clamp(ivec2(uva * texelsA), ivec2(0), ivec2(texelsA) - 1), 0);
#ifdef STRETCH
    // A keyframe baked for another view, stretched into place until the new
    // one lands: past its edges lies bare, flat plate, fading in over a few
    // texels.
    vec2 edge = clamp(min(uva, 1.0 - uva) * texelsA * 0.125, 0.0, 1.0);
    float within = edge.x * edge.y;
    g = mix(vec4(0.5, 0.5, 1.0, 0.0), g, within);
    ta = mix(vec4(0.5, 0.5, 1.0, 0.0), ta, within);
#endif
    g.a = tideOf(g.a, ta.a) + phaseA;
#ifdef BLEND
    // B is minified, but its margin still covers the screen.
    vec2 uvb = (originB + cmul(p, viewB)) * invExtentB + 0.5;
    vec4 h = textureLod(fieldB, uvb, 0.0);
    vec4 tb = texelFetch(fieldB, clamp(ivec2(uvb * texelsB), ivec2(0), ivec2(texelsB) - 1), 0);
    h.a = tideOf(h.a, tb.a) + phaseB;
#ifdef DISSOLVE
    vec3 color = mix(shade(g, ta, p), shade(h, tb, p), blendB);
#else
    g.rgb = mix(g.rgb, h.rgb, blendB);
    g.a += blendB * (fract(h.a - g.a + 0.5) - 0.5);
    vec3 color = shade(g, blendB < 0.5 ? ta : tb, p);
#endif
#else
    vec3 color = shade(g, ta, p);
#endif
#else
    vec4 g = texture(field, qt_TexCoord0);
    vec3 color = shade(g, g, p);
#endif
    color *= 1.0 - vignette * smoothstep(0.05, 0.9, dot(p, p));
    fragColor = vec4(color, 1.0);
}
