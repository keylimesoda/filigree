import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  // Filigree's user settings live on this plugin's native shell.json entry.
  property var shell: null
  property var manifest: null
  property var settings: ({})
  property string capturePath: ""
  property string captureError: ""
  property var artworkPalette: ({})
  property string artworkMode: ""
  // Light themes switch the engraving to bright-field lighting (ink on paper).
  readonly property bool lightTheme: artworkMode === "light"
    || (artworkMode === "" && 0.2126 * Color.background.r + 0.7152 * Color.background.g + 0.0722 * Color.background.b > 0.5)
  readonly property color secondaryColor: artworkPalette.cyan || artworkPalette.color6 || Color.accent
  readonly property color tertiaryColor: artworkPalette.magenta || artworkPalette.color5 || Color.foreground
  readonly property color goldColor: artworkPalette.yellow || artworkPalette.color3 || Color.accent
  // The rest of the theme's hues, which vivid colour flows borrow from.
  readonly property var extraColors: [["red", 1], ["yellow", 3], ["green", 2], ["cyan", 6], ["blue", 4], ["magenta", 5]]
    .map(pair => artworkPalette[pair[0]] || artworkPalette["color" + pair[1]] || "")
    .filter(value => value !== "")
  readonly property bool paused: settings.paused === true
  readonly property real motion: numberSetting("motion", 0.55, 0, 1)
  readonly property real speed: numberSetting("speed", 1.0, 0.1, 8)
  readonly property real intensity: numberSetting("intensity", 1.0, 0.1, 1.5)
  // A slow, endless zoom (0 = still) and a palette flowing along the bands.
  readonly property real zoom: numberSetting("zoom", 1, 0, 3)
  readonly property real colorCycle: numberSetting("colorCycle", 0, 0, 1)
  // A cap: the wallpaper draws only as often as its motion needs.
  readonly property int fps: Math.round(numberSetting("fps", 30, 1, 30))
  // Weight of the gold wire, relative to the default.
  readonly property real wire: numberSetting("wire", 1.0, 0.5, 2)
  // Finest detail, in screen pixels: lace finer than this is lit as a satin
  // sheen instead of glinting, so dense areas shimmer instead of crawling.
  // 1 keeps every glint (exactly 3.3.0's look).
  readonly property real detail: numberSetting("detail", 2, 1, 4)
  readonly property int maxDimension: Math.round(numberSetting("maxDimension", 3840, 960, 3840))
  readonly property int idlePause: Math.round(numberSetting("idlePause", 120, 30, 3600))
  // Composition (Fractal page in the studio). Presets write these as a bundle.
  readonly property string preset: String(settings.preset || "filigree")
  readonly property string equation: String(settings.equation || "z*z+c")
  readonly property bool julia: settings.julia === true
  readonly property real juliaReal: numberSetting("juliaReal", -0.8, -2, 2)
  readonly property real juliaImag: numberSetting("juliaImag", 0.156, -2, 2)
  readonly property real centerX: numberSetting("centerX", -0.10469636, -3, 3)
  readonly property real centerY: numberSetting("centerY", 0.95868651, -3, 3)
  readonly property real span: numberSetting("span", 0.03, 0.002, 5)
  readonly property real focusX: numberSetting("focusX", 0.12, -1, 1)
  readonly property real focusY: numberSetting("focusY", -0.08, -1, 1)
  readonly property int iterations: Math.round(numberSetting("iterations", 1500, 80, 5000))
  readonly property int colorMode: Math.round(numberSetting("colorMode", 0, 0, 3))
  readonly property real density: numberSetting("density", 1.0, 0.2, 2.5)

  // Custom-equation state. The default quadratic always uses the built-in
  // shader (analytic derivatives); any other equation is compiled to its own
  // .qsb and addressed by hash, so a failed compile never touches the live
  // wallpaper.
  property bool equationBusy: false
  property string equationError: ""
  property string compiledEquation: "z*z+c"
  property string pendingCompile: ""
  property bool usingCustomShader: false
  readonly property url builtinShaderUrl: Qt.resolvedUrl("fractal.frag.qsb")
  property url activeShaderUrl: Qt.resolvedUrl("fractal.frag.qsb")
  readonly property string pluginDir: {
    const u = Qt.resolvedUrl(".")
    return u.toString().replace(/^file:\/\//, "")
  }
  readonly property string equationCacheDir: stateHome + "/omarchy/filigree-equations"

  // Curated compositions. A preset writes its artwork parameters as a bundle;
  // motion, speed, frame rate, intensity, colour and idle policy stay with the
  // user. span is the height of the shorter screen side in the complex plane;
  // focus is where the vignette and the dome of the plate centre.
  readonly property var presets: ({
    "filigree": {
      centerX: -0.10469636, centerY: 0.95868651, span: 0.03, focusX: 0.12, focusY: -0.08,
      iterations: 1500, julia: false, density: 1.0, equation: "z*z+c"
    },
    "seahorse": {
      centerX: -0.77568377, centerY: 0.13646737, span: 0.01, focusX: 0, focusY: 0,
      iterations: 1500, julia: false, density: 1.0, equation: "z*z+c"
    },
    "julia": {
      julia: true, juliaReal: -0.8, juliaImag: 0.156,
      centerX: 0, centerY: 0, span: 3.2, focusX: -0.16484472, focusY: 0.02372256,
      iterations: 1500, density: 1.0, equation: "z*z+c"
    },
    // The whole set, focused on the seahorse point: a grand tour down into
    // the valley and its endless double spiral.
    "mandelbrot": {
      centerX: -0.75, centerY: 0, span: 2.6, focusX: -0.00987837, focusY: 0.05248745,
      iterations: 1500, julia: false, density: 1.0, equation: "z*z+c"
    },
    "trinity": {
      centerX: 0, centerY: 0, span: 3.1, focusX: 0, focusY: 0,
      iterations: 1500, julia: false, density: 1.0, equation: "z^3+c"
    }
  })

  // How the view zooms. About a Misiurewicz point of the Mandelbrot set, or a
  // repelling fixed point of a Julia set, the picture repeats itself at every
  // scale, so a view focused on one dives forever: one loop deeper it matches
  // itself scaled by `scale`, turned by `turn` radians, its bands `phase` tide
  // periods further on. Below `depth` (a span) one loop matches the next
  // closely enough to fade between them, so the loop starts there. Each pixel
  // is iterated as an offset from the point's exact orbit, which the bake
  // shader holds from `orbitStart` (both tables are written by divepoints.py).
  // Any other view dives in 3x and dissolves back to where it started.
  readonly property var divePoints: [
    {julia: false, x: -0.10109636384562216, y: 0.9562865108091415, scale: 2.343787, turn: 0.023399, phase: 1.5, steps: 6, depth: 0.00043,
     orbitStart: 0, orbitPre: 4, orbitPeriod: 1},
    {julia: false, x: -0.7756837680090538, y: 0.13646736829469012, scale: 2.584821, turn: 0.103525, phase: 12.5, steps: 7, depth: 1e-05,
     orbitStart: 5, orbitPre: 24, orbitPeriod: 1},
    {julia: true, juliaReal: -0.8, juliaImag: 0.156, x: -0.52750311864353463, y: 0.075912178352287865, scale: 3.817938, turn: -0.140121, phase: 10.5, steps: 10, depth: 0.0011,
     orbitStart: 30, orbitPre: 0, orbitPeriod: 1}
  ]
  readonly property var zoomLoop: loopFor({centerX: centerX, centerY: centerY, span: span, focusX: focusX,
    focusY: focusY, julia: julia, juliaReal: juliaReal, juliaImag: juliaImag})
  // The loop for any view; the studio asks about views it has not saved yet.
  function loopFor(v) {
    const fx = v.centerX + v.focusX * v.span, fy = v.centerY + v.focusY * v.span
    for (let i = 0; !usingCustomShader && i < divePoints.length; ++i) {
      const d = divePoints[i]
      if (d.julia !== v.julia) continue
      if (v.julia && (Math.abs(v.juliaReal - d.juliaReal) > 1e-9 || Math.abs(v.juliaImag - d.juliaImag) > 1e-9)) continue
      if (Math.abs(fx - d.x) < v.span * 0.002 && Math.abs(fy - d.y) < v.span * 0.002) {
        const entry = Math.max(0, Math.ceil(Math.log(v.span / d.depth) / Math.log(d.scale) - 0.01))
        // Dive into the point itself: a focus even slightly off it would
        // jump at the end of every loop.
        return {mode: "dive", dissolve: false, scale: d.scale, turn: d.turn, phase: d.phase, steps: d.steps, entry: entry,
          depth: d.depth, reference: true, x: d.x, y: d.y, orbitStart: d.orbitStart, orbitPre: d.orbitPre,
          orbitPeriod: d.orbitPeriod, focusX: (d.x - v.centerX) / v.span, focusY: (d.y - v.centerY) / v.span}
      }
    }
    return {mode: "dissolve", dissolve: true, scale: 3, turn: 0, phase: 0, steps: 8, entry: 0, depth: 0,
      reference: false, x: 0, y: 0, orbitStart: 0, orbitPre: 0, orbitPeriod: 1, focusX: v.focusX, focusY: v.focusY}
  }

  function numberSetting(key, fallback, minimum, maximum) {
    const value = settings[key]
    return typeof value === "number" && isFinite(value)
      ? Math.max(minimum, Math.min(maximum, value)) : fallback
  }
  function readArtworkPalette(raw) {
    const colors = {}
    const lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; ++i) {
      const match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) colors[match[1]] = match[2]
      const mode = lines[i].match(/^\s*mode\s*=\s*["']?(light|dark)/)
      if (mode) colors.mode = mode[1]
    }
    artworkMode = colors.mode || ""
    delete colors.mode
    artworkPalette = colors
  }
  function readSettings(raw) {
    try {
      const entries = JSON.parse(raw).plugins || []
      for (let i = 0; i < entries.length; ++i) {
        if (entries[i].id === "ric.background") {
          settings = entries[i]
          entryLoaded = true
          if (Object.keys(settings).length > 1) backUpSettings()
          else restoreSettings()
          return
        }
      }
      settings = ({})
      entryLoaded = false
    } catch (error) { console.warn("Filigree settings: " + error) }
  }
  // Switching the standard wallpaper back on (`omarchy-fractal off`, or
  // choosing a photo) removes this plugin's shell.json entry, settings and
  // all, and switching Filigree on again adds a bare one. Keep a copy of the
  // settings in the state directory and bring it back into a bare entry.
  property bool entryLoaded: false
  property var savedSettings: null
  property string savedText: ""
  function backUpSettings() {
    const text = JSON.stringify(settings)
    if (text === savedText) return
    savedText = text
    savedSettings = settings
    settingsBackup.setText(text + "\n")
  }
  function restoreSettings() {
    if (!entryLoaded || !shell || Object.keys(settings).length > 1) return
    if (!savedSettings || typeof savedSettings !== "object" || Array.isArray(savedSettings)) return
    const restored = Object.assign({}, savedSettings, {id: "ric.background"})
    if (Object.keys(restored).length <= 1) return
    shell.updateEntryInline("ric.background", restored)
    settings = restored
  }
  function configure(raw) {
    const ranges = {
      motion: [0, 1], speed: [0.1, 8], intensity: [0.1, 1.5],
      zoom: [0, 3], colorCycle: [0, 1], fps: [1, 30], wire: [0.5, 2], detail: [1, 4], maxDimension: [960, 3840], idlePause: [30, 3600],
      juliaReal: [-2, 2], juliaImag: [-2, 2],
      centerX: [-3, 3], centerY: [-3, 3], span: [0.002, 5], iterations: [80, 5000],
      focusX: [-1, 1], focusY: [-1, 1],
      density: [0.2, 2.5], colorMode: [0, 3]
    }
    const integerKeys = ["fps", "maxDimension", "idlePause", "iterations", "colorMode"]
    try {
      const next = JSON.parse(raw)
      if (!next || typeof next !== "object" || Array.isArray(next)) throw "expected an object"
      let presetName = null
      let equation = null
      const direct = {}
      for (const key in next) {
        const value = next[key]
        if (key === "preset") {
          if (typeof value !== "string" || !(value in presets)) throw "unknown preset: " + value
          presetName = value
        } else if (key === "equation") {
          if (typeof value !== "string" || !value.trim() || value.length > 512)
            throw "equation must be a non-empty string of at most 512 characters"
          equation = value.trim()
        } else if (key === "paused" || key === "julia") {
          if (typeof value !== "boolean") throw key + " must be true or false"
          direct[key] = value
        } else if (Object.prototype.hasOwnProperty.call(ranges, key)) {
          if (typeof value !== "number" || !isFinite(value)
            || value < ranges[key][0] || value > ranges[key][1])
            throw "invalid value for " + key
          if (integerKeys.indexOf(key) >= 0 && Math.floor(value) !== value)
            throw key + " must be an integer"
          direct[key] = value
        } else {
          throw "unknown setting: " + key
        }
      }
      if (!shell) throw "shell settings are unavailable"
      let merged = Object.assign({}, settings)
      if (presetName) {
        merged = Object.assign({}, merged, presets[presetName])
        merged.preset = presetName
      }
      for (const key in direct) merged[key] = direct[key]
      if (equation) merged.equation = equation
      shell.updateEntryInline("ric.background", merged)
      settings = merged
      // onSettingsChanged -> syncEquationShader() re-bakes the new equation
      // (presets and explicit equations alike) without blocking this reply.
      return statusJson()
    } catch (error) { return JSON.stringify({error: String(error)}) }
  }
  function statusJson() {
    const displays = []
    for (let i = 0; i < desktops.instances.length; ++i) {
      const panel = desktops.instances[i]
      displays.push({screen: panel.screen.name, width: panel.width, height: panel.height,
        animating: panel.fractal.animationRunning, frameRate: panel.fractal.frameRate, pauseReason: panel.pauseReason,
        ready: panel.fractal.ready, shaderFailed: panel.fractal.shaderFailed})
    }
    return JSON.stringify({name: "Filigree", version: "3.4.0", paused: paused, idle: idleMonitor.isIdle,
      motion: motion, speed: speed, intensity: intensity, zoom: zoom, colorCycle: colorCycle,
      zoomLoop: zoom > 0 ? zoomLoop.mode : "off",
      fps: fps, wire: wire, detail: detail, maxDimension: maxDimension,
      idlePause: idlePause, preset: preset, equation: equation, julia: julia,
      juliaReal: juliaReal, juliaImag: juliaImag, centerX: centerX, centerY: centerY,
      span: span, focusX: focusX, focusY: focusY, lightTheme: lightTheme,
      iterations: iterations, colorMode: colorMode, density: density,
      equationBusy: equationBusy, equationError: equationError,
      displays: displays, capturePath: capturePath, captureError: captureError})
  }
  function applyEquation(expression) {
    const eq = String(expression || "").trim()
    if (!eq) return "error: enter an equation, for example z^2 + c"
    if (eq.length > 512) return "error: keep equations to 512 characters or fewer"
    if (equationBusy) return "error: another equation is still compiling"
    startCompile(eq)
    return "compiling: " + eq
  }
  function startCompile(expression) {
    pendingCompile = expression
    equationBusy = true
    equationError = ""
    compileWatchdog.restart()
    compilerProc.command = [
      "python3", pluginDir + "/equation-compiler.py",
      "--expression=" + expression,
      "--template", pluginDir + "/fractal-template.glsl",
      "--cache-dir", equationCacheDir
    ]
    compilerProc.running = true
  }
  function handleCompileResult(output) {
    if (!equationBusy) return
    equationBusy = false
    let data = null
    try { data = JSON.parse(String(output || "").trim()) } catch (error) { data = null }
    if (!data || data.ok !== true || !data.shaderPath) {
      equationError = (data && data.error) ? String(data.error)
        : "The equation compiler returned an unreadable result"
      return
    }
    equationError = ""
    const eq = String(data.equation || pendingCompile || "").trim()
    compiledEquation = eq
    if (eq === "z*z+c") {
      usingCustomShader = false
      activeShaderUrl = builtinShaderUrl
    } else {
      activeShaderUrl = Qt.url("file://" + String(data.shaderPath))
      usingCustomShader = true
    }
    if (shell) {
      const merged = Object.assign({}, settings, {equation: eq})
      shell.updateEntryInline("ric.background", merged)
      settings = merged
    }
  }
  // Keep the active shader in step with settings.equation: startup restore,
  // preset changes, explicit equations and hand-edits of shell.json all end
  // up here. Compile results are hash-cached, so repeats are a fast no-op.
  function syncEquationShader() {
    if (equationBusy) return
    const stored = String(settings.equation || "").trim()
    if (!stored || stored === "z*z+c") {
      if (usingCustomShader || compiledEquation !== "z*z+c") {
        usingCustomShader = false
        activeShaderUrl = builtinShaderUrl
        compiledEquation = "z*z+c"
      }
      equationError = ""
      return
    }
    if (stored === compiledEquation) return
    startCompile(stored)
  }
  onSettingsChanged: root.syncEquationShader()
  function capture(path) {
    return captureForScreen("", path)
  }
  function captureForScreen(screenName, path) {
    if (!path.startsWith("/") || !path.toLowerCase().endsWith(".png")) return "error: use an absolute .png path"
    let best = null
    for (let i = 0; i < desktops.instances.length; ++i) {
      const candidate = desktops.instances[i]
      if (screenName && candidate.screen.name !== screenName) continue
      if (!best || candidate.width * candidate.height > best.width * best.height) best = candidate
    }
    if (!best) return "error: no display"
    capturePath = ""
    captureError = ""
    const queued = best.fractal.grabToImage(function(result) {
      if (result.saveToFile(path)) root.capturePath = path
      else root.captureError = "Could not save " + path
    })
    return queued ? "requested" : "error: renderer could not capture"
  }

  FileView {
    id: paletteFile
    path: root.stateHome + "/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.readArtworkPalette(text())
    onFileChanged: reload()
  }
  Connections {
    target: Color
    function onAccentChanged() { paletteFile.reload() }
  }
  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.readSettings(text())
    onFileChanged: reload()
  }
  FileView {
    id: settingsBackup
    path: root.stateHome + "/omarchy/filigree-settings.json"
    printErrors: false
    onLoaded: {
      try {
        root.savedText = text().trim()
        root.savedSettings = JSON.parse(root.savedText)
      } catch (error) { root.savedSettings = null }
      if (root.entryLoaded && Object.keys(root.settings).length > 1) root.backUpSettings()
      else root.restoreSettings()
    }
  }
  IdleMonitor {
    id: idleMonitor
    timeout: root.idlePause
    respectInhibitors: false
  }
  // Refresh lock/DPMS state gently using existing compositor IPC; no process.
  Timer {
    interval: 5000
    running: !idleMonitor.isIdle
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshMonitors()
  }
  Connections {
    target: idleMonitor
    function onIsIdleChanged() { if (!idleMonitor.isIdle) Hyprland.refreshMonitors() }
  }
  // The equation compiler: a stdlib-only Python script that validates the
  // expression against a whitelist, bakes it with qsb into the hash-addressed
  // cache and publishes atomically.
  Process {
    id: compilerProc
    stdout: StdioCollector {
      onStreamFinished: root.handleCompileResult(text)
    }
  }
  Timer {
    id: compileWatchdog
    interval: 45000
    onTriggered: {
      if (!root.equationBusy) return
      compilerProc.running = false
      root.equationBusy = false
      root.equationError = "Equation compilation took too long; try a simpler expression"
    }
  }
  Process {
    id: restorePhoto
    command: ["omarchy", "plugin", "enable", "omarchy.background"]
  }
  Timer {
    id: restorePhotoSoon
    interval: 80
    onTriggered: restorePhoto.running = true
  }
  IpcHandler {
    target: "fractal"
    function pause(): string { return root.configure('{"paused":true}') }
    function resume(): string { return root.configure('{"paused":false}') }
    function toggle(): string { return root.configure(JSON.stringify({paused: !root.paused})) }
    function configure(options: string): string { return root.configure(options) }
    function applyEquation(expression: string): string { return root.applyEquation(expression) }
    function status(): string { return root.statusJson() }
    function settings(): string {
      // The studio is this plugin's panel entry point; summon it through the
      // shell so the panel loader owns the window's lifecycle.
      if (!shell || typeof shell.summon !== "function") return "error: shell API unavailable"
      shell.summon("ric.background", "")
      return "opened"
    }
    function capture(path: string): string { return root.capture(path) }
    function captureScreen(screen: string, path: string): string { return root.captureForScreen(screen, path) }
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    readArtworkPalette(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
      restorePhotoSoon.restart()
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
      restorePhotoSoon.restart()
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: {
    refreshBackground()
    syncEquationShader()
  }

  Variants {
    id: desktops
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      readonly property alias fractal: artwork
      readonly property var monitor: Hyprland.monitorFor(screen)
      readonly property bool covered: !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)
      readonly property bool sleeping: !!(monitor && monitor.lastIpcObject && monitor.lastIpcObject.dpmsStatus === false)
      readonly property bool locked: !!(monitor && monitor.lastIpcObject && monitor.lastIpcObject.solitaryBlockedBy
        && monitor.lastIpcObject.solitaryBlockedBy.indexOf("LOCK") >= 0)
      readonly property bool remapping: remapGuard.remapping
      // First matching reason wins; mirrors the `playing` expression below.
      readonly property string pauseReason: {
        if (root.paused) return "paused"
        if (idleMonitor.isIdle) return "idle"
        if (sleeping) return "sleeping"
        if (locked) return "locked"
        if (covered) return "fullscreen"
        if (remapping) return "remapping"
        if (root.motion <= 0 && root.zoom <= 0 && root.colorCycle <= 0) return "motion-zero"
        if (artwork.shaderFailed) return "shader-error"
        return ""
      }

      screen: modelData
      visible: !remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // The theme photo stays loaded (its transitions still drive theme
      // changes) but is only drawn while the engraving is not on screen;
      // drawing a hidden 4K photo every frame is expensive when the desktop
      // is rendered in software.
      readonly property bool photoVisible: !artwork.ready || artwork.shaderFailed

      Image {
        id: base
        anchors.fill: parent
        visible: panel.photoVisible
        source: root.imageUrl(root.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: panel.photoVisible && root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: panel.photoVisible && root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: panel.photoVisible && root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: panel.photoVisible

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      Fractal {
        id: artwork
        anchors.fill: parent
        visible: !shaderFailed
        backgroundColor: Color.background
        accentColor: Color.accent
        foregroundColor: Color.foreground
        secondaryColor: root.secondaryColor
        tertiaryColor: root.tertiaryColor
        goldColor: root.goldColor
        extraColors: root.extraColors
        lightTheme: root.lightTheme
        intensity: root.intensity
        motion: root.motion
        speed: root.speed
        zoom: root.zoom
        colorCycle: root.colorCycle
        loopScale: root.zoomLoop.scale
        loopTurn: root.zoomLoop.turn
        loopPhase: root.zoomLoop.phase
        loopSteps: root.zoomLoop.steps
        loopEntry: root.zoomLoop.entry
        dissolve: root.zoomLoop.dissolve
        reference: root.zoomLoop.reference
        referenceX: root.zoomLoop.x
        referenceY: root.zoomLoop.y
        orbitStart: root.zoomLoop.orbitStart
        orbitPre: root.zoomLoop.orbitPre
        orbitPeriod: root.zoomLoop.orbitPeriod
        centerX: root.centerX
        centerY: root.centerY
        span: root.span
        focusX: root.zoomLoop.focusX
        focusY: root.zoomLoop.focusY
        julia: root.julia
        juliaReal: root.juliaReal
        juliaImag: root.juliaImag
        iterations: root.iterations
        colorMode: root.colorMode
        density: root.density
        customEquation: root.usingCustomShader
        shaderUrl: root.activeShaderUrl
        fps: root.fps
        wireWidth: 0.002 * root.wire
        detail: root.detail
        maxDimension: root.maxDimension
        // While a setting is being dragged, the desktop stretches what it
        // has and engraves again once the changes pause.
        settleDelay: 300
        playing: !root.paused && !idleMonitor.isIdle && !panel.covered
          && !panel.sleeping && !panel.locked && !panel.remapping
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.openSelector()
        }
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else if (mouse.button === Qt.LeftButton) root.configure(JSON.stringify({paused: !root.paused}))
          mouse.accepted = true
        }
      }
    }
  }
}