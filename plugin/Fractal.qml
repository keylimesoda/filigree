import QtQuick

// Filigree renders in two stages so that animation costs almost nothing.
//  * A bake (fractal.frag) renders the engraved relief once per keyframe:
//    surface normal, distance to the set and one angle in an RGBA8 texel per
//    pixel. It holds no colour, so theme changes never re-bake.
//  * surface (surface.frag) reads that texture once per pixel every frame and
//    lights it with slowly orbiting, theme-coloured lights.
// A dive zooms slowly into the focus. Keyframes are baked one zoom step
// apart: two are kept, the surface maps each onto the screen and cross-fades
// between them, and one new keyframe is baked per step. Every bake is spread
// over several frames, a band of rows at a time, so neither a dive nor a
// change of settings ever stalls a frame; until a new bake lands, the old
// keyframe is stretched into its place. At a self-similar focus (a
// Misiurewicz point) the dive is endless: one loop deeper, the view repeats
// itself, and each pixel is followed as an offset from the point's exactly
// known orbit, so it stays sharp at any depth. Any other view dives in for
// one loop and then dissolves back to where it started.
Item {
  id: root
  property color backgroundColor: "#2c2525"
  property color accentColor: "#f38d70"
  property color foregroundColor: "#e6d9db"
  property color secondaryColor: "#85dacc"
  property color tertiaryColor: "#a8a9eb"
  property color goldColor: "#f9cc6c"
  // More of the theme's colours (strings or colours); vivid settings let the
  // colour flow borrow the two whose hues are least like the others.
  property var extraColors: []
  property bool lightTheme: false
  // Vibrancy. At 1 the theme's colours are used as they are. Lower, they are
  // muted and drawn towards the metal's hue, so the piece reads as a few
  // quiet colours; higher, they are saturated, a third light joins the two,
  // and the colour flow takes in more of the theme's hues.
  property real intensity: 1.0
  property real motion: 0.55
  property real speed: 1.0
  property real centerX: -0.10469636
  property real centerY: 0.95868651
  property real span: 0.03
  // Where the composition's interest sits, in shorter-side units from the
  // middle of the screen: dives, the vignette and the dome centre here.
  property real focusX: 0.12
  property real focusY: -0.08
  property bool julia: false
  property real juliaReal: -0.8
  property real juliaImag: 0.156
  property int iterations: 1500
  property int colorMode: 0
  property real density: 1.0
  // Dive: zoom speed (0 holds the view) and the loop it follows. Each loop
  // zooms in by loopScale over loopSteps keyframes. At a self-similar focus
  // the next loop continues the last, turned by loopTurn with its tide phase
  // shifted by loopPhase; such a focus is only self-similar in the limit, so
  // the loop starts repeating loopEntry loops in, where one loop matches the
  // next closely enough to fade between them. With dissolve the view instead
  // cross-dissolves back to its start at the end of every loop.
  property real zoom: 0
  property real zoomTime: 0
  property real loopScale: 3
  property real loopTurn: 0
  property real loopPhase: 0
  property int loopSteps: 8
  property int loopEntry: 0
  property bool dissolve: true
  // The non-self-similar descent: a plain focus followed in float64, so the
  // dive keeps revealing new structure instead of cross-dissolving back.
  property bool descent: false
  // Perturbation: the dive point and where its exact orbit sits in the bake
  // shader's ORBIT table (written by divepoints.py).
  property bool reference: false
  property real referenceX: 0
  property real referenceY: 0
  property int orbitStart: 0
  property int orbitPre: 0
  property int orbitPeriod: 1
  // Colour cycling: how strongly the palette flows along the bands (0 = off).
  property real colorCycle: 0
  property real orbitTime: 0
  property bool customEquation: false
  property url shaderUrl: Qt.resolvedUrl("fractal.frag.qsb")
  // The float64 bake for the descent; a plain focus is iterated in dvec2 so
  // the dive holds past the float32 wall.
  property url shaderUrl64: Qt.resolvedUrl("fractal-fp64.frag.qsb")
  // Frame-rate cap. The wallpaper only draws as often as its motion needs.
  property int fps: 30
  property int maxDimension: 3840
  property bool playing: true
  property real elapsed: 0
  property bool baked: false
  // Nothing is baked until the item is complete and has settled.
  property bool completed: false
  // Keyframes are baked a band per frame; with gradualBake off, each lands in
  // a single frame instead. A host that drives elapsed itself sets
  // externalClock, and its frames then carry the bakes along.
  property bool gradualBake: true
  property bool externalClock: false
  // Width of the gold wire, in shorter-side units; never under 2.6 px.
  property real wireWidth: 0.002
  // Finest detail, in screen pixels. The wire's glints are kept wherever its
  // direction holds over at least this width; lace finer than that is lit
  // as satin, a sheen of the same brightness, so it shimmers instead of
  // crawling as the lights turn and the view drifts. 1 keeps every glint.
  property real detail: 2
  // Set if the satin filter cannot run here; the wire then glints as at 1.
  property bool satinFailed: false
  readonly property bool shaderFailed: slot0.failed || slot1.failed || surface.status === ShaderEffect.Error
  // A ShaderEffect whose shader came from Qt's cache (the second screen) can
  // stay "Uncompiled" while rendering fine, so readiness is judged by the
  // first completed bake instead.
  readonly property bool ready: baked && !shaderFailed
  readonly property bool animationRunning: frameClock.running
  readonly property bool ticking: frameClock.running || externalClock
  readonly property bool diving: zoom > 0
  readonly property real cacheScale: Math.min(1, maxDimension / Math.max(1, width, height))
  // The keyframe is drawn other than 1:1 on the screen.
  readonly property bool scaled: diving || cacheScale < 1
  readonly property int bakeWidth: Math.max(1, Math.round(width * cacheScale))
  readonly property int bakeHeight: Math.max(1, Math.round(height * cacheScale))

  // Engraving constants, in shorter-side units unless noted. A ramp is the
  // distance code of the field: log2(distance / shorter side) / 16 + 1.
  readonly property real shorter: Math.max(1, Math.min(bakeWidth, bakeHeight))
  readonly property real spacing: 0.004 / Math.max(0.2, density)
  function rampAt(px) { return Math.log2(px / shorter) / 16 + 1 }
  readonly property real wireEdge: 0.5 * Math.max(2.6, wireWidth * shorter)
  readonly property real metalLevel: rampAt(wireEdge)
  // The wire's edge is antialiased over 1.2 px.
  readonly property real metalEdge: 1.2 / (wireEdge * 16 * Math.LN2)
  // The tide and colour flow fade in between 5 and 15 px from the set.
  readonly property real tideNear: rampAt(5)
  readonly property real tideFar: rampAt(15)
  // The angle channel holds the wire's direction out to 1.5 px past its
  // edge, and texels below metalCut are drawn as wire (see fractal.frag).
  readonly property real fibreLevel: rampAt(wireEdge + 1.5)
  readonly property real metalCut: metalLevel + 0.5 * metalEdge
  // The wire rises out of the plate with slope bevel, so its baked normal
  // has length rim.
  readonly property real bevel: 0.5
  readonly property real rim: bevel / Math.sqrt(1 + bevel * bevel)

  // Satin (satin.frag). The wire's direction is averaged over a Gaussian
  // footprint as wide as the finest detail: its deviation is 0.375 of the
  // detail, less what the bake's supersampling and the surface's filtering
  // already blur (0.42 texel), in texels of the keyframe.
  function satinKernel(px) {
    const total = 0.375 * px * cacheScale, sigma = Math.sqrt(Math.max(0, total * total - 0.42 * 0.42))
    if (px <= 1 || sigma < 0.2) return { radius: 0, sigma: 0, taps: Qt.vector4d(0, 0, 0, 0) }
    const tap = d => Math.exp(-d * d / (2 * sigma * sigma))
    return { radius: Math.max(1, Math.min(4, Math.round(2 * sigma))), sigma: sigma,
             taps: Qt.vector4d(tap(1), tap(2), tap(3), tap(4)) }
  }
  // Mean of each glint q^s over every direction the wire can run, for a
  // light at this elevation: q = 1 - F (1 + cos t), F = (1 - sin elevation) / 4.
  // Returned as (E16 / E4, E16, E64 / E16, E128 / E64).
  function lobeMeans(elevation) {
    const F = (1 - Math.sin(elevation)) / 4, E = {4: 0, 16: 0, 64: 0, 128: 0}, n = 720
    for (let i = 0; i < n; ++i) {
      const q = 1 - F * (1 + Math.cos(2 * Math.PI * (i + 0.5) / n))
      const q4 = q * q * q * q, q16 = q4 * q4 * q4 * q4, q64 = q16 * q16 * q16 * q16
      E[4] += q4 / n; E[16] += q16 / n; E[64] += q64 / n; E[128] += q64 * q64 / n
    }
    return Qt.vector4d(E[16] / E[4], E[16], E[64] / E[16], E[128] / E[64])
  }
  readonly property vector4d keyMeans: lobeMeans(keyElevation)
  readonly property vector4d fillMeans: lobeMeans(fillElevation)
  // Flattened all the way, each glint is its mean, and the wire a flat
  // colour. The glitter it replaces is seen otherwise: the display clips its
  // peaks and the eye sums it as light, not as gamma-encoded values. So the
  // flat colour is shifted to the wire's colour lit from every direction,
  // clipped, and averaged as linear light, and the surface applies the shift
  // as far as each glint has flattened. How much is clipped depends on the
  // scale e the wire is drawn at (its rounding, and the vignette), so the
  // shift is fitted as a cubic in e over 0.3..1, from its value at four
  // points; its coefficients, lowest first. The lights' spacing is fixed,
  // so all this holds as they turn.
  //
  // A magnified field adds one more thing: where the filtered normals of a
  // filament's two sides cancel, the glitter there has lost its direction
  // and hardly glints, while satin, whose directions agree, glints on. So
  // where they cancel the sheen is dulled towards a wire lit from no
  // direction, by the share satinDull (fitted to renders of dense lace; it
  // falls as the footprint widens and covers more than those filaments).
  function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function encoded(c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055 }
  readonly property real satinDull: Math.max(0.1, Math.min(0.21, 0.19 - 0.067 * (satinTaps.sigma - 0.62)))
  readonly property var satinShift: {
    const s = surface, ts = s.thirdStrength, bright = s.brightField > 0.5
    const deep = s.wireDeep, wk = s.wireKey, g = s.gold, hot = s.wireHot, wt = s.wireThird
    const colours = [[deep.x, wk.x, g.x, hot.x, wt.x], [deep.y, wk.y, g.y, hot.y, wt.y], [deep.z, wk.z, g.z, hot.z, wt.z]]
    // The surface's wire (body 1) from its glints.
    const wire = (k16, k64, k128, f16, f64, t16, t64) => colours.map(([d, k, m, h, t]) => bright
      ? m * (0.4 + 0.7 * (0.6 * k16 + 0.4 * f16)) + h * (0.6 * k64 + 0.35 * f64)
      : d * 0.3 + k * (0.3 * k16 + 1.2 * k64) + m * (0.18 * f16 + 0.8 * f64) + h * (0.9 * k128)
        + t * ((0.2 * t16 + 0.8 * t64) * ts))
    const Fk = (1 - Math.sin(keyElevation)) / 4, Ff = (1 - Math.sin(fillElevation)) / 4
    const n = 720, lit = []
    for (let i = 0; i < n; ++i) {
      // Twice the wire's angle, from the key light's.
      const a = 2 * Math.PI * (i + 0.5) / n
      const qk = 1 - Fk * (1 - Math.cos(a))
      const qf = 1 - Ff * (1 - Math.cos(a - 2 * lightSpread))
      const qt = 1 - Ff * (1 - Math.cos(a - 4 * lightSpread))
      const k16 = Math.pow(qk, 16), k64 = Math.pow(k16, 4)
      const f16 = Math.pow(qf, 16), t16 = Math.pow(qt, 16)
      lit.push(wire(k16, k64, k64 * k64, f16, Math.pow(f16, 4), t16, Math.pow(t16, 4)))
    }
    const K = keyMeans, F = fillMeans
    const flat = wire(K.y, K.y * K.z, K.y * K.z * K.w, F.y, F.y * F.z, F.y, F.y * F.z)
    // A wire whose direction is lost catches no light at a slant.
    const qk = 1 - Fk, qf = 1 - Ff
    const dull = wire(Math.pow(qk, 16), Math.pow(qk, 64), Math.pow(qk, 128),
                      Math.pow(qf, 16), Math.pow(qf, 64), Math.pow(qf, 16), Math.pow(qf, 64))
    const seen = v => linear(Math.min(1, Math.max(0, v)))
    const knots = [0.3, 0.3 + 0.7 / 3, 0.3 + 1.4 / 3, 1]
    // The cubic through the knots (Newton's divided differences, expanded to
    // powers of e).
    const cubic = y => {
      const d = y.slice()
      for (let j = 1; j < 4; ++j)
        for (let i = 3; i >= j; --i) d[i] = (d[i] - d[i - 1]) / (knots[i] - knots[i - j])
      let poly = [d[3]]
      for (let j = 2; j >= 0; --j) {
        const next = [0].concat(poly)
        for (let i = 0; i < poly.length; ++i) next[i] -= knots[j] * poly[i]
        next[0] += d[j]
        poly = next
      }
      return poly
    }
    const shifts = [0, 1, 2].map(c => {
      const glitter = knots.map(e => {
        let sum = 0
        for (let i = 0; i < n; ++i) sum += seen(e * lit[i][c])
        return sum / n
      })
      return [cubic(knots.map((e, j) => encoded(glitter[j]) / e - flat[c])),
              cubic(knots.map((e, j) => (encoded((1 - satinDull) * glitter[j] + satinDull * seen(e * dull[c]))
                                         - encoded(glitter[j])) / e))]
    })
    const vectors = p => [0, 1, 2, 3].map(i => Qt.vector3d(shifts[0][p][i], shifts[1][p][i], shifts[2][p][i]))
    return vectors(0).concat(vectors(1))
  }
  readonly property var satinTaps: satinKernel(detail)
  readonly property bool satinOn: !satinFailed && satinTaps.radius > 0

  // Lights: a warm key and a cool fill orbit together, a quarter turn apart
  // (a third light joins them in iridescent mode or when vivid), so
  // highlights sweep slowly across the cuts. A faint tide runs down the
  // equipotentials.
  readonly property real lightAzimuth: (-40 + orbitTime * 4) * Math.PI / 180
  readonly property real lightSpread: (colorMode === 1 ? 120 : 90) * Math.PI / 180
  readonly property real keyElevation: 45 * Math.PI / 180
  readonly property real fillElevation: 50 * Math.PI / 180
  readonly property vector3d keyDirection: direction(lightAzimuth, keyElevation)
  readonly property vector3d fillDirection: direction(lightAzimuth + lightSpread, fillElevation)
  readonly property vector3d thirdDirection: direction(lightAzimuth + 2 * lightSpread, fillElevation)

  function direction(azimuth, elevation) {
    return Qt.vector3d(Math.cos(azimuth) * Math.cos(elevation), Math.sin(azimuth) * Math.cos(elevation), Math.sin(elevation))
  }
  // A light seen along a fibre: the wire is lit as a bundle of fibres
  // (Kajiya-Kay), which mirror a light where they cross its half vector h at
  // right angles. For a fibre across angle a, (t.h)^2 is the dot product of
  // this with (1, cos 2a, sin 2a).
  function fibre(l) {
    const hz = l.z + 1
    const n = Math.sqrt(l.x * l.x + l.y * l.y + hz * hz)
    const x = l.x / n, y = l.y / n
    return Qt.vector3d((x * x + y * y) / 2, (y * y - x * x) / 2, -x * y)
  }
  function rgb(c, s) { return Qt.vector3d(c.r * s, c.g * s, c.b * s) }
  // Broad reflection lobes: the colour deepened towards its own square.
  function sheen(c, s) {
    return Qt.vector3d((0.7 * c.r * c.r + 0.3 * c.r) * s, (0.7 * c.g * c.g + 0.3 * c.g) * s, (0.7 * c.b * c.b + 0.3 * c.b) * s)
  }
  function product(a, b) { return Qt.vector3d(a.r * b.r, a.g * b.g, a.b * b.b) }
  function blend(a, b, t, s) {
    return Qt.vector3d((a.r + (b.r - a.r) * t) * s, (a.g + (b.g - a.g) * t) * s, (a.b + (b.b - a.b) * t) * s)
  }
  function smoothstep(e0, e1, x) {
    const t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
  }

  // Colour, worked in OKLab so that changing chroma keeps lightness and hue.
  function oklab(c) {
    const f = x => x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
    const r = f(c.r), g = f(c.g), b = f(c.b)
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
  }
  function linearFromLab(L, a, b) {
    const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
    const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
    const s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
  }
  function inGamut(v) { return v.every(x => x >= -1e-4 && x <= 1 + 1e-4) }
  // Back to sRGB; a colour pushed out of gamut loses chroma, never hue.
  function fromLab(L, a, b) {
    let v = linearFromLab(L, a, b)
    if (!inGamut(v)) {
      let lo = 0, hi = 1
      for (let i = 0; i < 16; ++i) {
        const mid = (lo + hi) / 2
        if (inGamut(linearFromLab(L, a * mid, b * mid))) lo = mid
        else hi = mid
      }
      v = linearFromLab(L, a * lo, b * lo)
    }
    const f = x => {
      const c = Math.max(0, Math.min(1, x))
      return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055
    }
    return Qt.rgba(f(v[0]), f(v[1]), f(v[2]), 1)
  }
  function hueOf(c) {
    const l = oklab(c)
    return { hue: Math.atan2(l[2], l[1]), chroma: Math.hypot(l[1], l[2]) }
  }

  readonly property real vivid: Math.max(0.1, Math.min(1.5, intensity))
  // How far past 1 the vibrancy is: the third light and the extra hues.
  readonly property real richness: smoothstep(1.0, 1.4, vivid)
  readonly property real thirdStrength: colorMode === 1 ? 1 : richness
  readonly property color fillSource: colorMode >= 2 ? foregroundColor : secondaryColor
  readonly property color chosenMetal: colorMode === 2 ? accentColor : colorMode === 3 ? foregroundColor : goldColor
  // Some palettes' metal is too deep to catch the light on a dark field, or
  // too pale to show on a light one; bring its value into range, keeping hue.
  readonly property color metalBase: {
    const c = chosenMetal
    const s = lightTheme
      ? Math.min(1, 0.7 / Math.max(0.001, 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b))
      : Math.max(1, 0.7 / Math.max(0.1, c.r, c.g, c.b))
    return s === 1 ? c : Qt.rgba(Math.min(1, c.r * s), Math.min(1, c.g * s), Math.min(1, c.b * s), 1)
  }
  readonly property var metalHue: {
    const l = oklab(metalBase), c = Math.hypot(l[1], l[2])
    return c > 1e-4 ? [l[1] / c, l[2] / c] : [0, 0]
  }
  // The metal keeps its hue: muted, it loses up to 40% of its chroma.
  readonly property color metalColor: {
    if (Math.abs(vivid - 1) < 1e-6) return metalBase
    const l = oklab(metalBase)
    const k = vivid < 1 ? 0.6 + 0.4 * (vivid - 0.1) / 0.9 : 1 + 0.6 * (vivid - 1)
    return fromLab(l[0], l[1] * k, l[2] * k)
  }
  // Every other colour, muted, fades to 15% of its chroma in the metal's
  // hue, so a muted piece is a few quiet colours around the metal; vivid,
  // it gains up to 30% more chroma.
  function vibrant(c) {
    if (Math.abs(vivid - 1) < 1e-6) return c
    const l = oklab(c)
    let a = l[1], b = l[2]
    if (vivid < 1) {
      const t = (vivid - 0.1) / 0.9, target = 0.15 * Math.hypot(a, b)
      a = target * metalHue[0] + (a - target * metalHue[0]) * t
      b = target * metalHue[1] + (b - target * metalHue[1]) * t
    } else {
      a *= 1 + 0.6 * (vivid - 1)
      b *= 1 + 0.6 * (vivid - 1)
    }
    return fromLab(l[0], a, b)
  }
  readonly property color keyColor: vibrant(accentColor)
  readonly property color fillColor: vibrant(fillSource)
  readonly property color thirdColor: vibrant(tertiaryColor)
  readonly property color secondColor: vibrant(secondaryColor)
  readonly property color pearlColor: vibrant(foregroundColor)

  // Colour cycling: a loop through the palette in the order steel takes on
  // heat tint (straw, bronze, purple, blue), flowing slowly along the bands.
  // Vivid, two more of the theme's hues join the loop.
  function flowColor(c) {
    if (lightTheme) return Qt.vector3d(c.r, c.g, c.b)
    const l = Math.max(0.2, 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
    return Qt.vector3d(c.r / l, c.g / l, c.b / l)
  }
  readonly property var extraPair: {
    const used = [metalColor, keyColor, thirdColor, secondColor].map(hueOf).filter(h => h.chroma > 0.04).map(h => h.hue)
    const candidates = []
    for (const value of (extraColors || [])) {
      const c = Qt.darker(value, 1.0)
      if (!c) continue
      const v = vibrant(c), h = hueOf(v)
      if (h.chroma > 0.04) candidates.push({ color: v, hue: h.hue })
    }
    const picked = []
    while (picked.length < 2) {
      let best = null, farthest = -1
      for (const candidate of candidates) {
        if (picked.indexOf(candidate) >= 0) continue
        let nearest = Math.PI
        for (const u of used) nearest = Math.min(nearest, Math.abs(Math.atan2(Math.sin(candidate.hue - u), Math.cos(candidate.hue - u))))
        if (nearest > farthest) { farthest = nearest; best = candidate }
      }
      if (!best) break
      picked.push(best)
      used.push(best.hue)
    }
    return [picked.length > 0 ? picked[0].color : thirdColor, picked.length > 1 ? picked[1].color : secondColor]
  }
  readonly property var flowStops: {
    const base = [metalColor, keyColor, thirdColor, secondColor].map(flowColor)
    const rich = [metalColor, keyColor, thirdColor, extraPair[0], secondColor, extraPair[1]].map(flowColor)
    const stops = []
    for (let i = 0; i < 6; ++i) {
      const x = i * 4 / 6, j = Math.floor(x), f = x - j
      const plain = base[j].times(1 - f).plus(base[(j + 1) % 4].times(f))
      stops.push(plain.times(1 - richness).plus(rich[i].times(richness)))
    }
    return stops
  }

  // Keyframes. Step k of a dive is the view zoomed in by stepScale^k about the
  // focus. Each of the two slots is asked to hold one step (want) and reports
  // the step its texture holds once the bake has landed (have).
  readonly property real noKey: -1000000
  readonly property int steps: Math.max(1, loopSteps)
  readonly property real stepScale: Math.pow(Math.max(1.05, loopScale), 1 / steps)
  // Natural-log zoom per second of dive time at zoom 1: a 2.34x loop in ~5 min.
  readonly property real zoomRate: 0.003
  readonly property real level: diving ? zoomTime * zoomRate / Math.log(stepScale) : 0
  readonly property int levelStep: Math.floor(level)
  readonly property real levelFraction: level - levelStep
  // A dive scales each keyframe about the focus; a still view is mapped from
  // the middle of the screen. Kept in double precision: the reference offset
  // below is their small difference from the dive point.
  readonly property real bakeCenterX: diving ? centerX + focusX * span : centerX
  readonly property real bakeCenterY: diving ? centerY + focusY * span : centerY
  readonly property vector2d bakeAnchor: diving ? Qt.vector2d(focusX, focusY) : Qt.vector2d(0, 0)
  readonly property vector2d refOffset: Qt.vector2d(bakeCenterX - referenceX, bakeCenterY - referenceY)

  readonly property int entrySteps: Math.max(0, loopEntry) * steps
  function loopOf(k) { return k < entrySteps + steps ? 0 : Math.floor((k - entrySteps) / steps) }
  function stepIn(k) { return k - loopOf(k) * steps }
  function keySpan(k) { return k === noKey ? span : span / Math.pow(stepScale, descent ? k : stepIn(k)) }
  function keyAngle(k) { return k === noKey ? 0 : loopTurn * stepIn(k) / steps }
  function keyTurn(k) {
    const a = keyAngle(k)
    return Qt.vector2d(Math.cos(a), Math.sin(a))
  }
  function keyPhase(k) {
    const v = k === noKey ? 0 : loopOf(k) * loopPhase
    return v - Math.floor(v)
  }
  // Screen to keyframe k about the focus, as one complex factor.
  function viewOf(k) {
    if (k === noKey) return [1, 0]
    const m = Math.pow(stepScale, k - level)
    const a = loopTurn * (level - k) / steps
    return [m * Math.cos(a), m * Math.sin(a)]
  }
  function view(k) {
    const v = viewOf(k)
    return Qt.vector2d(v[0], v[1])
  }
  // Step k ends where the loop starts again.
  function wraps(k) {
    const n = k + 1 - entrySteps
    return n >= steps && n % steps === 0
  }
  // Across a wrap that is not self-similar the two keyframes hold different
  // pictures, which are cross-dissolved over half a step.
  readonly property bool dissolving: diving && dissolve && wraps(levelStep)
  // The keyframe just above the current zoom is drawn magnified (A) and the
  // one just below it minified (B). If neither is baked yet (the view
  // jumped), the nearest bake holds the screen until they are.
  readonly property var roles: {
    const h0 = slot0.have, h1 = slot1.have
    const k0 = levelStep, k1 = levelStep + 1
    const a = h0 === k0 ? 0 : h1 === k0 ? 1 : -1
    const b = h0 === k1 ? 0 : h1 === k1 ? 1 : -1
    if (a >= 0) return [a, b]
    if (b >= 0) return [b, -1]
    if (h1 === noKey) return [0, -1]
    if (h0 === noKey) return [1, -1]
    return [Math.abs(h0 - level) <= Math.abs(h1 - level) ? 0 : 1, -1]
  }
  readonly property int slotA: roles[0]
  readonly property int slotB: roles[1]
  readonly property real keyA: slotA === 1 ? slot1.have : slot0.have
  readonly property real keyB: slotB === 1 ? slot1.have : slotB === 0 ? slot0.have : noKey
  // Keyframe B fades in over the end of each step only (seven seconds at
  // zoom 1): on a software rasteriser a second texture costs almost as much
  // as the lighting itself. A dissolve takes the last half of its step.
  readonly property real blendWindow: dissolving ? 0.5 : 0.15
  readonly property real blendB: {
    if (slotB < 0) return 0
    const t = Math.max(0, (levelFraction - 1 + blendWindow) / blendWindow)
    return t * t * (3 - 2 * t)
  }
  // Keyframes are baked a little larger than the screen so that B, shown
  // minified during the fade, still covers it all. The margin is an even
  // number of texels so that a keyframe at 1:1 lands exactly on the pixels.
  readonly property vector2d margin: {
    if (!diving) return Qt.vector2d(1, 1)
    const m = Math.pow(stepScale, dissolve ? 0.5 : 0.15)
    const hx = 0.5 * bakeWidth / shorter, hy = 0.5 * bakeHeight / shorter
    const t = Math.abs(loopTurn) / steps
    return Qt.vector2d(m + Math.abs(focusX) / hx * (m - 1) + t * (hy + Math.abs(focusY)) / hx,
                       m + Math.abs(focusY) / hy * (m - 1) + t * (hx + Math.abs(focusX)) / hy)
  }
  readonly property int keyWidth: bakeWidth + 2 * Math.ceil(bakeWidth * (margin.x - 1) / 2 + (diving ? 2 : 0))
  readonly property int keyHeight: bakeHeight + 2 * Math.ceil(bakeHeight * (margin.y - 1) / 2 + (diving ? 2 : 0))

  // The screen in shorter-side units, and a keyframe's extent in them.
  readonly property vector2d aspect: Qt.vector2d(width / Math.max(1, Math.min(width, height)), height / Math.max(1, Math.min(width, height)))
  readonly property vector2d invExtent: Qt.vector2d(bakeWidth / (keyWidth * aspect.x), bakeHeight / (keyHeight * aspect.y))
  // Where keyframe k lies in the plane, were it baked now: its texel at q
  // (shorter-side units from the keyframe's middle) shows the point
  // c + (q - a) t, with t, the turn times the span, one complex factor.
  function geometry(k) {
    const a = keyAngle(k), s = keySpan(k)
    return {cx: bakeCenterX, cy: bakeCenterY, ax: diving ? focusX : 0, ay: diving ? focusY : 0,
            tx: Math.cos(a) * s, ty: Math.sin(a) * s,
            keyW: keyWidth, keyH: keyHeight, ix: invExtent.x, iy: invExtent.y}
  }
  function sameGeometry(a, b) {
    return a.cx === b.cx && a.cy === b.cy && a.ax === b.ax && a.ay === b.ay && a.tx === b.tx && a.ty === b.ty
      && a.keyW === b.keyW && a.keyH === b.keyH && a.ix === b.ix && a.iy === b.iy
  }
  // How the keyframe slot i holds meets the screen now. Baked for other
  // settings, it is stretched into place until its successor lands, so a
  // change shows at once: the screen shows z + (s - focus) w, s in
  // shorter-side units from its middle, so the keyframe is read at
  // q = a + (z - c) / t + (s - focus) w / t. One that would be blown up
  // past recognition, or has moved off the screen, is held as it was.
  function placement(i) {
    const slot = i === 1 ? slot1 : i === 0 ? slot0 : null
    const k = slot ? slot.have : noKey
    const S = slot ? slot.shown : null
    const fit = {origin: Qt.vector2d(focusX, focusY), view: view(k), invExtent: invExtent,
                 texels: Qt.vector2d(keyWidth, keyHeight), exact: true, covers: true, hold: false}
    if (!S || k === noKey) return fit
    const g = geometry(k)
    if (sameGeometry(S, g)) return fit
    const v = viewOf(k)
    const wx = v[0] * g.tx - v[1] * g.ty, wy = v[0] * g.ty + v[1] * g.tx
    const dx = centerX + focusX * span - S.cx, dy = centerY + focusY * span - S.cy
    const n = S.tx * S.tx + S.ty * S.ty
    let ox = S.ax + (dx * S.tx + dy * S.ty) / n, oy = S.ay + (dy * S.tx - dx * S.ty) / n
    let vx = (wx * S.tx + wy * S.ty) / n, vy = (wy * S.tx - wx * S.ty) / n
    const inside = (px, py) => Math.abs((ox + vx * px - vy * py) * S.ix) <= 0.501
                            && Math.abs((oy + vx * py + vy * px) * S.iy) <= 0.501
    let seen = 0
    for (let a = 0; a < 6; ++a)
      for (let b = 0; b < 6; ++b)
        if (inside(((a + 0.5) / 6 - 0.5) * aspect.x - focusX, ((b + 0.5) / 6 - 0.5) * aspect.y - focusY)) ++seen
    const hold = seen < 2 || Math.hypot(vx, vy) < 0.125
    if (hold) {
      ox = focusX
      oy = focusY
      vx = v[0]
      vy = v[1]
    }
    let covers = true
    for (const x of [-0.5, 0.5])
      for (const y of [-0.5, 0.5])
        if (!inside(x * aspect.x - focusX, y * aspect.y - focusY)) covers = false
    return {origin: Qt.vector2d(ox, oy), view: Qt.vector2d(vx, vy), invExtent: Qt.vector2d(S.ix, S.iy),
            texels: Qt.vector2d(S.keyW, S.keyH), exact: false, covers: covers, hold: hold}
  }
  readonly property var placeA: placement(slotA)
  readonly property var placeB: placement(slotB)
  // Keyframe B only joins in where it lines up with A.
  readonly property bool showB: slotB >= 0 && blendB > 0 && placeA.covers
    && (placeB.exact || (placeB.covers && !placeB.hold && !placeA.hold))
  readonly property real shownBlend: showB ? blendB : 0
  function exactIn(i) { return slotA === i ? placeA.exact : slotB === i ? placeB.exact : true }

  // Bakes. Every change that alters one moves version on, and a slot whose
  // texture was baked at an older version is baked again; while changes
  // keep coming (a slider being dragged), a slot with something to show
  // waits until they have been quiet for settleDelay ms. A bake is spread
  // over frames, a band of rows at a time, so no frame ever waits on more
  // than one band.
  property int version: 0
  property double changedAt: 0
  property int settleDelay: 0
  // Draft bakes take one sample per texel instead of four, for a view that
  // is being dragged about. New bakes start at most every bakeInterval ms.
  property bool draft: false
  property int bakeInterval: 0
  property double lastStart: 0
  // Rows are baked in bands of about this many texels.
  property int bandTexels: 160000
  property int bandMinRows: 16
  property int bandLimit: 64
  function refresh() {
    version += 1
    changedAt = Date.now()
    poke()
  }
  function poke() { Qt.callLater(pump) }
  // Everything a bake of keyframe k needs, as the settings are now.
  function snapshot(k) {
    const job = geometry(k)
    // The float64 descent bake costs ~1.45x the float32 one, so it is spread
    // over more, thinner bands to keep its per-frame slice at or below the
    // float32 bake's.
    const bandTexelsFor = descent ? 80000 : bandTexels
    const bandLimitFor = descent ? 96 : bandLimit
    const bands = Math.max(1, Math.min(bandLimitFor, Math.floor(keyHeight / bandMinRows),
                                       Math.ceil(keyWidth * keyHeight / bandTexelsFor)))
    job.bandRows = Math.ceil(keyHeight / bands)
    job.bands = Math.ceil(keyHeight / job.bandRows)
    job.key = k
    job.version = version
    job.resolution = Qt.vector2d(keyWidth, keyHeight)
    job.frame = Qt.vector2d(bakeWidth, bakeHeight)
    job.center = Qt.vector2d(bakeCenterX, bakeCenterY)
    // The focus and the Julia constant as high+low float32 splits, so the
    // float64 bake holds them to full precision (QML carries doubles; the
    // split is exact). Unused by the float32 bake.
    job.centerHigh = Qt.vector2d(Math.fround(bakeCenterX), Math.fround(bakeCenterY))
    job.centerLow = Qt.vector2d(bakeCenterX - Math.fround(bakeCenterX),
                                bakeCenterY - Math.fround(bakeCenterY))
    job.juliaConstantHigh = Qt.vector2d(Math.fround(juliaReal), Math.fround(juliaImag))
    job.juliaConstantLow = Qt.vector2d(juliaReal - Math.fround(juliaReal),
                                       juliaImag - Math.fround(juliaImag))
    job.anchor = Qt.vector2d(bakeAnchor.x, bakeAnchor.y)
    job.turn = keyTurn(k)
    job.juliaConstant = Qt.vector2d(juliaReal, juliaImag)
    job.refOffset = Qt.vector2d(refOffset.x, refOffset.y)
    job.span = keySpan(k)
    job.juliaMode = julia ? 1 : 0
    job.iterationLimit = iterations
    job.samples = draft ? 1 : 2
    job.wire = wireWidth
    job.fibreLevel = fibreLevel
    job.metalCut = metalCut
    job.spacing = spacing
    job.refMode = reference && !customEquation ? 1 : 0
    job.refStart = orbitStart
    job.refPre = orbitPre
    job.refPeriod = orbitPeriod
    job.shader = (descent && !customEquation) ? shaderUrl64 : shaderUrl
    return job
  }
  // Asks for the next piece of baking: a band, or the composition of a
  // finished keyframe. Only one is ever outstanding, and the keyframe the
  // screen needs most goes first.
  function pump() {
    if (!completed || !visible) return
    if (slot0.waiting) { slot0.watch(); return }
    if (slot1.waiting) { slot1.watch(); return }
    const quiet = Date.now() - changedAt >= settleDelay
    const primary = diving ? levelStep : 0
    const first = slot1.want === primary ? slot1 : slot0
    const second = first === slot0 ? slot1 : slot0
    if (!first.step(quiet)) second.step(quiet)
  }
  // With the frame clock stopped, or for a change of settings, bakes are
  // driven here; otherwise a dive bakes along with its frames.
  Timer {
    id: settle
    interval: 33
    repeat: true
    running: root.completed && root.visible
      && (slot0.behind || slot1.behind || (!root.ticking && (slot0.busy || slot1.busy)))
    onTriggered: root.pump()
  }

  function assignKeys() {
    const wanted = diving ? [levelStep, levelStep + 1] : [0]
    const current = [slot0.want, slot1.want]
    const missing = wanted.filter(k => current.indexOf(k) < 0)
    const free = [0, 1].filter(i => wanted.indexOf(current[i]) < 0)
    for (let i = 0; i < missing.length && i < free.length; ++i) {
      if (free[i] === 0) slot0.want = missing[i]
      else slot1.want = missing[i]
    }
  }
  // A new kind of view: the slot holding the nearest keyframe keeps it on
  // screen, stretched into place, until the new ones land.
  function restartKeys() {
    const first = diving ? levelStep : 0, second = diving ? levelStep + 1 : noKey
    if (Math.abs(slot1.have - first) < Math.abs(slot0.have - first)) {
      slot1.want = first
      slot0.want = second
    } else {
      slot0.want = first
      slot1.want = second
    }
    refresh()
  }
  // A new scene graph starts with empty textures: show nothing until they
  // are baked again.
  function reset() {
    slot0.forget()
    slot1.forget()
    baked = false
    refresh()
  }
  onLevelStepChanged: assignKeys()
  // A dive that is switched off starts again from the composition.
  onZoomChanged: if (zoom <= 0) zoomTime = 0
  onDivingChanged: restartKeys()
  onDissolveChanged: restartKeys()
  onLoopStepsChanged: restartKeys()
  onLoopScaleChanged: restartKeys()
  onLoopTurnChanged: restartKeys()
  onLoopEntryChanged: restartKeys()

  function tick() { pump() }
  onElapsedChanged: if (externalClock) tick()
  onVisibleChanged: if (visible) poke()

  onWidthChanged: refresh()
  onHeightChanged: refresh()
  onMaxDimensionChanged: refresh()
  onCenterXChanged: refresh()
  onCenterYChanged: refresh()
  onSpanChanged: refresh()
  onFocusXChanged: if (diving) refresh()
  onFocusYChanged: if (diving) refresh()
  onKeyWidthChanged: refresh()
  onKeyHeightChanged: refresh()
  onJuliaChanged: refresh()
  onJuliaRealChanged: refresh()
  onJuliaImagChanged: refresh()
  onIterationsChanged: refresh()
  onDensityChanged: refresh()
  onWireWidthChanged: refresh()
  // Satin is applied as the bands are composed, so a new finest detail
  // needs only a new composition of each keyframe on screen; one still
  // baking is composed with it when it lands.
  onSatinTapsChanged: { slot0.recompose(); slot1.recompose() }
  onSatinOnChanged: { slot0.recompose(); slot1.recompose() }
  onReferenceChanged: refresh()
  onReferenceXChanged: refresh()
  onReferenceYChanged: refresh()
  onOrbitStartChanged: refresh()
  onOrbitPreChanged: refresh()
  onOrbitPeriodChanged: refresh()
  onCustomEquationChanged: refresh()
  onShaderUrlChanged: refresh()
  // Leaving draft, whatever was baked roughly is baked again in full.
  onDraftChanged: if (!draft && (slot0.rough || slot1.rough)) refresh()
  Component.onCompleted: {
    slot0.want = diving ? levelStep : 0
    slot1.want = diving ? levelStep + 1 : noKey
    completed = true
    refresh()
  }
  Connections {
    target: root.Window.window
    ignoreUnknownSignals: true
    function onSceneGraphInitialized() { root.reset() }
  }

  // Frame rate: the lights and tide need about 10 frames a second; a dive
  // needs enough that the fastest pixel, in the corner farthest from the
  // focus, moves little more than half a pixel per frame. Rates divide 60 Hz
  // evenly.
  readonly property real divePixelSpeed: {
    if (!diving) return 0
    const s = Math.max(1, Math.min(width, height))
    const reach = Math.hypot(0.5 * width + Math.abs(focusX) * s, 0.5 * height + Math.abs(focusY) * s)
    return zoomRate * zoom * speed * reach * Math.hypot(1, loopTurn / Math.log(Math.max(1.05, loopScale)))
  }
  readonly property int frameRate: {
    const need = Math.max(motion > 0 || colorCycle > 0 ? 10 * speed : 0, divePixelSpeed / 0.6)
    const rates = [6, 10, 12, 15, 20, 30]
    let rate = 30
    for (const r of rates) {
      if (r >= need) { rate = r; break }
    }
    return Math.max(1, Math.min(fps, rate))
  }
  Timer {
    id: frameClock
    interval: Math.round(1000 / root.frameRate)
    running: root.playing && root.visible && root.ready
      && (root.motion > 0 || root.zoom > 0 || root.colorCycle > 0)
    repeat: true
    property double lastTick: Date.now()
    onRunningChanged: lastTick = Date.now()
    onTriggered: {
      const now = Date.now()
      const dt = root.speed * Math.min(0.25, Math.max(0, (now - lastTick) / 1000))
      lastTick = now
      root.elapsed += dt
      if (root.motion > 0) root.orbitTime += dt
      if (root.zoom > 0) root.zoomTime += dt * root.zoom
      root.tick()
    }
  }

  // One keyframe. A bake is rendered into bands of rows, each its own
  // texture, and the bands are then composed into the texture the surface
  // reads, which keeps the previous keyframe until the new one is complete.
  // Everything a bake reads is frozen when it starts (job), so settings can
  // change under it without tearing it.
  component KeySlot: Item {
    id: slot
    property Item fractal
    // Filter the texture: it is scaled on screen, or stretched into place.
    property bool filtered: false
    readonly property real none: -1000000
    // The step this slot should hold; and the step, settings version and
    // bake (with its place in the plane) its texture holds.
    property real want: none
    property real have: none
    property int haveVersion: -1
    property var shown: null
    // The bake under way, and how far it has got.
    property var job: ({key: none, version: -1, bands: 1, bandRows: 1, keyW: 1, keyH: 1,
      resolution: Qt.vector2d(1, 1), frame: Qt.vector2d(1, 1), center: Qt.vector2d(0, 0),
      anchor: Qt.vector2d(0, 0), turn: Qt.vector2d(1, 0), juliaConstant: Qt.vector2d(0, 0),
      refOffset: Qt.vector2d(0, 0), span: 1, juliaMode: 0, iterationLimit: 1, samples: 1,
      wire: 0.002, fibreLevel: 0, metalCut: 0, spacing: 0.004, refMode: 0, refStart: 0, refPre: 0,
      refPeriod: 1, centerHigh: Qt.vector2d(0, 0), centerLow: Qt.vector2d(0, 0),
      juliaConstantHigh: Qt.vector2d(0, 0), juliaConstantLow: Qt.vector2d(0, 0), shader: ""})
    property bool working: false
    property int nextBand: 0
    // The band asked for and not yet rendered, and whether the composition is.
    property int inflight: -1
    property bool composePending: false
    // The bands still hold the keyframe on screen, so it can be composed again.
    property bool bandsIntact: false
    // The band being baked on its own; the frame renders it only if it is drawn.
    property Item activeBand: null
    // Pumps spent waiting for a band or the composition.
    property int waited: 0
    property size texSize: Qt.size(1, 1)
    readonly property bool used: want !== none
    readonly property bool failed: bake.status === ShaderEffect.Error
    readonly property Item map: composed
    readonly property bool stale: want !== none && fractal !== null
      && (have !== want || haveVersion !== fractal.version)
    // Nothing to show, or the settings have changed since.
    readonly property bool behind: want !== none && fractal !== null
      && (have === none || haveVersion !== fractal.version)
    readonly property bool waiting: inflight >= 0 || composePending
    readonly property bool busy: stale || working || waiting
    // Its texture, or the bake under way, is a draft.
    readonly property bool rough: (shown !== null && shown.samples < 2) || (working && job.samples < 2)

    function drop() {
      working = false
      inflight = -1
      nextBand = 0
      waited = 0
      activeBand = null
    }
    function forget() {
      drop()
      composePending = false
      bandsIntact = false
      have = none
      haveVersion = -1
      shown = null
    }
    onWantChanged: {
      if (want === none) {
        forget()
        texSize = Qt.size(1, 1)
      }
      if (fractal) fractal.poke()
    }
    // Starts or carries on this slot's bake; returns whether it asked for work.
    function step(quiet) {
      if (want === none || !fractal.completed) return false
      // A bake overtaken by a change of settings is finished if it is well
      // along, and otherwise begun again.
      if (working && (job.key !== want || (job.version !== fractal.version && nextBand * 2 < job.bands))) drop()
      if (!working) {
        if (!stale || (have === want && !quiet)) return false
        const now = Date.now()
        if (now - fractal.lastStart < fractal.bakeInterval) return false
        fractal.lastStart = now
        job = fractal.snapshot(want)
        working = true
        nextBand = 0
        waited = 0
      }
      if (!fractal.gradualBake || job.bands === 1) {
        // All in one frame: the composition renders every band inside it.
        for (let i = nextBand; i < job.bands; ++i) {
          const piece = pieces.itemAt(i)
          if (piece) piece.band.scheduleUpdate()
        }
        compose()
        return true
      }
      if (nextBand < job.bands) return request(nextBand)
      compose()
      return true
    }
    function request(i) {
      const piece = pieces.itemAt(i)
      if (!piece) return false
      inflight = i
      activeBand = piece.band
      bandsIntact = false
      piece.band.scheduleUpdate()
      return true
    }
    function landed(i) {
      if (i !== inflight) return
      inflight = -1
      waited = 0
      nextBand = i + 1
    }
    // The finished bands become the texture on screen, in the same frame as
    // the placement that goes with them.
    function compose() {
      const done = job
      drop()
      texSize = Qt.size(done.keyW, done.keyH)
      shown = done
      have = done.key
      haveVersion = done.version
      bandsIntact = true
      composePending = true
      composed.scheduleUpdate()
    }
    // Composes the keyframe on screen again from its bands, as for a new
    // finest detail. A bake under way has moved the bands (or will) and is
    // composed with the new settings when it lands.
    function recompose() {
      if (working || !bandsIntact || have === none || composePending) return
      composePending = true
      composed.scheduleUpdate()
      if (fractal) fractal.poke()
    }
    // Should a request ever go unanswered, ask again rather than stall.
    function watch() {
      if (++waited % 30 !== 0) return
      if (inflight >= 0) {
        const piece = pieces.itemAt(inflight)
        if (piece) piece.band.scheduleUpdate()
        else inflight = -1
      }
      if (composePending) composed.scheduleUpdate()
    }

    ShaderEffect {
      id: bake
      width: slot.job.keyW
      height: slot.job.keyH
      blending: false
      property vector2d resolution: slot.job.resolution
      property vector2d frame: slot.job.frame
      property vector2d center: slot.job.center
      property vector2d anchor: slot.job.anchor
      property vector2d turn: slot.job.turn
      property vector2d juliaConstant: slot.job.juliaConstant
      property vector2d refOffset: slot.job.refOffset
      property real span: slot.job.span
      property real juliaMode: slot.job.juliaMode
      property real iterationLimit: slot.job.iterationLimit
      property real samples: slot.job.samples
      property real rays: 2
      property real relief: 0.45
      property real wire: slot.job.wire
      property real bevel: 0.5
      property real spacing: slot.job.spacing
      property real tidePeriod: 2
      property real refMode: slot.job.refMode
      property real refStart: slot.job.refStart
      property real refPre: slot.job.refPre
      property real refPeriod: slot.job.refPeriod
      property vector2d centerHigh: slot.job.centerHigh
      property vector2d centerLow: slot.job.centerLow
      property vector2d juliaConstantHigh: slot.job.juliaConstantHigh
      property vector2d juliaConstantLow: slot.job.juliaConstantLow
      fragmentShader: slot.job.shader !== "" ? slot.job.shader : slot.fractal ? slot.fractal.shaderUrl : ""
      onStatusChanged: {
        if (slot.fractal) slot.fractal.refresh()
        if (status === ShaderEffect.Error) console.error("Filigree field: " + log)
      }
    }
    Item {
      id: assembly
      width: slot.job.keyW
      height: slot.job.keyH
      Repeater {
        id: pieces
        model: slot.job.bands
        // Each band's filter reads the rows beside it from its neighbours.
        onItemAdded: (index, item) => {
          const before = itemAt(index - 1), after = itemAt(index + 1)
          if (before) { item.above = before.band; before.below = item.band }
          if (after) { item.below = after.band; after.above = item.band }
        }
        // Copies one band into place; blending off, so the angle channel is
        // copied rather than taken for opacity. With satin on, the band is
        // filtered on the way (satin.frag).
        delegate: ShaderEffect {
          id: piece
          required property int index
          readonly property int firstRow: index * slot.job.bandRows
          readonly property int rows: Math.max(1, Math.min(slot.job.bandRows, slot.job.keyH - firstRow))
          readonly property Item band: bandTexture
          readonly property bool satin: slot.fractal !== null && slot.fractal.satinOn
          y: firstRow
          width: slot.job.keyW
          height: rows
          blending: false
          property variant source: bandTexture
          property variant above: null
          property variant below: null
          property vector2d size: Qt.vector2d(slot.job.keyW, rows)
          property real aboveRows: index > 0 && above ? slot.job.bandRows : 0
          property real belowRows: index + 1 < slot.job.bands && below
            ? Math.max(1, Math.min(slot.job.bandRows, slot.job.keyH - firstRow - rows)) : 0
          property real radius: satin ? slot.fractal.satinTaps.radius : 0
          property vector4d taps: satin ? slot.fractal.satinTaps.taps : Qt.vector4d(0, 0, 0, 0)
          property real fibreLevel: slot.job.fibreLevel
          property real metalCut: slot.job.metalCut
          property real rim: slot.fractal !== null ? slot.fractal.rim : 1
          fragmentShader: satin ? Qt.resolvedUrl("satin.frag.qsb") : ""
          onStatusChanged: {
            if (status === ShaderEffect.Error && satin) {
              console.error("Filigree satin: " + log)
              slot.fractal.satinFailed = true
            }
          }
          ShaderEffectSource {
            id: bandTexture
            visible: false
            sourceItem: bake
            hideSource: true
            live: false
            smooth: false
            format: ShaderEffectSource.RGBA8
            sourceRect: Qt.rect(0, piece.firstRow, slot.job.keyW, piece.rows)
            textureSize: slot.used ? Qt.size(slot.job.keyW, piece.rows) : Qt.size(1, 1)
            onScheduledUpdateCompleted: slot.landed(piece.index)
          }
        }
      }
    }
    // A texture is only rendered when something in the frame draws it: the
    // band being baked, or the composition being made, is drawn here as a
    // single pixel under the surface.
    ShaderEffect {
      width: 1
      height: 1
      visible: slot.composePending || slot.activeBand !== null
      property variant source: slot.activeBand !== null ? slot.activeBand : composed
    }
    ShaderEffectSource {
      id: composed
      sourceItem: assembly
      hideSource: true
      visible: false
      live: false
      format: ShaderEffectSource.RGBA8
      // Nearest filtering at 1:1 is both exact and the cheapest read on a
      // software rasteriser; filter only when the texture is scaled on screen.
      smooth: slot.filtered
      textureSize: slot.texSize
      onScheduledUpdateCompleted: {
        slot.composePending = false
        slot.waited = 0
        if (slot.have !== slot.none) slot.fractal.baked = true
      }
    }
  }
  // Two slots while diving; otherwise one.
  KeySlot { id: slot0; fractal: root; filtered: root.scaled || !root.exactIn(0) }
  KeySlot { id: slot1; fractal: root; filtered: root.scaled || !root.exactIn(1) }

  ShaderEffect {
    id: surface
    anchors.fill: parent
    visible: root.baked
    blending: false
    property variant field: root.slotA === 1 ? slot1.map : slot0.map
    property variant fieldB: root.slotB === 1 ? slot1.map : root.slotB === 0 ? slot0.map : root.slotA === 1 ? slot0.map : slot1.map
    property vector3d keyDirection: root.keyDirection
    property vector3d fillDirection: root.fillDirection
    property vector3d thirdDirection: root.thirdDirection
    property vector3d keyFibre: root.fibre(root.keyDirection)
    property vector3d fillFibre: root.fibre(root.fillDirection)
    property vector3d thirdFibre: root.fibre(root.thirdDirection)
    property vector2d aspect: root.aspect
    property vector2d focal: Qt.vector2d(root.focusX, root.focusY)
    property vector2d originA: root.placeA.origin
    property vector2d originB: root.placeB.origin
    property vector2d viewA: root.placeA.view
    property vector2d viewB: root.placeB.view
    property vector2d invExtentA: root.placeA.invExtent
    property vector2d invExtentB: root.placeB.invExtent
    property vector2d texelsA: root.placeA.texels
    property vector2d texelsB: root.placeB.texels
    property real blendB: root.shownBlend
    property real phaseA: root.keyPhase(root.keyA)
    property real phaseB: root.keyPhase(root.keyB)
    property real flow: root.colorCycle
    property real flowPhase: (root.elapsed * 0.01) % 1
    property real flowScale: 1
    property vector3d flow0: root.flowStops[0]
    property vector3d flow1: root.flowStops[1].minus(root.flowStops[0])
    property vector3d flow2: root.flowStops[2].minus(root.flowStops[1])
    property vector3d flow3: root.flowStops[3].minus(root.flowStops[2])
    property vector3d flow4: root.flowStops[4].minus(root.flowStops[3])
    property vector3d flow5: root.flowStops[5].minus(root.flowStops[4])
    property vector3d flow6: root.flowStops[0].minus(root.flowStops[5])
    property real tide: (root.elapsed * 0.03) % 1
    property real tideStrength: 0.55 * root.motion
    property real metalLevel: root.metalLevel
    property real metalEdge: root.metalEdge
    property real satin: root.satinOn ? 1 : 0
    property real metalCut: root.metalCut
    property real invRim: 1 / root.rim
    property vector4d keyMeans: root.keyMeans
    property vector4d fillMeans: root.fillMeans
    // The third light stands at the fill's elevation.
    property vector4d thirdMeans: root.fillMeans
    property vector3d satinShift0: root.satinShift[0]
    property vector3d satinShift1: root.satinShift[1]
    property vector3d satinShift2: root.satinShift[2]
    property vector3d satinShift3: root.satinShift[3]
    property vector3d satinDull0: root.satinOn ? root.satinShift[4] : Qt.vector3d(0, 0, 0)
    property vector3d satinDull1: root.satinOn ? root.satinShift[5] : Qt.vector3d(0, 0, 0)
    property vector3d satinDull2: root.satinOn ? root.satinShift[6] : Qt.vector3d(0, 0, 0)
    property vector3d satinDull3: root.satinOn ? root.satinShift[7] : Qt.vector3d(0, 0, 0)
    property real tideNear: root.tideNear
    property real tideFar: root.tideFar
    property real dome: 0.12
    property real brightField: root.lightTheme ? 1 : 0
    property real thirdStrength: root.thirdStrength
    property real vignette: root.lightTheme ? 0.12 : 0.4
    property vector3d ground: root.rgb(root.backgroundColor, 1)
    property vector3d key: root.rgb(root.keyColor, 1)
    property vector3d fill: root.rgb(root.fillColor, 1)
    property vector3d third: root.rgb(root.thirdColor, 1)
    property vector3d enamel: root.rgb(root.thirdColor, 1)
    property vector3d gold: root.rgb(root.metalColor, 1)
    property vector3d pearl: root.rgb(root.pearlColor, 1)
    property vector3d keySheen: root.sheen(root.keyColor, 0.3)
    property vector3d fillSheen: root.sheen(root.fillColor, 0.25)
    property vector3d thirdSheen: root.sheen(root.thirdColor, 0.25)
    property vector3d wireDeep: root.product(root.metalColor, root.metalColor)
    property vector3d wireKey: root.product(root.metalColor, root.keyColor)
    property vector3d wireThird: root.product(root.metalColor, root.thirdColor)
    property vector3d wireHot: root.lightTheme ? root.blend(root.metalColor, Qt.rgba(1, 1, 1, 1), 0.6, 1)
                                               : root.blend(root.metalColor, root.pearlColor, 0.7, 1)
    // Dark field: mix(background * 0.55, enamel * 0.3, 0.45); light: mix(enamel, pearl, 0.25) * 0.8
    property vector3d glassBase: root.lightTheme ? root.blend(root.thirdColor, root.pearlColor, 0.25, 0.8)
      : Qt.vector3d(root.backgroundColor.r * 0.3025 + root.thirdColor.r * 0.135,
                    root.backgroundColor.g * 0.3025 + root.thirdColor.g * 0.135,
                    root.backgroundColor.b * 0.3025 + root.thirdColor.b * 0.135)
    // Plain at 1:1; a keyframe that does not cover the screen, stretched
    // into place, has bare plate drawn around it.
    fragmentShader: Qt.resolvedUrl(!root.scaled && root.placeA.exact ? "surface.frag.qsb"
      : !root.placeA.covers ? "surface-stretch.frag.qsb"
      : root.shownBlend <= 0 ? "surface-dive.frag.qsb"
      : root.dissolving ? "surface-dissolve.frag.qsb" : "surface-blend.frag.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) console.error("Filigree surface: " + log)
  }
}
