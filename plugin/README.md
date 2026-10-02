# Filigree

A quiet, living fractal wallpaper for Omarchy, made like a guilloché watch
dial. Fine grooves are cut into a dark plate along the Mandelbrot set's external
rays, the boundary of the set rises out of it as rounded gold wire, and the
set's interior becomes pools of glassy enamel. Two lights in the theme's
colours circle the plate once every 90 seconds, so highlights sweep slowly
across every cut, while a faint tide of light runs down the equipotentials into
the lace. The view sinks slowly and endlessly into the fractal, and the
palette can flow along the grooves. The colours follow the
current Omarchy theme: its accent is the warm
key light, cyan the cool fill, yellow the metal, magenta the enamel. A metal
too deep (or, on a light theme, too pale) to read against the plate is brought
into range, keeping its hue. Light themes print the same engraving in ink on
paper instead. The artwork is generated mathematically by shaders; it contains
no downloaded images.

Filigree runs as the native `ric.background` shell plugin, cloned from
`omarchy.background`. It survives Omarchy updates and uses the existing shell
process. Each display gets a composition fitted to its aspect ratio, including
portrait screens.

Install from the repository root with
`omarchy plugin add https://github.com/keylimesoda/filigree`. The CLI is
installed at `~/.config/omarchy/plugins/ric.background/plugin/fractal`, not
automatically on `PATH`. The `omarchy-fractal` examples below assume you first
set an interactive shell alias:

```bash
alias omarchy-fractal="$HOME/.config/omarchy/plugins/ric.background/plugin/fractal"
```

## Switching it on

Filigree is not an entry in Omarchy's background picker: it replaces the
wallpaper renderer itself, so while it is on it is drawn instead of the theme
photo.

```bash
omarchy-fractal on    # same as: omarchy plugin enable ric.background
omarchy-fractal off   # same as: omarchy plugin enable omarchy.background
```

Choosing a photo in the background picker (middle click on the desktop,
`omarchy background`, or cycling backgrounds) switches back to the standard
renderer; `omarchy-fractal on` returns to Filigree. Changing the theme keeps
Filigree and recolours it.

## The studio panel

Filigree is both a wallpaper service and a studio panel. Open the panel with:

```bash
omarchy-fractal settings
# or, through the shell directly:
omarchy-shell shell summon ric.background '{}'
```

`omarchy-fractal settings` switches Filigree on first if the standard
wallpaper is in use; the direct shell call only opens the panel of an enabled
plugin.

### From the Omarchy menu

A plugin cannot add rows to the Omarchy menu itself. To get a Filigree entry,
add this line inside the outer braces of
`~/.config/omarchy/extensions/omarchy-menu.jsonc` (the menu reloads it on
save):

```jsonc
"style.filigree": {"icon":"󰜗","label":"Filigree","aliases":["filigree","fractal"],"description":"Fractal wallpaper studio","when":"[[ -x ~/.config/omarchy/plugins/ric.background/plugin/fractal ]]","action":"~/.config/omarchy/plugins/ric.background/plugin/fractal settings"}
```

The studio then opens from **Style → Filigree** in the Omarchy menu
(Super + Space), by typing “filigree” in that menu from anywhere, or with
`omarchy menu summon filigree`.

The studio opens as a floating window in the middle of the focused monitor:
1160 pixels wide where that fits, narrower on a small or portrait screen.

Beside a live preview, the panel has three pages:

- **Motion** — pause/resume, animation speed (0.1–8×), motion amplitude,
  zoom, colour cycle, frame-rate limit, and the idle-pause delay. It also reports, per display, whether
  the desktop animation is running or why it is paused.
- **Fractal** — choose a composition preset, edit the iteration equation,
  pick the parameter plane (Mandelbrot or Julia), set the Julia constant, the
  view center, field of view, and iteration detail.
- **Color** — the color mapping (theme spectrum, iridescent, duotone, or
  platinum), color intensity, the density of the engraved grooves, the weight
  of the gold wire, and the finest detail. The current theme palette is shown
  at the bottom.

Everything saves automatically. The preview follows at once; the desktop
follows as soon as you pause, or when you let go of a drag or a slider.
“Reset Filigree” restores the defaults and “Revert session” restores the
values from when the window opened.

Numbers typed into the Julia constant and Center fields are tried out when
you stop typing, kept on Enter or on leaving the field, and Escape puts back
the value from before you typed. A field's label turns red while it doesn't
hold a number in range.

### The preview is a map

The preview shows the composition as it plays on the desktop. Corner marks
frame each display's view, and the plane outside every display is dimmed. It
is also a map of the complex plane, so you can wander off to find your own
composition:

- **Drag** to move the view, and **scroll** to zoom about the pointer (1.25×
  a notch). Double-click zooms in 2× there; Shift + double-click zooms out.
- The corner buttons: **+** and **−** zoom 1.5× about the middle, **⌂**
  returns to the preset's framing, and **◎** aims the dive: click the point
  it should head for (Esc cancels). A right-click aims directly.
- From the keyboard, Tab to the preview (an accent frame shows it has focus).
  The arrow keys move the view by a tenth of the preview's shorter side (with
  Shift, a fiftieth), `+` and `−` zoom 1.25× (so do Page Up and Page Down),
  `0` or Home return to the framing, and `D` aims the dive at the middle.

While you explore, the preview's own dive pauses (“MAP · DIVE PAUSED”) so it
holds the framing you are editing, each display's name appears in its frame,
and a reticle marks where the dive is heading. Gold diamonds mark the points
where the dive can go on forever: the Filigree dendrite and the seahorse
valley's double spiral on the Mandelbrot plane, and the Julia lace's spiral
on its own plane. They show while the equation is the built-in `z*z+c`, and
aiming within 14 pixels of one snaps to it.

The chosen point stays put as you move the view, typing a centre or moving
the Field of view slider included. The dive's focus can only sit so far from
the middle of the screen (see `focusX` / `focusY` below); beyond that the dive
heads as near to the point as it can and a faint ring marks the point itself.
Move the view back toward it and the dive heads for it again.

## Presets

| Preset | Composition |
| --- | --- |
| `filigree` | The default: a three-armed dendrite of the Mandelbrot set near −0.101 + 0.956i, diving endlessly into it |
| `seahorse` | Spirals of the seahorse valley, diving endlessly into its double spiral |
| `julia` | A Julia lace (constant c = −0.8 + 0.156i), diving endlessly into the spiral where its arms meet |
| `mandelbrot` | The whole set, set in enamel: a grand tour down the seahorse valley into its endless double spiral |
| `trinity` | The cubic Multibrot, `z^3 + c` |

```bash
omarchy-fractal preset julia
```

Presets write their own composition (view, plane, equation); your motion,
speed, zoom, colour cycle, frame rate, intensity, and idle settings are kept.

## Zoom and colour cycling

The view dives by default; colour cycling is off. Both combine with the
orbiting lights (or replace them, with `motion` at `0`).

```bash
omarchy-fractal set zoom 1          # 0 holds the view; up to 3
omarchy-fractal set colorCycle 0.5  # 0 is off; 1 is the full palette
```

**Zoom.** Every preset but `trinity` is focused on a point where its fractal
is self-similar: a Misiurewicz point of the Mandelbrot set, whose critical
orbit lands on a repelling cycle, or for `julia` the repelling fixed point
where the lace's arms meet. Magnified by a fixed factor and turned slightly
about that point, the picture looks like itself again (2.34× and 1.3° for
`filigree`, 2.58× for the seahorse, 3.82× for the Julia lace), so the view can
sink into it forever. At `zoom 1` it sinks about 2.5× deeper every five
minutes. The dive starts from the composition, and once one loop matches the
next closely (24 minutes in for `filigree`, 42 for `seahorse`, 45 for
`julia`, over an hour for the `mandelbrot` tour) it repeats a seamless loop.
Each pixel is iterated as a small offset from the point's exactly known orbit
(perturbation), so the lace stays sharp at any depth. Other views and custom
equations sink 3× deeper and then cross-dissolve back to where they began.

**Colour cycling.** The grooves take on the theme palette in the order steel
takes on heat tint (metal, accent, magenta, cyan), and the colours drift
slowly in towards the lace, one full cycle every 100 seconds at speed 1. At
`0.5` it is a faint heat tint; at `1` a dark theme looks like anodised titanium
and a light theme like mother-of-pearl. At higher `intensity`, two more of the
theme's hues, the two least like the rest, join the loop.

## Custom equations

The studio (or the CLI) accepts a small, deliberately non-executable equation
language for the iteration `zₙ₊₁ = f(zₙ, c)`:

- values: `z` (the orbit), `c` (the parameter), `i`, `pi`
- operators: `+  −  *  /  ^` (integer powers 0–8) and parentheses
- functions: `sin`, `cos`, `exp`, `conj`, `abs` (modulus), `abs2` (per
  component), `re`, `im`, `complex(r, i)`

```bash
omarchy-fractal equation "z^3 + c"
omarchy-fractal equation "abs2(z)*abs2(z) + c"
```

Each accepted equation is compiled to its own shader and cached by hash
(`~/.local/state/omarchy/filigree-equations/`), so re-applying an equation is
instant and a failed compile never touches the running wallpaper.

## Controls

```bash
omarchy-fractal pause
omarchy-fractal resume
omarchy-fractal toggle
omarchy-fractal status
omarchy-fractal set motion 0.3
omarchy-fractal set speed 3
omarchy-fractal set zoom 1
omarchy-fractal set colorCycle 0.5
omarchy-fractal set intensity 0.7
omarchy-fractal set wire 1.4
omarchy-fractal set detail 3
omarchy-fractal set fps 10
omarchy-fractal capture "$HOME/Pictures/filigree.png"
```

Double-click the bare desktop with the left button to pause or resume. A right
double-click opens the theme picker; a middle click opens the background
picker. Choosing a regular background restores Omarchy's standard wallpaper
renderer. Changing the theme keeps Filigree and updates its palette.

Captures contain only the wallpaper from the largest display. To capture a
specific monitor, use `omarchy-shell fractal captureScreen DP-3 /absolute/path.png`. The helper waits
up to 15 seconds for the image and prints its path when saved. `status` reports
`capturePath` or `captureError` for the latest request. The output directory must
exist.

## Settings

Settings persist inline on the `ric.background` entry in
`~/.config/omarchy/shell.json`. Use `omarchy-fractal set KEY VALUE` or the
studio panel while Filigree is enabled. Omarchy removes that entry when the
standard wallpaper is switched back on, so Filigree also keeps a copy in
`~/.local/state/omarchy/filigree-settings.json` and restores it when it is
switched on again. To start from the defaults, use “Reset Filigree” in the
studio.

| Setting | Default | Range | Effect |
| --- | --- | --- | --- |
| `paused` | `false` | `true` / `false` | Freeze or resume motion |
| `motion` | `0.55` | `0`–`1` | Strength of the tide of light; `0` holds a still engraving |
| `speed` | `1.0` | `0.1`–`8` | Scales every motion (the lights orbit once per 90 s at `1`) |
| `zoom` | `1` | `0`–`3` | Dive speed (see Zoom above); `0` holds the view |
| `colorCycle` | `0` | `0`–`1` | Palette tint flowing along the grooves; `0` is off |
| `intensity` | `1.0` | `0.1`–`1.5` | Colour: low is a few quiet colours drawn towards the gold; high is saturated colour, a third light, and more of the theme's hues |
| `wire` | `1.0` | `0.5`–`2` | Weight of the gold wire |
| `detail` | `2` | `1`–`4` | Finest detail, in pixels: lace finer than this is lit as a satin sheen instead of glinting; `1` keeps every glint |
| `fps` | `30` | `1`–`30`, integer | Frame-rate cap; the wallpaper draws only as often as its motion needs (10 fps for the lights, 15 while diving at 4K) |
| `maxDimension` | `3840` | `960`–`3840`, integer | Maximum cached texture dimension |
| `idlePause` | `120` | `30`–`3600`, integer | Idle seconds before animation pauses |
| `preset` | `filigree` | preset name | Curated composition bundle |
| `equation` | `z*z+c` | ≤ 512 chars | Custom iteration equation |
| `julia` | `false` | `true` / `false` | Julia plane (constant c) instead of Mandelbrot |
| `juliaReal` | `-0.8` | `-2`–`2` | Julia constant, real part |
| `juliaImag` | `0.156` | `-2`–`2` | Julia constant, imaginary part |
| `centerX` / `centerY` | filigree view | `-3`–`3` | View center in the complex plane |
| `span` | `0.03` | `0.002`–`5` | Height of the shorter screen side in the plane (smaller = deeper zoom) |
| `focusX` / `focusY` | `0.12` / `-0.08` | `-1`–`1` | Where the dive heads, and the centre of the vignette and the plate's dome, in shorter-side units from the middle of the screen |
| `iterations` | `1500` | `80`–`5000`, integer | Iteration detail |
| `colorMode` | `0` | `0`–`3`, integer | Color mapping (0 theme spectrum, 1 iridescent, 2 duotone, 3 platinum) |
| `density` | `1.0` | `0.2`–`2.5` | Density of the engraved grooves |

## How it renders

The desktop may be drawn by a software rasteriser (llvmpipe), so Filigree
splits the work in two:

1. **Engrave, once per keyframe.** `fractal.frag` iterates the fractal with
   analytic derivatives, four rotated-grid samples per texel, and bakes the
   relief into one RGBA8 texel per screen pixel: the surface normal of the
   grooves and wire, the distance to the set, and one angle (the tide phase,
   or the wire's direction). Everything it encodes is band-limited: grooves
   finer than a pixel fade to their average instead of aliasing, and the wire
   is never narrower than 2.6 px, so edges stay smooth at 1:1 and magnified.
   It contains no colour, so theme changes, colour settings and the lights
   never engrave again.
2. **Light, every frame.** `surface.frag` reads that texel and lights it with
   plain arithmetic: mirror reflections of the key, fill and optional third
   light on the plate; the wire lit as a bundle of gold fibres (Kajiya–Kay),
   so it has a rounded, satin highlight that follows its direction; a
   slightly domed plate so reflections drift; the tide pulse; and a vignette.
   Colour products that are the same for every pixel are computed in QML,
   including the intensity mapping, which works in OKLab so that muted and
   vivid palettes keep their lightness.

**Finest detail.** In dense lace the engraving runs finer than a pixel, and
during the dive its one-pixel glints flip from frame to frame — a fine crawl
over the densest regions. `detail` (default `2`, range `1`–`4`, in screen
pixels) removes it: when a keyframe is composed, the wire's fibre directions
are averaged over a small footprint at every wire texel. Where the directions
agree, the wire keeps its rounded glint; where they disagree, its relief is
smoothed and it reads as a matte, hammered satin sheen instead of glitter.
The filtering happens once per keyframe, at composition, so the per-frame
lighting still costs exactly two texture reads; `1` turns it off entirely.
Changing it re-lights the keyframes already on screen, without re-engraving.
Measured at 4K on llvmpipe: the crawl in dense lace drops 57–80% per frame
during a dive (more at higher settings), the picture's brightness moves at
most ±2%, and a frame costs 6% more (seahorse) to 8% (trinity) CPU at
`detail 2`; `1` costs the same as before. A live change re-composes both
keyframes in one frame: 43–70 ms wall time (0.8–1.6 s of CPU) at 4K, more at
`3` and `4`.

While diving, the relief is engraved at keyframes one zoom step apart (a
step is about 47 seconds at `zoom 1`), a little larger than the screen. Two
are kept: the surface magnifies the upper one onto the screen and, over the
last 15% of each step, fades in the next one minified. The next keyframe is
engraved a band of rows per frame while the wallpaper plays, so no frame
stalls. At a loop boundary the keyframe is re-used, turned and with its tide
phase shifted. The frame rate adapts: 10 fps for the lights, and while diving
just enough that no pixel moves more than about half a pixel per frame (15 fps
on a 4K screen at `zoom 1`, 10 on 1080p). Measured at 4K on llvmpipe (Ryzen 9
9950X), a still plate costs 120–145 ms of CPU time per frame (5 ms wall), a
dive about 175 ms (6.5 ms wall) and 240 ms during the fades, and each new
keyframe about 5 s more, spread over 16 frames (about a second, 18 ms wall
each). A 1080×1920 screen costs a fifth of that. Colour cycling costs nothing
measurable.

A change to anything engraved (the view, a preset, iteration detail, groove
density or wire weight) is engraved the same way, a band of rows at a time
between frames, so it never holds up the desktop or the studio. Until the new
keyframe lands, the old one stays on screen. After a change of view it is
stretched into place, so the move shows at once and sharpens a moment later;
one that would have to be magnified more than eightfold, or has all but left
the screen, is shown as it was instead.
The desktop starts engraving once changes have paused for 0.3 s. While you
move about the map or drag a slider that re-engraves, the studio's preview
engraves quick drafts, one sample per texel instead of four, and engraves in
full when you stop. Measured at 4K, the shell kept answering within 27–34 ms
while the map was dragged and within 209 ms while a new view was committed;
before 3.3, a change of view froze it for about 2.5 s.

Rendering preserves the monitor's aspect ratio and uses the configured texture
limit to bound the cost on large displays. While the engraving is on screen the
theme photo is not drawn at all. Animation pauses while idle, locked, on a
sleeping display, or behind a fullscreen window; `status` reports the reason
per display.

## Restore the standard background

```bash
omarchy-fractal off
```

This re-enables `omarchy.background` (the standard renderer).
`omarchy-fractal on` returns to Filigree with your settings.

## Development

From the repository root, rebuild the baked shaders after editing `plugin/*.frag`:

```bash
plugin/build-shaders
```

This updates the checkout, not an installed copy. After updating the installed
plugin with the rebuilt shaders, run `omarchy restart shell` to load them.

Validate the root manifest against Omarchy's manifest schema from the
repository root:

```bash
omarchy plugin validate .
```