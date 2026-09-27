.pragma library

// The studio's map of the complex plane. A view is the wallpaper's own
// settings: a centre, a span (the plane height of each display's shorter
// side) and a focus (the dive target, in spans from the centre). The real
// axis runs right and the imaginary axis down, as on the desktop.

const centerLimit = 3
const spanMinimum = 0.002
const spanMaximum = 5
const focusLimit = 1

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// How much more of the plane than one span the preview's shorter side
// shows, so that every display's view fits inside a w x h preview.
function framing(displays, w, h) {
  if (!(w > 1 && h > 1)) return 1
  const list = displays && displays.length ? displays : [{width: 16, height: 9}]
  const short = Math.min(w, h)
  let k = 0
  for (let i = 0; i < list.length; ++i) {
    const d = list[i]
    const m = Math.max(1, Math.min(d.width, d.height))
    k = Math.max(k, d.width / m * short / w, d.height / m * short / h)
  }
  return k * 1.04
}

// Where display d's view sits in the preview, in pixels.
function frameOf(d, w, h, k) {
  const short = Math.min(w, h)
  const m = Math.max(1, Math.min(d.width, d.height))
  const fw = d.width / m * short / k, fh = d.height / m * short / k
  return {x: (w - fw) / 2, y: (h - fh) / 2, width: fw, height: fh}
}

// Plane units per preview pixel.
function unit(view, k, w, h) { return view.span * k / Math.max(1, Math.min(w, h)) }

function toPlane(view, k, w, h, px, py) {
  const u = unit(view, k, w, h)
  return {x: view.centerX + (px - w / 2) * u, y: view.centerY + (py - h / 2) * u}
}

function toPixel(view, k, w, h, x, y) {
  const u = unit(view, k, w, h)
  return {x: w / 2 + (x - view.centerX) / u, y: h / 2 + (y - view.centerY) / u}
}

// The view moved to a new centre and span. The dive target stays on its
// point of the plane while that is within reach of the new view.
function moved(target, cx, cy, span) {
  span = clamp(span, spanMinimum, spanMaximum)
  cx = clamp(cx, -centerLimit, centerLimit)
  cy = clamp(cy, -centerLimit, centerLimit)
  const fx = (target.x - cx) / span, fy = (target.y - cy) / span
  return {centerX: cx, centerY: cy, span: span,
    focusX: clamp(fx, -focusLimit, focusLimit), focusY: clamp(fy, -focusLimit, focusLimit),
    kept: Math.abs(fx) <= focusLimit && Math.abs(fy) <= focusLimit}
}

// The view shifted by (dx, dy) preview pixels.
function shifted(view, target, k, w, h, dx, dy) {
  const u = unit(view, k, w, h)
  return moved(target, view.centerX + dx * u, view.centerY + dy * u, view.span)
}

// Zoomed in by f (below 1 zooms out) about preview pixel (px, py), which
// stays on the same point of the plane.
function zoomedAt(view, target, k, w, h, px, py, f) {
  const span = clamp(view.span / f, spanMinimum, spanMaximum)
  const a = unit(view, k, w, h), b = span * k / Math.max(1, Math.min(w, h))
  return moved(target, view.centerX + (px - w / 2) * (a - b),
    view.centerY + (py - h / 2) * (a - b), span)
}

// The dive target for a point of the preview: the point of the plane (x, y)
// and the focus that reaches it, or as near as a focus can. A dive point
// within reach pixels is taken exactly, since only a dive into the point
// itself can go on forever.
function aimed(view, k, w, h, px, py, points, reach) {
  let p = toPlane(view, k, w, h, px, py)
  let best = reach, point = null
  for (let i = 0; i < points.length; ++i) {
    const q = toPixel(view, k, w, h, points[i].x, points[i].y)
    const d = Math.hypot(q.x - px, q.y - py)
    if (d <= best) { best = d; point = points[i] }
  }
  if (point) p = {x: point.x, y: point.y}
  const fx = (p.x - view.centerX) / view.span, fy = (p.y - view.centerY) / view.span
  return {x: p.x, y: p.y, focusX: clamp(fx, -focusLimit, focusLimit), focusY: clamp(fy, -focusLimit, focusLimit),
    point: point, kept: Math.abs(fx) <= focusLimit && Math.abs(fy) <= focusLimit}
}

// The dive points an equation can dive into forever.
function pointsFor(points, julia, juliaReal, juliaImag, custom) {
  if (custom) return []
  return points.filter(d => d.julia === julia
    && (!julia || (Math.abs(juliaReal - d.juliaReal) < 1e-9 && Math.abs(juliaImag - d.juliaImag) < 1e-9)))
}

// The loop a dive starts repeating at, for a view of the given span.
function entryFor(loop, span) {
  if (loop.mode !== "dive" || !(loop.depth > 0)) return 0
  return Math.max(0, Math.ceil(Math.log(span / loop.depth) / Math.log(loop.scale) - 0.01))
}
