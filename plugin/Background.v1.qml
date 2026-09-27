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
  readonly property color secondaryColor: artworkPalette.cyan || artworkPalette.color6 || Color.accent
  readonly property color tertiaryColor: artworkPalette.magenta || artworkPalette.color5 || Color.foreground
  readonly property color goldColor: artworkPalette.yellow || artworkPalette.color3 || Color.accent
  readonly property bool paused: settings.paused === true
  readonly property real motion: numberSetting("motion", 0.55, 0, 1)
  readonly property real intensity: numberSetting("intensity", 1.0, 0.1, 1.5)
  readonly property int fps: Math.round(numberSetting("fps", 20, 1, 30))
  readonly property int maxDimension: Math.round(numberSetting("maxDimension", 3840, 960, 3840))
  readonly property int idlePause: Math.round(numberSetting("idlePause", 120, 30, 3600))

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
    }
    artworkPalette = colors
  }
  function readSettings(raw) {
    try {
      const entries = JSON.parse(raw).plugins || []
      for (let i = 0; i < entries.length; ++i) {
        if (entries[i].id === "ric.background") { settings = entries[i]; return }
      }
      settings = ({})
    } catch (error) { console.warn("Filigree settings: " + error) }
  }
  function configure(raw) {
    const ranges = {motion: [0, 1], intensity: [0.1, 1.5], fps: [1, 30], maxDimension: [960, 3840], idlePause: [30, 3600]}
    try {
      const next = JSON.parse(raw)
      if (!next || typeof next !== "object" || Array.isArray(next)) throw "expected an object"
      for (const key in next) {
        if (key === "paused") {
          if (typeof next[key] !== "boolean") throw "paused must be true or false"
        } else {
          if (!Object.prototype.hasOwnProperty.call(ranges, key)) throw "unknown setting: " + key
          if (typeof next[key] !== "number" || !isFinite(next[key]) || next[key] < ranges[key][0] || next[key] > ranges[key][1])
            throw "invalid value for " + key
          if (["fps", "maxDimension", "idlePause"].indexOf(key) >= 0 && Math.floor(next[key]) !== next[key])
            throw key + " must be an integer"
        }
      }
      if (!shell) throw "shell settings are unavailable"
      const merged = Object.assign({}, settings, next)
      shell.updateEntryInline("ric.background", merged)
      settings = merged
      return statusJson()
    } catch (error) { return JSON.stringify({error: String(error)}) }
  }
  function statusJson() {
    const displays = []
    for (let i = 0; i < desktops.instances.length; ++i) {
      const panel = desktops.instances[i]
      displays.push({screen: panel.screen.name, width: panel.width, height: panel.height,
        animating: panel.fractal.playing && motion > 0, shaderFailed: panel.fractal.shaderFailed})
    }
    return JSON.stringify({name: "Filigree", paused: paused, idle: idleMonitor.isIdle,
      motion: motion, intensity: intensity, fps: fps, maxDimension: maxDimension,
      idlePause: idlePause, displays: displays, capturePath: capturePath, captureError: captureError})
  }
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
    function status(): string { return root.statusJson() }
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

  Component.onCompleted: refreshBackground()

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

      screen: modelData
      visible: !remapGuard.remapping
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

      Image {
        id: base
        anchors.fill: parent
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
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
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
        layer.enabled: true

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
        intensity: root.intensity
        motion: root.motion
        fps: root.fps
        maxDimension: root.maxDimension
        playing: !root.paused && !idleMonitor.isIdle && !panel.covered
          && !panel.sleeping && !panel.locked && !remapGuard.remapping
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
