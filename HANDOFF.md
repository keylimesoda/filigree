# Filigree (`ric.background`) — hand-off spec

Written for the next agent taking over this project. Everything below is
either measured, read from the code, or quoted from the user; anything not
verified is marked **unverified**. Line numbers are approximate — grep to
confirm before editing.

---

## 0. Status at hand-off (TL;DR)

| | State |
|---|---|
| **Deployed** (`~/.config/omarchy/plugins/ric.background/`) | **3.3.0**, stable, running live on both displays |
| **Dev** (`/home/ric/Work/filigree/plugin/`) | 3.3.0 **plus in-progress 3.4.0 "Finest detail" (satin prefilter)**; `manifest.json` still says 3.3.0 |
| Satin engine (shaders + `Fractal.qml`) | Implemented, calibrated, verified offscreen |
| Setting plumbing (Background/Studio/CLI/README/manifest) | **Not started** |
| Deploy of 3.4.0 | **Not done** |

- The in-flight change is saved as a patch against the deployed 3.3.0 (excluding
  `.qsb` binaries): `scratch/satin-harness/satin-3.4.0-wip.diff`. It touches
  4 files: `build-shaders`, `Fractal.qml`, `satin.frag` (new) and `surface.frag`.
- Next actions: **§7**.

---

## 1. What Filigree is, and the quality bar

Filigree is an animated fractal wallpaper for Omarchy (Hyprland + Quickshell).
It is a native shell plugin cloned from `omarchy.background`, with two
manifest kinds: `service` (`Background.qml`) and `panel`
(`FiligreeStudio.qml`, "the studio").

The look is a guilloché watch dial:
- fine grooves cut along the Mandelbrot set's external rays;
- the set's boundary rising as rounded gold wire (Kajiya–Kay fibre lighting);
- enamel pools inside the set;
- two or three theme-coloured lights orbiting slowly;
- a tide of light running down the equipotentials;
- an optional endless, seamless dive into self-similar (Misiurewicz) points;
- optional heat-tint colour cycling.

All colours come from the current Omarchy theme, and light themes print the
same engraving as ink on paper.

What the user asked for, in their own words:
- "This wallpaper should be gorgeous, with subtle animation, like pretend this
  is your resume entry for working at a math-brained high-end design firm."
- "The existing animation (waving back and forth) is terrible. Do something
  freaking awesome."
- Later requests:
  - "a subtle ongoing zoom, or a slight color cycling";
  - how to load and configure it, and how to open its config;
  - studio performance, the Center fields, and a navigable map preview ("We
    want this to be easy/accessible for folks to use and make beautiful
    things");
  - finally, the "smallest render detail size" / crawl question, which led
    to the satin feature (the user replied "Go ahead").

## 2. Ground rules (follow these)

1. **Never guess or infer code behaviour.** The user's standing instruction is:
   "DO NOT, UNDER ANY CIRCUMSTANCES, GUESS OR INFER unless you ask me first."
   Back every claim with code, a measurement or a test, and label hypotheses
   as such.
2. **The user is often at the machine.**
   - Send no synthetic mouse or keyboard input, and don't steal focus.
   - Use IPC (`omarchy-shell fractal …`) and the offscreen harness instead.
3. **Do not change the user's live Filigree settings.** Read them with
   `status` only. If a live test must change something, restore it exactly.
4. **CPU is the budget.** The desktop shell renders in software (llvmpipe) on
   a Ryzen 9 9950X (32 threads). Every per-frame ALU op and texture fetch
   matters. The user's criterion for the satin feature was "both more
   attractive and similarly or more performant".
5. **`omarchy restart shell` restarts the user's whole shell and closes the
   studio.** Do it only to deploy.
6. **Never edit `/usr/share/omarchy/`.** Reading it is fine.
7. When the user asks to "discuss before any changes", do analysis only.

## 3. Where things are

| Path | What |
|---|---|
| `/home/ric/Work/filigree/plugin/` | **Dev copy** (not a git repo). `Background.v1.qml` here is an old dev-only leftover and is not deployed |
| `~/.config/omarchy/plugins/ric.background/` | **Deployed copy** (3.3.0) |
| `~/.config/omarchy/shell.json` | Live settings, inline on the `ric.background` entry |
| `~/.local/state/omarchy/filigree-settings.json` | Filigree's own copy of the settings, restored when switched back on |
| `~/.local/state/omarchy/filigree-equations/` | Custom-equation shader cache, keyed by hash |
| `/home/ric/Work/filigree/scratch/bench/` | `frender` offscreen renderer (`frender.cpp`), `env.sh` (forces llvmpipe), `qmltest/` (studio unit tests), `test_navigation.js` (map math tests) |
| `/home/ric/Work/filigree/scratch/satin-harness/` | **Preserved satin measurement harness**: scripts, `base-plugin/` (= 3.3.0 reference), diagnostic shader variants, evidence crops, WIP diff. See §8 |
| `/home/ric/Work/filigree/scratch/backup-*` | Older backups (v2, v3.0.0, v3.1 deployed) |
| `scratch/fild/` | Live working copy of the harness (sed-rewritten from the `/tmp/fil-d` layout, which the 2026-09-26 reboot wiped along with `/tmp`; `/tmp` is ephemeral per command in agent sessions, so keep everything under the workspace). venv at `scratch/fild/venv`; outputs `scratch/fild/r/` (throwaway, deleted 2026-09-26); visual crops in `scratch/fild/crops/` |

## 4. Architecture

### 4.1 Plugin files

| File | Role |
|---|---|
| `Background.qml` | Service. Reads settings (`numberSetting(key, default, min, max)`), presets, the dive-point table, IPC handlers (`configure`, `status`, `captureScreen`, …), and one `Fractal` per screen |
| `Fractal.qml` | The renderer: keyframe slots (`KeySlot`), banded bakes, composition, the surface `ShaderEffect`, lights and colour maths (OKLab), dive and loop logic, and the satin wiring |
| `fractal.frag` | Bake shader. Iterates the fractal with analytic derivatives and perturbation, using 4 RGSS samples per texel, into an RGBA8 field. It is also the template for custom equations, so keep it compatible |
| `fractal-template.glsl` | Generated by `build-shaders` from `fractal.frag`, with `CUSTOM_EQUATION` defined |
| `equation-compiler.py` | Compiles the safe equation language to a shader |
| `surface.frag` | Per-frame lighting. Built as 5 variants: plain, `-dive`, `-blend`, `-dissolve`, `-stretch` |
| `satin.frag` | **New in 3.4.0.** The composition-time satin filter |
| `build-shaders` | Runs `qsb` for every shader. `satin.frag` and the dive variants need GLSL 150 / ES 300 because they use `texelFetch` |
| `FiligreeStudio.qml` | Studio panel: pages Motion / Fractal / Color, a live preview that is also a map, and number inputs |
| `navigation.js` | Map-view maths (pure functions, tested by `test_navigation.js`) |
| `fractal` | CLI: `on`, `off`, `settings`, `preset`, `equation`, `set`, `pause`, `resume`, `toggle`, `status`, `capture`. `~/.local/bin/omarchy-fractal` is a symlink to the **deployed** copy of this script |
| `divepoints.py` | Offline finder for dive points (Misiurewicz points and self-similarity parameters) |
| `manifest.json` | Plugin manifest (version, kinds, entry points) |

### 4.2 Render pipeline

The pipeline has three stages; the full user-facing description is in
README "How it renders".

1. **Bake** (per keyframe, spread over frames in bands of rows).
   - `fractal.frag` renders an RGBA8 field of about one texel per screen
     pixel, a little larger than the screen.
   - Field format (stated in checkpoint notes; `fractal.frag` is the ground
     truth):
     - **r, g** = the normal, stored as ·0.5+0.5. On the wire its length is
       `rim` = 0.5/√1.25 ≈ 0.447.
     - **b** below 0.2 codes pool coverage (0 = fully inside the set).
       Otherwise it is the distance ramp `log2(d/shorter)/16 + 1`.
     - **a** = an angle: the doubled-angle fibre direction on and near the
       wire (ramp < `fibreLevel`), or the tide phase elsewhere.
   - The field holds no colour, so theme changes and lights never re-bake.
2. **Compose.**
   - The band textures are drawn by the `pieces` Repeater into `assembly`.
   - `assembly` is captured by the `composed` ShaderEffectSource, which is
     `live: false`, so it renders only when `scheduleUpdate()` is called.
   - In 3.4.0 the pieces run `satin.frag` when satin is on; otherwise they
     are plain copies.
3. **Surface** (every frame).
   - `surface.frag` makes exactly **2 fetches**: a bilinear `g` and a
     nearest `ta` (`texelFetch`). Everything else is ALU.
   - Measured on llvmpipe at 4K, any extra per-frame texture fetch costs
     +40 ms CPU (nearest) or +75 ms (bilinear). **Do not add per-frame
     fetches.**

Other behaviour:
- **Dive:** two slots. The surface magnifies keyframe A and, over the last
  15% of each step, fades in B (blend, or dissolve for non-self-similar
  views). At a loop boundary the keyframe is reused, turned and with its tide
  phase shifted.
- **View changes (3.3.0 "stretch-and-refine"):** the old keyframe is
  stretched into place (the `STRETCH` variant) while the new one bakes
  gradually. The studio bakes drafts (1 sample per texel) while the user
  interacts.
- **Frame rate:** adaptive, up to the `fps` cap: 10 fps for the lights, and
  while diving just enough that no pixel moves more than about 0.5 px per
  frame. The user currently runs at 6 fps.

### 4.3 How the user opens things

- On/off: `omarchy-fractal on` / `off`.
  - It is **not** an entry in the background picker.
  - Picking a photo in the picker switches back to `omarchy.background`.
- Studio:
  - `omarchy-fractal settings`;
  - the Omarchy menu → Style → Filigree (via
    `~/.config/omarchy/extensions/omarchy-menu.jsonc`; see the README);
  - or typing "filigree" in the menu.
- Desktop gestures:
  - left double-click on the bare desktop = pause / resume;
  - right double-click = theme picker;
  - middle click = background picker.

## 5. History (done)

| Version | Checkpoints | Delivered |
|---|---|---|
| 3.0.0 | 1–4 | Rebuild as the guilloché engraving. Bake once, light per frame; dark-field and light-theme ink; gold wire; enamel; orbiting theme lights |
| 3.1 | 5–8 | Opt-in dive zoom and heat-tint colour flow. Fixed settings loss on off/on (state-file copy) |
| 3.2.0 | 9–16 | Perturbation-based endless dives into Misiurewicz points (filigree, seahorse, julia, mandelbrot tour); dissolve loop for other views; band-limited RGSS bake (wire ≥ 2.6 px); Kajiya–Kay gold; OKLab "intensity"; adaptive fps; banded bakes (no stalls) |
| 3.2 + menu | 17 | Omarchy menu entry (documented in the README) |
| 3.3.0 | 17–25 | Stretch-and-refine renderer: a view change used to freeze the shell ~2.5 s; now it stays responsive (27–34 ms while dragging the map). Also: Center fields fixed; navigable map preview (drag, wheel, keys, dive aiming, gold diamonds at dive points); floating studio window; `qmltest` harness (21 tests passing at 3.3.0) |
| 3.4.0 (WIP) | 26–31 + last segment | "Finest detail" satin prefilter (§6) |

## 6. In flight: 3.4.0 "Finest detail" (satin prefilter)

### 6.1 The problem (measured, checkpoint 27)

The user saw one-pixel "crawl/noise" in dense lace during animation. The
measurements (trinity scene, user settings, 4K, frender on llvmpipe) were:

- **The crawl comes from the dive, not the lights.** Dense-lace mean |Δ| per
  6-fps frame:
  - dive only: 25.0;
  - lights + tide only: 0.24.
- **Knockouts point at the glints.** With no Kajiya–Kay glints the crawl
  drops 73%; with flat normals it drops about 100%.
- **Dense lace is almost all wire.** It is 95.8% wire pixels, and 52.5% of
  them take the fibre angle from the nearest texel.
- **Conclusion:** the "1-px detail" is glints flipping as per-pixel fibre
  directions change, not geometry.
- **A second artefact (not addressed):** a 15.07-px axis-aligned grid of
  change lines where nearest-texel lookups switch texels as the zoom
  advances. The FFT period matched the predicted beat period.

### 6.2 Design (chosen after an evidence-based discussion; the user said "Go ahead")

**Setting.** `detail` (label "Finest detail"), in screen pixels, range 1–4,
default 2. Detail 1 keeps 3.3.0 exactly.

**"Approach P": filter once at composition, not per frame.**

The band-copy pieces run `satin.frag`. For each wire texel it:
- averages the doubled-angle fibre vectors (cos 2θ, sin 2θ) over a Gaussian
  footprint;
- takes coherence κ = |mean vector| (1 on a clean wire, near 0 where
  directions disagree);
- writes the mean direction into **a**;
- on wire texels (b < `metalCut`), writes the normal as `rim·κ·across`, with
  its sign matched to the original normal. So **κ travels in the normal's
  length**, and the surface still makes zero extra fetches.

Band edges read the neighbouring bands, which are linked in the Repeater's
`onItemAdded` handler.

**Kernel** (`Fractal.qml` `satinKernel`):
- σ = √max(0, (0.375·detail·cacheScale)² − 0.42²) texels;
- radius = clamp(round(2σ), 1, 4); taps = exp(−k²/2σ²);
- satin is off if detail ≤ 1 or σ < 0.2;
- resulting values: detail 2 → σ 0.621, r 1 (9 taps); detail 3 → σ 1.044,
  r 2; detail 4 → σ 1.44, r 3.

**Surface** (`surface.frag` `plate()`, all inside a uniform `if (satin > 0.5)`
so detail 1 costs the same as 3.3.0):

- **Coherence.** `k = coherence(t) = min(|t.rg·2−1| / rim, 1)` on wire texels
  (`0.002 ≤ t.b < metalCut`), otherwise 1.
- **Mean-preserving lobe cascade.** `widen(sharp, broader, scale, w)`: as k
  falls, each Kajiya–Kay lobe hands part of itself to the next broader lobe,
  scaled to the same mean over all directions.
  - Weights: k² for lobe 16; k⁵ (key) or k⁴ (fill and third) for lobe 64;
    k¹⁶ for lobe 128.
  - The means come from `lobeMeans(elevation)` in QML (`keyMeans`,
    `fillMeans`, `thirdMeans`).
  - At k = 1 every lobe is exactly as before.
- **Clip shift.** A flattened glint looks dimmer than glitter, because the
  display clips glitter peaks and the eye sums light linearly.
  - Fix: `satinShift0..3` is a cubic in e, with e = clamp(body·vignette,
    0.3, 1), weighted by (1 − k⁵).
  - QML fits it at 4 knots from the wire lit from 720 directions, clipped,
    then averaged in linear light.
- **Dull share** (DIVE builds only). This is a measured root cause, not a
  guess.
  - In 3.3.0, DIVE `direction()` = mix(circle(t.a), fromNormal, trust). At
    filament centres the bilinear normals cancel, so trust is intermediate
    and the two vectors disagree.
  - The direction vector shortens and those pixels hardly glint ("dull
    pixels"). Satin's coherent normals revived them, which made dense lace
    +5.6% too bright.
  - Fix: a second cubic `satinDull0..3` weighted by (1 − trust), with share
    `satinDull = clamp(0.19 − 0.067·(σ − 0.62), 0.1, 0.21)`, fitted to
    renders.
  - The plain (non-dive) surface has trust = 1, so the term vanishes there.
- **Live changes.** A live detail change recomposes from the intact bands
  without re-baking: `onSatinTapsChanged` / `onSatinOnChanged` →
  `slotN.recompose()`, guarded by `bandsIntact`.
- **Failure fallback.** If `satin.frag` fails to load, `satinFailed` is set
  and the wire glints as at detail 1.

Designs that were rejected:
- a separate "fibres" texture read per frame (too costly: see the fetch costs
  in §4.2);
- the first preview's Toksvig-style lobe widening. It used 9 per-frame
  fetches and measured +36% too bright in dense lace; the mean-preserving
  cascade replaced it;
- two micro-optimisations, measured with no gain: a dynamic skip
  `if (k < 1 || trust < 1)`, and passing the vignette factor through.

### 6.3 Code map (dev copy)

**`surface.frag`**
- Uniforms: `satin`, `invRim`, `metalCut`, `keyMeans` / `fillMeans` /
  `thirdMeans`, `satinShift0..3`, `satinDull0..3` (~l.71–97).
- `direction(t, g, out trust)` (~l.145).
- `coherence()` and `widen()` (~l.159–174).
- The satin block in `plate()` (~l.300–336).

**`Fractal.qml`**
- `detail` and `satinFailed` (~l.94–100).
- Engraving constants, including `fibreLevel`, `metalCut` and `rim`
  (~l.115–134).
- `satinKernel` and `lobeMeans` (~l.136–160).
- The clip-shift / dull-share comment, `linear` / `encoded`, `satinDull`
  and `satinShift` (8 vectors: [0..3] clip, [4..7] dull) (~l.161–237).
- `satinTaps` and `satinOn` (~l.238).
- Recompose hooks (~l.716).
- `KeySlot` `bandsIntact`, `compose()`, `recompose()` (~l.800–915).
- The satin-capable `pieces` delegate (~l.960–1015).
- Surface uniforms (~l.1085–1105).

**`satin.frag`**: the composition kernel (fully commented).

**`build-shaders`**: skips `satin.frag` in the generic loop and compiles it
with `--glsl '150,300 es'`.

### 6.4 Results

All results are from the frender harness at 3840×2160 on llvmpipe.

**Crawl.** Dense-lace mean |ΔL| per frame, with 1/6 elapsed-second steps,
dive:

| Scene | 3.3.0 | detail 2 | detail 3 | detail 4 |
|---|---|---|---|---|
| Trinity | 60.2 | 25.7 (−57%) | 15.6 (−74%) | 11.8 (−80%) |
| Seahorse (the user's preset) | 62.3 | 23.6 (−62%) | 11.6 (−81%) | 7.3 (−88%) |

**Brightness and colour** vs 3.3.0:
- Method: linear-light Y ratio, with masks from the mean of 8 light angles
  (orbit renders); ΔE = CIE76 of the mean colour.
- JND ≈ 2.3. Whole-frame Y ratio is 0.99–1.00.

| Case | Dense Y | Dense ΔE | Smooth Y | Smooth ΔE |
|---|---|---|---|---|
| Trinity d2 | 0.999 | 0.13 | 1.004 | 0.66 |
| Trinity d3 | 0.986 | 1.04 | | |
| Trinity d4 | 1.002 | 1.13 | | |
| Seahorse d2 | 0.999 | 0.97 | | |
| Seahorse d3 | 0.982 | 0.78 | | |
| Seahorse d4 | 0.991 | 0.65 | | |
| Light theme, trinity d2 | 0.982 | 0.99 | | |
| Non-dive (zoom 0), trinity d2 | 1.020 | 1.65 | | |
| Non-dive (zoom 0), trinity d4 | 1.013 | 0.64 | | |

**Look.** Dense lace becomes a matte/hammered satin sheen framed by crisp
polished curls. See `satin-harness/crop-light.png`, `crop-trinity.png` and
`sb-crop.png`.

**Per-frame CPU.**
- Method: `bench.sh`, 40 frames, median ms of process CPU across all threads,
  run sequentially.
- The machine was shared: load 9–14, including the user's own shell
  animating.

| Scene | 3.3.0 base | detail 1 | detail 2 | detail 4 |
|---|---|---|---|---|
| Trinity dive | 163.0, 158.0, 161.9, 157.6, 159.1 | 158.9, 160.4 | 169.8, 171.1, 170.1, 176.2, 173.2 | 170.7, 183.2 |
| Seahorse dive | 181.1, 178.7, 180.9 | | 191.8, 190.0, 193.3 | |

→ Detail 1 costs the same as 3.3.0. Detail 2 costs **+6% (seahorse) to +8%
(trinity)** per frame. This satin ALU is present only on wire pixels.

**Compose frame** (one-off, when a keyframe is composed):
- Measured through a live detail change on trinity at 4K. **Both slots were
  recomposed in that one frame**, which also includes the normal surface
  render.
- Normal frames around it: ~6–7 ms wall, 160–190 ms CPU.
- Per-keyframe cost in an ordinary dive (one slot at a time) was **not
  measured separately**. No keyframe compose happened within the bench
  windows.

| Change to | Wall | CPU |
|---|---|---|
| →d1 (plain copy) | 43.1 ms | 756 ms |
| →d2 (r 1, 9 taps) | 48.9 ms | 1145 ms |
| →d3 (r 2, 25 taps) | 61.9 ms | 1259 ms |
| →d4 (r 3, 49 taps) | 69.8 ms | 1631 ms |

### 6.5 Verified vs not verified

**Verified**
- **Detail 1 matches 3.3.0.** Max diff is 1/255 on a single pixel of 8.3 M
  (trinity dive, 4K).
- **The uniform-branch refactor didn't change detail 2.** Output is
  bit-identical before and after (trinity and seahorse).
- **Live detail changes work.** 2→1, 1→3, 4→2 and 2→4 each recompose in one
  frame from intact bands. There is no re-bake and no errors, and the satin
  radius switches correctly (0 / 1 / 2 / 3). Logs:
  `/tmp/fil-d/r/chg-*.log`.
- All the numbers in §6.4.

**Not verified yet**
- That the image after a live change equals a fresh render at the new detail.
  The last bench frame of each change run was saved as
  `/tmp/fil-d/r/chg-<from>-<to>-end.png`, at t = 13.4439. Render a fresh one
  at that t and diff.
- Transitions with satin on: the blend, dissolve and stretch variants, over
  frames inside a blend window and during a view change (look for errors and
  visual seams).
- Light theme at d3/d4, non-dive at d3, and the 1080×1920 portrait screen.
- `cacheScale < 1` (maxDimension below the screen size). The kernel scales σ
  by `cacheScale`, and satin switches itself off when σ < 0.2.
- The studio preview's `Fractal` (FiligreeStudio.qml ~l.620) **does not bind
  `detail` yet**, so it always uses the default 2.
- `qmltest` and `test_navigation.js` have not been re-run. No studio file has
  changed yet.

## 7. Remaining work (in order)

> **Status (2026-09-26, session 2) — items 1–7 done in the dev copy; only 8 (deploy) remains, gated on the user.**
> - §6.5 gaps closed by the Phase A / A.5 harness battery (re-run this session
>   because `/tmp` proved ephemeral; harness now lives in `scratch/fild/`):
>   live detail changes are pixel-identical to fresh boots (4/4 diffs 0.000000);
>   trinity + seahorse blend windows and the trinity dissolve (detail 4,
>   blend 0.819→1.000), stretch (29 frames) and portrait runs all clean;
>   cacheScale<1: detail 2 + maxDimension 1920 on 4K → satin off (σ<0.2),
>   detail 4 → on. Brightness vs detail 1: light d3 ΔE≤1.06, light d4
>   ΔE≤0.89, non-dive dark d3 ΔE≤1.10 (JND ≈ 2.3). Crawl/CPU numbers from
>   §6.4 stand.
> - Item 7 validation: `./build-shaders` OK; `omarchy plugin validate .`
>   rc=0; `scratch/bench/qmltest/run.sh` → **25 passed / 0 failed** (the 21
>   original tests plus a new CompileCheck compiling Fractal.qml and
>   FiligreeStudio.qml against the shell-module stubs);
>   `node scratch/bench/test_navigation.js` all pass.
> - QML load check (frender + extended stubs in `qmltest/stubs`):
>   FiligreeStudio.qml loads, type-checks, instantiates and renders offscreen
>   (rc=0). Background.qml parses completely and resolves every type and
>   property except two harness-only artifacts on 3.3.0-era code:
>   `WlrLayershell` attached properties (C++ attachables, not expressible in
>   pure-QML stubs) and boolean-edge `anchors { top: true; … }` (this
>   build's QQuickAnchorLine rejects them even on a plain Item in frender
>   and qmltestrunner, yet the live shell — same /usr/lib Qt 6.11 via
>   /usr/bin/quickshell — compiles them fine).
> - CLI: `plugin/fractal --help` shows the detail line; out-of-range values
>   are rejected client-side (no IPC reaches the live shell);
>   `setting_json detail 2.5|1|4` emits correct JSON (`integer=false`,
>   matching the studio's 0.5 step).
> - Visuals: crops in `scratch/fild/crops/` (the dissolve frame was
>   re-cropped in-bounds — the earlier "pitch-black L-region" finding was
>   PIL padding from an oversized crop box; the raw frame has 0.000%
>   pure-black pixels). Statistical scan (sub-agent, decoder verified
>   pixel-identical to ImageMagick; kept at `crops/qa_scan.py`): all other
>   frames clean; the few bright-strip candidates drift position as the
>   view magnifies (engraving features, not seams). The sheen/ghosting
>   "look" still needs the user's eyes after deploy — this model cannot
>   read images.
> - Item 8 deploy: backups already made
>   (`scratch/backup-deployed-v3.3.0-20260926-024912`,
>   `backup-plugin-v3.4.0wip-20260926-024912`, live snapshot
>   `snapshot-live-20260926-024912`). Awaiting user go-ahead.

1. **(Recommended) close the verification gaps** in §6.5 using the harness
   (§8).
2. **`Background.qml`** — add the setting:
   - Near `wire` (~l.42), add
     `readonly property real detail: numberSetting("detail", 2, 1, 4)`.
   - In the `configure()` ranges object (~l.203–209), add `detail: [1, 4]`.
     Check how `configure()` treats keys that aren't in `ranges`.
   - In `statusJson()` (~l.256–272), add `detail: detail` and bump
     `version: "3.3.0"` → `"3.4.0"`.
   - In the `Fractal { … }` instance (~l.790–835, next to
     `wireWidth: 0.002 * root.wire`), add `detail: root.detail`.
   - Presets (~l.84–103) hold compositions only; `wire` isn't in them, so
     `detail` shouldn't be either.
3. **`FiligreeStudio.qml`**:
   - Add `detail: 2` to the defaults object at ~l.44 (it lists `wire: 1.0`).
     Check how Reset and Revert use it.
   - On the Color page, after "Wire weight" (~l.1127), add a slider. Use
     `rebakes: false`: a detail change only recomposes. Suggested:
     ```qml
     TuningSlider { label: "Finest detail"; setting: "detail"; minimum: 1; maximum: 4; step: 0.5; decimals: 1; suffix: " px"; hint: "Lace finer than this is lit as a satin sheen instead of glinting, so dense areas shimmer instead of crawling. 1 keeps every glint." }
     ```
   - Bind the preview `Fractal` (~l.620–662): `detail: Number(root.value("detail"))`.
     This raises the open question in §11.1.
4. **`fractal` CLI**:
   - Add `detail) minimum=1; maximum=4 ;;` to the `setting_json()` case
     (~l.102–120). Without it, `set detail` fails with "unknown setting".
   - Add a help line under "Settings:" (~l.27–45), e.g.
     `detail  1..4  default 2 (finest detail in px; finer lace is lit as satin)`.
   - `omarchy-fractal` runs the **deployed** script, so test the dev copy
     directly (`plugin/fractal …`) until it is deployed.
5. **`README.md`**:
   - Settings table row (~l.237):
     `| detail | 2 | 1–4 | Finest detail, in pixels: lace finer than this is lit as a satin sheen instead of glinting; 1 keeps every glint |`.
   - Add an example under Controls.
   - Add a satin paragraph plus the measured costs to "How it renders".
   - Mention the slider in the studio's Color-page description (~l.79–81).
6. **`manifest.json`**: version `3.4.0`. Optionally mention satin in the
   description.
7. **Validate**:
   - `./build-shaders`, then `omarchy plugin validate .` (in `plugin/`).
   - `scratch/bench/qmltest/run.sh`, which should still pass (21 tests at
     3.3.0).
   - `node scratch/bench/test_navigation.js`.
   - A harness render at each detail level after the plumbing, to confirm the
     `Background.qml` binding works (§8).
8. **Deploy.** The user is usually present, so say what you're doing, and
   warn that the studio will close.
   1. Back up the deployed copy:
      `cp -a ~/.config/omarchy/plugins/ric.background /home/ric/Work/filigree/scratch/backup-deployed-v3.3.0-$(date +%Y%m%d-%H%M%S)`.
   2. Copy the dev files, including `satin.frag`, `satin.frag.qsb` and every
      rebuilt `.qsb`, but not `Background.v1.qml`:
      `rsync -a --exclude Background.v1.qml /home/ric/Work/filigree/plugin/ ~/.config/omarchy/plugins/ric.background/`.
   3. Check with `diff -rq` that the only difference left is
      `Background.v1.qml`.
   4. Run `omarchy restart shell`.
   5. Run `OMARCHY_SHELL_IPC_TIMEOUT=10s omarchy-shell fractal status`. Expect
      version `3.4.0`, `detail` 2, and both displays `ready:true`,
      `shaderFailed:false`.
   6. Check the shell logs for `Filigree satin:` or `Filigree field:` errors
      (these strings come from `console.error` in `Fractal.qml`).
   7. Take a live capture:
      `OMARCHY_SHELL_IPC_TIMEOUT=10s omarchy-shell fractal captureScreen HDMI-A-1 /abs/path.png`.
      It is asynchronous: poll `capturePath` in `status`.
   8. **Don't change the user's settings.** The user's current `detail` is
      unset, so they get the default 2.
9. **Clean up**:
   - `rm -rf /tmp/fil-d` (8.9 GB; the harness is preserved in
     `scratch/satin-harness`).
   - Remove any other temp dirs you create.
10. Report to the user with measured numbers only. Use §6.4 (and update it if
    anything changes).

## 8. Test and measurement harness

**Offscreen renderer.**
```bash
cd /home/ric/Work/filigree/scratch/bench && source ./env.sh   # env.sh forces Mesa/llvmpipe; without it frender uses the GPU
./frender FILE.qml --size 3840x2160 --warmup 25000 [--prop k=v]... --times t0,t1,... --settle 2 --out /path/%1.png
#   --bench N --bench-dt DT --trace   → per-frame "bench i t=… wall=… cpu=…" (cpu = process CPU, all threads, renderFrame only)
#   With --out, the last bench frame is also saved as "<name>-end.png".
```

**Restoring the satin harness** (its scripts hard-code `/tmp/fil-d`):
```bash
mkdir -p /tmp/fil-d/r && cp -r /home/ric/Work/filigree/scratch/satin-harness/. /tmp/fil-d/
python3 -m venv /tmp/fil-d/venv && /tmp/fil-d/venv/bin/pip install numpy pillow scipy
```

**What each file does**
- `Test-dev.qml` imports the dev plugin; `Test-base.qml` imports
  `/tmp/fil-d/base-plugin` (the 3.3.0 reference). Both expose props:
  - `detail`;
  - `detail2` + `changeAt` (a scripted live change);
  - `light` (1 = light theme);
  - `trace` (1 = print a `STATE` line every frame, with slots, `comp`,
    `intact` and satin radius);
  - `orbitMul` / `orbitBase`.
- `render.sh <base|dev|dv-NAME> <trinity|seahorse> <name> <e0> <dt> <n> [--prop k=v…]`
  - Writes `/tmp/fil-d/r/<name>-NNN.png` and `<name>.log`.
  - Environment variables: `SIZE` (default 3840x2160), `WARM` (25000 ms),
    `MOTION` (0.8), `ZOOM` (2; 0 = non-dive).
- `bench.sh <which> <scene> <tag> <e0> <dt> [props]` prints the per-frame CPU
  median over `BN` = 40 frames. **Run benches sequentially and interleave
  variants**, because the machine is shared.
- `mkdvar.sh <name> <src.frag>` builds a symlinked copy of the dev plugin
  whose surface variants come from `src.frag`, and writes `Test-dv-<name>.qml`.
  Use it for A/B shader experiments.
- Scene args: `trinity.args` (the `z^3+c` custom shader from the user's
  equation cache, e0 = 11.4439) and `seahorse.args` (e0 = 11.31).
- Metrics, all as `<script> <base> <n> <runs…>` over `/tmp/fil-d/r/`:
  - `lin.py`: crawl, with masks from base frame 0;
  - `lin2.py`: brightness, with masks from the mean of all base frames — use
    this for brightness;
  - `de.py`: CIE76 ΔE of mean colours;
  - `perframe.py` / `measure.py`: older variants.
  - `model.py` is the numeric model of the lobe cascade.

**Standard runs**
```bash
./render.sh base trinity bt 11.4439 0.1666667 8                      # dive, crawl
./render.sh dev  trinity f2t 11.4439 0.1666667 8 --prop detail=2
./render.sh base trinity bto 11.4439 0.0001 8 --prop orbitMul=112500 --prop orbitBase=11.4439   # 8 light angles 45° apart, static geometry → brightness
MOTION=0.8 ZOOM=0 ./render.sh …                                      # non-dive
./render.sh dev trinity chg 11.4439 0.0166667 1 --bench 40 --bench-dt 0.05 --trace --prop trace=1 --prop detail=2 --prop detail2=4 --prop changeAt=12.0
```

**Methodology lessons.** These were learned the hard way; follow them.
- **Accumulate image means in float64.** A float32 `.mean()` over a 4K frame
  was wrong by 1–2%, and it corrupted earlier RGB-ratio claims.
- **Don't build brightness masks from one base frame.** That selects pixels
  that happen to be bright in that frame (regression to the mean). Use the
  mean over the orbit set (`lin2.py`).
- **Calibrate brightness in linear light,** across light angles and in both
  scenes.
- **Bench noise is about ±3%** with the user's shell animating. Use 3
  interleaved rounds before claiming a difference.

**Other tests**
- `scratch/bench/qmltest/run.sh`: offscreen `qmltestrunner` tests of the
  studio's NumberInput and window sizing, with Omarchy modules stubbed.
- `node scratch/bench/test_navigation.js`: tests the map maths in
  `navigation.js`.

## 9. Live system facts

**Displays**
- HDMI-A-1: 3840×2160.
- DP-3: 1080×1920, portrait.

**Shell**
- The live shell is `quickshell -p /usr/share/omarchy/shell`, RSS about
  1.3 GB. It is rendered in software (llvmpipe):
  `~/.config/omarchy/shell-render.conf:8` has `render=software`, via the
  user's `ric.shell-render` plugin.
- The shell restarted at about 02:02 on the day of hand-off. The cause is
  unknown; `coredumpctl` showed no core dump.

**User settings** (last `status`, read-only — do not change):
- Composition: preset `seahorse`, zoomLoop `dive`, center
  (−0.7760421936870407, 0.13472427034434906), span 0.002, focus
  (0.17921283899346996, 0.8715489751705274).
- Motion: `paused: false`, speed 0.1, zoom 2, motion 0.19, fps cap 30,
  idlePause 120.
- Colour and detail: intensity 1.2, colorCycle 0.4, wire 1.55, iterations
  1500, colorMode 0, density 1, dark theme, maxDimension 3840.
- Both displays were animating at frameRate 6.
- (The user changes these themselves; earlier they had speed 2 and paused.)

**IPC**
- `omarchy-shell fractal status | configure '<json>' | captureScreen <screen> <abs.png>`.
- Set `OMARCHY_SHELL_IPC_TIMEOUT=10s`.

## 10. Pitfalls

- `live: false` sources render only when drawn. The 1-px helper
  `ShaderEffect` in `KeySlot` draws the active band or composition so that it
  updates.
- `satin.frag` and the dive variants need GLSL ≥ 150 (`texelFetch`). The
  generic `build-shaders` loop compiles for `100 es,120,150`, which is why
  satin is special-cased.
- A `ShaderEffect` whose shader came from Qt's cache can stay "Uncompiled"
  while rendering fine, so readiness is judged by the first completed bake.
- The equation-shader cache is keyed by hash. `fractal.frag` is the template,
  so changing it changes every custom equation's shader.
- Qt V4 JS: `Fractal.qml` uses `concat` instead of `flatMap`. This was a
  precaution; it was **not verified** that `flatMap` fails in this Qt.
- Settings are removed from `shell.json` when Omarchy re-enables
  `omarchy.background`. Filigree restores them from its state file.

## 11. Open questions / ideas for later

1. **The studio preview and `detail`.** `detail` is in screen pixels, and the
   preview is smaller than the desktop. Should the preview use the same pixel
   value (it smooths relatively more of the composition), or scale it by
   preview/desktop size to predict the desktop look? This is a product
   decision; ask the user.
2. **Satin per-frame cost** (+6–8% at detail 2).
   - Two bit-identical micro-optimisations gave nothing measurable
     (`satin-harness/dsrc/surface-db.frag`, `surface-vg.frag`).
   - Real savings would need changes to the output and re-validation, e.g. a
     scalar-times-colour shift instead of two vec3 cubics. Not attempted.
3. **Compose hitch at detail 3/4.** A double compose took 62–70 ms wall at 4K,
   versus 43 ms at detail 1. Measure a single-slot compose during an ordinary
   dive and decide whether it's acceptable.
4. **The 15-px texel-switch grid lines** from nearest-texel lookups (§6.1)
   remain. A future fix would need a linearly filterable encoding of the
   angle and trust inputs, without adding per-frame fetches.
