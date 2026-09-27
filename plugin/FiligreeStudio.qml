import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui as Ui
import "navigation.js" as Nav

// This window belongs to the wallpaper service. Closing it never stops the
// wallpaper; its preview clock only runs while the window is visible.
Item {
  id: root
  property var shell: null
  property var service: null
  property var liveStatus: ({displays: []})
  property var pending: ({})
  property var saved: ({})
  property string message: ""
  property bool messageIsError: false
  property int page: 0
  // The preview is also a map of the plane: dragging, zooming and aiming
  // write to the preview at once and to the desktop when they pause.
  property bool dragging: false
  property bool aimMode: false
  property bool sliding: false
  property var displayList: []
  property string displayKey: ""
  readonly property bool navigating: dragging || navIdle.running
  // Exploring holds the preview's dive at the composition's own framing.
  readonly property bool exploring: navigating || aimMode || pad.lingering || pad.keyboardFocused
  readonly property bool isOpen: window.visible
  // Panel host contract: the shell reads `opened` and drives open(payload) /
  // close() through its panel loader.
  readonly property bool opened: window.visible
  readonly property color ink: Color.foreground
  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.63)
  readonly property color line: Qt.rgba(ink.r, ink.g, ink.b, 0.13)
  readonly property color wash: Qt.rgba(ink.r, ink.g, ink.b, 0.035)
  readonly property var defaults: ({
    speed: 1.0, motion: 0.55, zoom: 1, colorCycle: 0, paused: false, preset: "filigree",
    equation: "z*z+c", julia: false, juliaReal: -0.8, juliaImag: 0.156,
    centerX: -0.10469636, centerY: 0.95868651, span: 0.03, focusX: 0.12, focusY: -0.08,
    iterations: 1500, colorMode: 0, intensity: 1.0, density: 1.0, wire: 1.0, detail: 2,
    fps: 30, idlePause: 120
  })

  function value(key) {
    if (pending[key] !== undefined) return pending[key]
    if (service && service.settings[key] !== undefined) return service.settings[key]
    if (service && service[key] !== undefined && key !== "equation") return service[key]
    if (key === "equation" && service && service.equation !== undefined) return service.equation
    return defaults[key]
  }
  // The view as it stands, unsaved changes included.
  readonly property var view: ({centerX: Number(value("centerX")), centerY: Number(value("centerY")),
    span: Number(value("span")), focusX: Number(value("focusX")), focusY: Number(value("focusY"))})
  readonly property var loop: service && typeof service.loopFor === "function"
    ? service.loopFor({centerX: view.centerX, centerY: view.centerY, span: view.span, focusX: view.focusX,
      focusY: view.focusY, julia: !!value("julia"), juliaReal: Number(value("juliaReal")), juliaImag: Number(value("juliaImag"))})
    : ({mode: "dissolve", dissolve: true, scale: 3, turn: 0, phase: 0, steps: 8, entry: 0, depth: 0, reference: false,
      x: 0, y: 0, orbitStart: 0, orbitPre: 0, orbitPeriod: 1, focusX: view.focusX, focusY: view.focusY})
  // Where the dive goes: exactly into its point, during an endless dive.
  readonly property var target: loop.mode === "dive" ? ({x: loop.x, y: loop.y})
    : ({x: view.centerX + view.focusX * view.span, y: view.centerY + view.focusY * view.span})
  // The dive target as chosen, kept while the view is moved about. The saved
  // focus reaches a span from the centre at most and waits at that edge while
  // the chosen point is further off, so that moving back finds it exactly
  // (and an endless dive resumes). It holds only for the view it was left at.
  property var pin: null
  function sameView(a, b) {
    return !!a && !!b && a.centerX === b.centerX && a.centerY === b.centerY && a.span === b.span
      && a.focusX === b.focusX && a.focusY === b.focusY
  }
  readonly property var anchor: pin && sameView(pin.view, view) ? ({x: pin.x, y: pin.y}) : target
  readonly property var divePoints: service ? Nav.pointsFor(service.divePoints || [], !!value("julia"),
    Number(value("juliaReal")), Number(value("juliaImag")), !!service.usingCustomShader) : []
  // The preview shows this much more of the plane than a span, so that every
  // display's view fits inside it.
  readonly property real frameScale: Nav.framing(displayList, preview.width, preview.height)

  function snapshot() {
    var result = {}
    for (var key in defaults) result[key] = value(key)
    return result
  }
  function refreshStatus() {
    if (!service) return
    try { liveStatus = JSON.parse(service.statusJson()) }
    catch (error) { showMessage(String(error), true); return }
    const displays = (liveStatus.displays || []).map(d => ({screen: String(d.screen || ""),
      width: Number(d.width) || 0, height: Number(d.height) || 0})).filter(d => d.width > 0 && d.height > 0)
    const key = JSON.stringify(displays)
    if (key !== displayKey) {
      displayKey = key
      displayList = displays
    }
  }
  function bindService() {
    if (service) return
    if (shell && typeof shell.serviceFor === "function") {
      const found = shell.serviceFor("ric.background")
      if (found) service = found
    }
  }
  // The shell injects `service` on load, but the panel can mount before the
  // wallpaper service is up; retry briefly so an early summon still works.
  function open(payload) {
    bindService()
    if (!window.visible) {
      saved = snapshot()
      message = ""
      equationInput.text = String(value("equation"))
      fitToMonitor()
    }
    refreshStatus()
    window.visible = true
    Qt.callLater(root.releaseFocus)
  }
  // Sizes the studio for the monitor Hyprland will open it on, the focused
  // one: its design size where that fits, less on a small or portrait screen.
  // Hyprland names the focused monitor a moment after the shell starts; until
  // then the studio is sized to fit every screen.
  function fitToMonitor() {
    const monitor = Hyprland.focusedMonitor
    const name = monitor ? String(monitor.name || "") : ""
    const screens = Quickshell.screens || []
    let known = false
    for (let i = 0; i < screens.length; ++i) if (screens[i].name === name) known = true
    let width = 1160, height = 780
    for (let i = 0; i < screens.length; ++i) {
      if (known && screens[i].name !== name) continue
      width = Math.min(width, screens[i].width - 48)
      height = Math.min(height, screens[i].height - 96)
    }
    window.fitWidth = Math.max(880, width)
    window.implicitHeight = Math.max(660, height)
  }
  function close() {
    aimMode = false
    flush()
    window.visible = false
  }
  // Focus given to the window scope would go straight back to the field that
  // held it, so it goes to a plain item instead.
  function releaseFocus() { focusSink.forceActiveFocus() }
  function showMessage(text, error) {
    message = text
    messageIsError = !!error
  }
  // A note about the view, kept on show for a while over "Saved".
  function notify(text) {
    showMessage(text, false)
    noticeHold.restart()
  }
  function apply(patch) {
    if (!service) return false
    try {
      var result = JSON.parse(service.configure(JSON.stringify(patch)))
      if (result.error) { showMessage(result.error, true); return false }
      liveStatus = result
      if (!noticeHold.running) showMessage("Saved automatically", false)
      return true
    } catch (error) { showMessage(String(error), true); return false }
  }
  function queue(key, next) {
    var patch = {}
    patch[key] = next
    pending = Object.assign({}, pending, patch)
    writeSoon.restart()
  }
  function flush() {
    writeSoon.stop()
    if (Object.keys(pending).length === 0) return
    var patch = pending
    pending = ({})
    apply(patch)
  }
  function change(key, next) {
    flush()
    var patch = {}; patch[key] = next
    apply(patch)
  }
  // Adds a view to the unsaved changes, pinning the dive target to `keep`
  // (a point of the plane), and says so if an endless dive ends or resumes.
  function stage(patch, keep) {
    const wasDive = loop.mode === "dive"
    const next = Object.assign({}, pending)
    for (const key in patch) if (key !== "kept" && key !== "point") next[key] = patch[key]
    pending = next
    pin = keep ? {x: keep.x, y: keep.y, view: view} : null
    if (!keep) return
    if (wasDive && loop.mode !== "dive") notify("The endless dive’s point is out of reach; move back toward it to resume")
    else if (!wasDive && loop.mode === "dive") notify("Back on the endless dive")
  }
  function navigate(patch, now, keep) {
    stage(patch, keep)
    navIdle.restart()
    if (now) flush()
    else navCommit.restart()
  }
  function panBy(dx, dy) {
    const a = anchor
    navigate(Nav.shifted(view, a, frameScale, preview.width, preview.height, dx, dy), false, a)
  }
  function dragTo(grab, dx, dy) {
    stage(Nav.shifted(grab.view, grab.anchor, frameScale, preview.width, preview.height, -dx, -dy), grab.anchor)
    navIdle.restart()
  }
  // Zooms in by f (below 1 zooms out) about a point of the preview.
  function zoomBy(f, px, py) {
    if (px === undefined) { px = preview.width / 2; py = preview.height / 2 }
    const a = anchor
    const next = Nav.zoomedAt(view, a, frameScale, preview.width, preview.height, px, py, f)
    if (next.span === view.span) {
      notify(f > 1 ? "That’s as deep as the engraving goes" : "That’s the widest view")
      return
    }
    navigate(next, false, a)
  }
  function aimAt(px, py) {
    const hit = Nav.aimed(view, frameScale, preview.width, preview.height, px, py, divePoints, 14)
    navigate({focusX: hit.focusX, focusY: hit.focusY}, true, {x: hit.x, y: hit.y})
    const diving = Number(value("zoom")) > 0
    notify(hit.point ? "Aimed at an endless dive" + (diving ? "" : " · raise Zoom on the Motion page to dive")
      : hit.kept ? (diving ? "The view now dives here" : "Focus set · raise Zoom on the Motion page to dive")
      : "The dive goes as near that point as this view allows; move toward it to reach it")
  }
  function resetView() {
    const p = service && service.presets ? service.presets[String(value("preset"))] : null
    if (!p) return
    navigate({centerX: p.centerX, centerY: p.centerY, span: p.span, focusX: p.focusX, focusY: p.focusY}, true)
  }
  // A typed centre or a new field of view moves the view as the map does.
  function setView(cx, cy, span, live) {
    const a = anchor
    stage(Nav.moved(a, cx, cy, span), a)
    if (live) writeSoon.restart()
    else flush()
  }
  function formatNumber(v) {
    return isFinite(v) ? String(Number(Number(v).toPrecision(10))) : ""
  }
  function readout() {
    const v = view
    const digits = Math.max(3, Math.min(10, Math.ceil(-Math.log(v.span) / Math.LN10) + 3))
    const minus = t => t.replace("-", "−")
    const dive = Number(value("zoom")) > 0
      ? "   ·   " + (loop.mode === "dive" ? "∞ endless dive" : "dives 3× and returns") : ""
    return minus(v.centerX.toFixed(digits)) + (v.centerY < 0 ? " − " : " + ") + Math.abs(v.centerY).toFixed(digits)
      + "i   ·   field " + v.span.toPrecision(3) + dive
  }
  function setEquation(expression) {
    flush()
    var result = String(service.applyEquation(expression))
    if (result.toLowerCase().indexOf("error") === 0) showMessage(result, true)
    else showMessage("Compiling equation…", false)
  }
  function restore(values) {
    writeSoon.stop()
    pending = ({})
    var patch = Object.assign({}, values)
    var expression = patch.equation
    delete patch.equation
    if (apply(patch) && expression !== undefined && expression !== value("equation"))
      setEquation(expression)
    equationInput.text = String(expression || value("equation"))
  }
  function reason(display) {
    if (display.animating) return "Animating"
    var reason = String(display.pauseReason || "")
    var names = {paused: "Paused by you", idle: "Paused while idle", fullscreen: "Paused behind fullscreen",
      covered: "Paused behind fullscreen", sleeping: "Display asleep", locked: "Screen locked",
      remapping: "Display changing", motion: "Motion is set to zero", "motion-zero": "Motion is set to zero",
      "shader-error": "Shader needs attention"}
    if (names[reason]) return names[reason]
    if (reason) return reason.charAt(0).toUpperCase() + reason.slice(1)
    if (value("paused")) return "Paused by you"
    if (Number(value("motion")) === 0 && Number(value("zoom")) === 0 && Number(value("colorCycle")) === 0) return "Motion is set to zero"
    if (liveStatus.idle) return "Paused while idle"
    return "Paused"
  }
  function presetName() {
    var names = {filigree: "Filigree", seahorse: "Seahorse valley", julia: "Julia lace", mandelbrot: "Mandelbrot atlas", trinity: "Trinity"}
    return names[String(value("preset"))] || ""
  }
  // A preset's name while its framing stands; once explored, the view is
  // the user's own.
  function titleForPreset() {
    const name = presetName()
    const p = service && service.presets ? service.presets[String(value("preset"))] : null
    if (!name || !p) return "Your composition"
    // Differences too small to see do not count: a fraction of a pixel, or a
    // focus the dive would snap to the same point from.
    const span = p.span !== undefined ? p.span : view.span
    const tolerance = {centerX: span * 1e-4, centerY: span * 1e-4, span: span * 1e-4,
      focusX: 2e-3, focusY: 2e-3, juliaReal: 1e-9, juliaImag: 1e-9}
    let own = (p.julia !== undefined && !!value("julia") !== p.julia)
      || (p.equation !== undefined && String(value("equation")) !== p.equation)
    for (const key in tolerance) {
      const want = p[key]
      if (want !== undefined && Math.abs(Number(value(key)) - want) > tolerance[key]) own = true
    }
    return own ? "Your composition · from " + name : name
  }

  Timer { id: writeSoon; interval: 180; onTriggered: root.flush() }
  Timer { id: navCommit; interval: 400; onTriggered: if (!root.dragging) root.flush() }
  Timer { id: navIdle; interval: 1200 }
  Timer { id: noticeHold; interval: 2500 }
  Timer { interval: 1000; running: window.visible; repeat: true; onTriggered: root.refreshStatus() }
  Timer {
    interval: 400
    running: !root.service
    repeat: true
    onTriggered: {
      root.bindService()
      if (root.service) stop()
    }
  }
  Component.onCompleted: root.bindService()
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onEquationBusyChanged() {
      if (root.service.equationBusy) return
      if (root.service.equationError) root.showMessage(root.service.equationError, true)
      else {
        root.showMessage("Equation applied", false)
        equationInput.text = String(root.value("equation"))
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.ink
    font.family: Style.font.family
    font.pixelSize: 12
  }
  component Note: Label {
    color: root.muted
    font.pixelSize: 11
    wrapMode: Text.WordWrap
    lineHeight: 1.35
    Layout.fillWidth: true
  }
  component Section: ColumnLayout {
    property string title
    property string detail: ""
    spacing: 6
    Layout.fillWidth: true
    Label { text: parent.title; font.pixelSize: 19; font.weight: Font.Medium }
    Note { text: parent.detail; visible: text.length > 0 }
  }
  component Rule: Rectangle {
    color: root.line
    implicitHeight: 1
    Layout.fillWidth: true
  }
  component Action: Ui.Button {
    focusable: true
    bordered: true
    horizontalPadding: 14
    verticalPadding: 9
    fontSize: 12
    foreground: root.ink
    opacity: enabled ? 1 : 0.45
  }
  component TuningSlider: ColumnLayout {
    id: sliderRow
    property string label
    property string setting
    property real minimum: 0
    property real maximum: 1
    property real step: 0.01
    property int decimals: 2
    property string suffix: ""
    property real displayScale: 1
    property string hint: ""
    property bool logarithmic: false
    // Changing it engraves the plate again: while dragged, the preview
    // engraves quick drafts.
    property bool rebakes: false
    // How a moved value is written, if not simply as the setting.
    property var write: null
    readonly property real current: Number(root.value(setting))
    spacing: 4
    Layout.fillWidth: true
    RowLayout {
      Layout.fillWidth: true
      Label { text: sliderRow.label; Layout.fillWidth: true }
      Label {
        text: (sliderRow.current * sliderRow.displayScale).toFixed(sliderRow.decimals) + sliderRow.suffix
        color: Color.accent
        font.pixelSize: 11
      }
    }
    QQC.Slider {
      id: slider
      Layout.fillWidth: true
      implicitHeight: 24
      from: sliderRow.logarithmic ? Math.log(sliderRow.minimum) : sliderRow.minimum
      to: sliderRow.logarithmic ? Math.log(sliderRow.maximum) : sliderRow.maximum
      stepSize: sliderRow.logarithmic ? 0 : sliderRow.step
      value: sliderRow.logarithmic ? Math.log(Math.max(sliderRow.minimum, sliderRow.current)) : sliderRow.current
      Accessible.name: sliderRow.label
      onMoved: {
        const next = sliderRow.logarithmic ? Math.exp(value) : value
        if (sliderRow.write) sliderRow.write(next)
        else root.queue(sliderRow.setting, next)
      }
      onPressedChanged: {
        if (sliderRow.rebakes) root.sliding = pressed
        if (!pressed) root.flush()
      }
      background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: slider.availableWidth
        height: 3
        radius: 2
        color: root.line
        Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: Color.accent }
      }
      handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: 13; height: 13; radius: 7
        color: slider.pressed ? Color.foreground : Color.accent
        border.width: slider.activeFocus ? 2 : 0
        border.color: Color.foreground
      }
    }
    Note { text: sliderRow.hint; visible: text.length > 0; font.pixelSize: 10 }
  }
  // A number typed in is tried out after a pause in typing and kept on Enter
  // or on leaving the field; Escape puts back the value from before typing.
  component NumberInput: ColumnLayout {
    id: numberRow
    property string label
    property string setting
    property real minimum: -100
    property real maximum: 100
    // How a value is written: live while typing, or for good.
    property var submit: function(next, live) {
      if (live) root.queue(numberRow.setting, next)
      else root.change(numberRow.setting, next)
    }
    property bool editing: false
    // The value when typing began, which Escape restores even once a typed
    // number has been tried out.
    property real before: NaN
    readonly property real current: Number(root.value(setting))
    readonly property bool invalid: editing && isNaN(parsed())
    function parsed() {
      const text = field.text.trim().replace(/\u2212/g, "-")
      const next = text.length ? Number(text) : NaN
      return isFinite(next) && next >= minimum && next <= maximum ? next : NaN
    }
    function commit() {
      if (!editing) return
      typing.stop()
      const next = parsed()
      editing = false
      if (isNaN(next)) root.showMessage(label + ": enter a number from " + minimum + " to " + maximum, true)
      else if (next !== current) submit(next, false)
    }
    function revert() {
      typing.stop()
      editing = false
      if (!isNaN(before) && before !== current) submit(before, false)
    }
    spacing: 6
    Layout.fillWidth: true
    Label { text: numberRow.label; color: numberRow.invalid ? Color.urgent : root.muted; font.pixelSize: 10 }
    Ui.TextField {
      id: field
      Layout.fillWidth: true
      implicitWidth: 110
      font.pixelSize: 12
      selectByMouse: true
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      Accessible.name: numberRow.label
      Binding on text {
        when: !numberRow.editing
        value: root.formatNumber(numberRow.current)
        restoreMode: Binding.RestoreNone
      }
      onTextEdited: {
        if (!numberRow.editing) numberRow.before = numberRow.current
        numberRow.editing = true
        typing.restart()
      }
      onAccepted: numberRow.commit()
      onActiveFocusChanged: if (!activeFocus) numberRow.commit()
      Keys.onEscapePressed: function(event) {
        if (!numberRow.editing) { event.accepted = false; return }
        numberRow.revert()
        root.releaseFocus()
      }
    }
    Timer {
      id: typing
      interval: 700
      onTriggered: {
        const next = numberRow.parsed()
        if (!isNaN(next) && next !== numberRow.current) numberRow.submit(next, true)
      }
    }
  }
  // The dropdown writes its own value when picked; binding it back to the
  // setting keeps it true to resets and to picks that fail.
  component Choice: Ui.Dropdown {
    id: choice
    property string current
    value: current
    Layout.fillWidth: true
    foreground: root.ink
    background: Color.background
    popupBorder: Color.accent
    rowHeight: 36
    popupRowHeight: 36
    Connections {
      target: choice
      function onChanged() { choice.value = Qt.binding(function() { return choice.current }) }
    }
  }
  component MapButton: Ui.Button {
    focusable: true
    bordered: true
    width: 30
    height: 30
    horizontalPadding: 0
    verticalPadding: 0
    iconSize: 15
    foreground: root.ink
    background: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Accessible.onPressAction: clicked()
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Filigree · Fractal studio"
    color: Color.background
    // One width, fitted to the monitor at each opening (see fitToMonitor).
    // Hyprland floats a window whose width cannot change at its own size
    // instead of tiling it; the height stays free.
    property int fitWidth: 1160
    implicitWidth: fitWidth
    implicitHeight: 780
    minimumSize: Qt.size(fitWidth, 660)
    maximumSize: Qt.size(fitWidth, 16777215)
    onVisibleChanged: if (!visible) root.flush()

    FocusScope {
      id: content
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: {
        if (root.aimMode) root.aimMode = false
        else root.close()
      }
      Item { id: focusSink; focus: true }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 22

        RowLayout {
          Layout.fillWidth: true
          spacing: 18
          ColumnLayout {
            spacing: 4
            Layout.fillWidth: true
            Text { text: "Filigree"; color: root.ink; font.family: "serif"; font.pixelSize: 40; font.letterSpacing: -1.3 }
            Label { text: "A living study in complex numbers."; color: root.muted; font.pixelSize: 11 }
          }
          Row {
            spacing: 5
            Repeater {
              model: [Color.accent, root.service ? root.service.secondaryColor : Color.accent,
                root.service ? root.service.tertiaryColor : Color.foreground,
                root.service ? root.service.goldColor : Color.accent]
              Rectangle { required property color modelData; width: 9; height: 26; radius: 4; color: modelData }
            }
          }
          Label { text: "THEME\nLINKED"; font.pixelSize: 9; font.letterSpacing: 1.4; lineHeight: 1.4; color: root.muted }
        }

        Rule {}

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 28

          ColumnLayout {
            Layout.preferredWidth: 560
            Layout.maximumWidth: 640
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 13

            Rectangle {
              id: artworkFrame
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 260
              Layout.maximumHeight: 440
              color: Color.background
              border.color: root.line
              border.width: 1
              clip: true

              Fractal {
                id: preview
                anchors.fill: parent
                anchors.margins: 1
                backgroundColor: Color.background
                foregroundColor: Color.foreground
                accentColor: Color.accent
                secondaryColor: root.service ? root.service.secondaryColor : Color.accent
                tertiaryColor: root.service ? root.service.tertiaryColor : Color.foreground
                goldColor: root.service ? root.service.goldColor : Color.accent
                extraColors: root.service ? root.service.extraColors : []
                lightTheme: root.service ? root.service.lightTheme : false
                intensity: Number(root.value("intensity"))
                motion: Number(root.value("motion"))
                speed: Number(root.value("speed"))
                zoom: root.exploring ? 0 : Number(root.value("zoom"))
                colorCycle: Number(root.value("colorCycle"))
                loopScale: root.loop.scale
                loopTurn: root.loop.turn
                loopPhase: root.loop.phase
                loopSteps: root.loop.steps
                loopEntry: Nav.entryFor(root.loop, preview.span)
                dissolve: root.loop.dissolve
                reference: root.loop.reference
                referenceX: root.loop.x
                referenceY: root.loop.y
                orbitStart: root.loop.orbitStart
                orbitPre: root.loop.orbitPre
                orbitPeriod: root.loop.orbitPeriod
                // Wide enough for every display's view; a dive goes exactly
                // into its point, as on the desktop.
                centerX: root.view.centerX
                centerY: root.view.centerY
                span: root.view.span * root.frameScale
                focusX: root.loop.focusX / root.frameScale
                focusY: root.loop.focusY / root.frameScale
                julia: !!root.value("julia")
                juliaReal: Number(root.value("juliaReal"))
                juliaImag: Number(root.value("juliaImag"))
                iterations: Math.round(Number(root.value("iterations")))
                colorMode: Math.round(Number(root.value("colorMode")))
                density: Number(root.value("density"))
                wireWidth: 0.002 * Number(root.value("wire"))
                // In screen pixels like on the desktop; the supersampled
                // preview cache makes the sheen read a touch stronger here.
                detail: Number(root.value("detail"))
                customEquation: root.service ? root.service.usingCustomShader : false
                shaderUrl: root.service && root.service.usingCustomShader
                  ? root.service.activeShaderUrl : Qt.resolvedUrl("fractal.frag.qsb")
                maxDimension: 1000
                // Under the hand, quick drafts at most about ten times a
                // second; the full engraving once the hand rests.
                draft: root.navigating || root.sliding
                bakeInterval: draft ? 90 : 0
                bandTexels: 1000000
                playing: window.visible
              }

              Item {
                id: pad
                anchors.fill: preview
                activeFocusOnTab: true
                // The pointer has rested here (or just left).
                property bool lingering: false
                // Focus came from a click rather than the keyboard.
                property bool mouseFocus: false
                readonly property bool keyboardFocused: activeFocus && !mouseFocus
                readonly property var rects: root.displayList.map(d => Object.assign({name: d.screen},
                  Nav.frameOf(d, pad.width, pad.height, root.frameScale)))
                readonly property var aim: Nav.toPixel(root.view, root.frameScale, pad.width, pad.height, root.target.x, root.target.y)
                onActiveFocusChanged: if (!activeFocus) mouseFocus = false
                Accessible.role: Accessible.Graphic
                Accessible.name: "Preview of " + root.titleForPreset()
                Accessible.description: "Arrow keys move the view, plus and minus zoom, D aims the dive at the middle, 0 returns to the composition's framing."
                Accessible.focusable: true

                Keys.onPressed: function(event) {
                  const fine = (event.modifiers & Qt.ShiftModifier) !== 0
                  const step = Math.min(width, height) * (fine ? 0.02 : 0.1)
                  let handled = true
                  switch (event.key) {
                  case Qt.Key_Left: root.panBy(-step, 0); break
                  case Qt.Key_Right: root.panBy(step, 0); break
                  case Qt.Key_Up: root.panBy(0, -step); break
                  case Qt.Key_Down: root.panBy(0, step); break
                  case Qt.Key_Plus: case Qt.Key_Equal: case Qt.Key_PageUp: root.zoomBy(1.25); break
                  case Qt.Key_Minus: case Qt.Key_Underscore: case Qt.Key_PageDown: root.zoomBy(0.8); break
                  case Qt.Key_0: case Qt.Key_Home: root.resetView(); break
                  case Qt.Key_D: root.aimAt(width / 2, height / 2); break
                  default: handled = false
                  }
                  if (handled) mouseFocus = false
                  event.accepted = handled
                }

                HoverHandler {
                  id: padHover
                  onHoveredChanged: {
                    if (hovered) {
                      linger.stop()
                      if (!pad.lingering) dwell.restart()
                    } else {
                      dwell.stop()
                      if (pad.lingering) linger.restart()
                    }
                  }
                }
                Timer { id: dwell; interval: 350; onTriggered: pad.lingering = true }
                Timer { id: linger; interval: 900; onTriggered: pad.lingering = false }

                // Beyond the displays' views the preview is dimmed; corner
                // marks show each display's view.
                Canvas {
                  id: frames
                  anchors.fill: parent
                  readonly property string signature: JSON.stringify(pad.rects) + root.exploring
                    + Color.background + root.ink
                  onSignatureChanged: requestPaint()
                  function css(c, a) {
                    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
                  }
                  onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const rects = pad.rects
                    if (!rects.length) return
                    ctx.fillStyle = css(Color.background, 0.46)
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.fillStyle = "rgba(0,0,0,1)"
                    for (let i = 0; i < rects.length; ++i) ctx.fillRect(rects[i].x, rects[i].y, rects[i].width, rects[i].height)
                    ctx.globalCompositeOperation = "source-over"
                    ctx.strokeStyle = css(root.ink, root.exploring ? 0.7 : 0.38)
                    ctx.lineWidth = 1
                    const l = 11
                    for (let i = 0; i < rects.length; ++i) {
                      const r = rects[i]
                      const x0 = Math.round(r.x) + 0.5, y0 = Math.round(r.y) + 0.5
                      const x1 = Math.round(r.x + r.width) - 0.5, y1 = Math.round(r.y + r.height) - 0.5
                      ctx.beginPath()
                      ctx.moveTo(x0, y0 + l); ctx.lineTo(x0, y0); ctx.lineTo(x0 + l, y0)
                      ctx.moveTo(x1 - l, y0); ctx.lineTo(x1, y0); ctx.lineTo(x1, y0 + l)
                      ctx.moveTo(x1, y1 - l); ctx.lineTo(x1, y1); ctx.lineTo(x1 - l, y1)
                      ctx.moveTo(x0 + l, y1); ctx.lineTo(x0, y1); ctx.lineTo(x0, y1 - l)
                      ctx.stroke()
                    }
                  }
                }
                Repeater {
                  model: pad.rects
                  Label {
                    required property var modelData
                    x: modelData.x + 7
                    y: modelData.y + 6
                    text: modelData.name
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    color: root.ink
                    opacity: root.exploring ? 0.72 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                  }
                }

                MouseArea {
                  id: padMouse
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  preventStealing: true
                  cursorShape: root.aimMode ? Qt.CrossCursor : root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  // The pointer and view where a drag began.
                  property var grab: null
                  function finish() {
                    grab = null
                    if (!root.dragging) return
                    root.dragging = false
                    navIdle.restart()
                    root.flush()
                  }
                  onPressed: function(mouse) {
                    pad.mouseFocus = true
                    pad.forceActiveFocus()
                    pad.lingering = true
                    grab = mouse.button === Qt.LeftButton && !root.aimMode
                      ? {x: mouse.x, y: mouse.y, view: root.view, anchor: root.anchor} : null
                  }
                  onPositionChanged: function(mouse) {
                    if (!grab) return
                    const dx = mouse.x - grab.x, dy = mouse.y - grab.y
                    if (!root.dragging && Math.abs(dx) + Math.abs(dy) < 4) return
                    root.dragging = true
                    root.dragTo(grab, dx, dy)
                  }
                  onReleased: finish()
                  onCanceled: finish()
                  onClicked: function(mouse) {
                    if (mouse.button !== Qt.RightButton && !root.aimMode) return
                    root.aimMode = false
                    root.aimAt(mouse.x, mouse.y)
                  }
                  onDoubleClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton && !root.aimMode)
                      root.zoomBy((mouse.modifiers & Qt.ShiftModifier) ? 0.5 : 2, mouse.x, mouse.y)
                  }
                  onWheel: function(wheel) {
                    const notches = wheel.angleDelta.y / 120
                    if (notches !== 0) root.zoomBy(Math.pow(1.25, notches), wheel.x, wheel.y)
                  }
                }

                // Points where the dive can go on forever.
                Repeater {
                  model: root.exploring ? root.divePoints : []
                  Rectangle {
                    required property var modelData
                    readonly property var at: Nav.toPixel(root.view, root.frameScale, pad.width, pad.height, modelData.x, modelData.y)
                    x: at.x - width / 2
                    y: at.y - height / 2
                    width: 9
                    height: 9
                    rotation: 45
                    color: root.service ? root.service.goldColor : Color.accent
                    border.width: 1
                    border.color: Color.background
                  }
                }
                // The dive target.
                Item {
                  x: pad.aim.x - width / 2
                  y: pad.aim.y - height / 2
                  width: 26
                  height: 26
                  opacity: root.exploring ? 1 : 0
                  visible: opacity > 0
                  Behavior on opacity { NumberAnimation { duration: 180 } }
                  Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16; radius: 8
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55)
                  }
                  Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    border.width: 1.5
                    border.color: Color.accent
                  }
                  Repeater {
                    model: [[12, 0, 2, 5], [12, 21, 2, 5], [0, 12, 5, 2], [21, 12, 5, 2]]
                    Rectangle {
                      required property var modelData
                      x: modelData[0]; y: modelData[1]; width: modelData[2]; height: modelData[3]
                      color: Color.accent
                    }
                  }
                }

                // The chosen point, while it is beyond the dive's reach.
                Rectangle {
                  readonly property var at: Nav.toPixel(root.view, root.frameScale, pad.width, pad.height, root.anchor.x, root.anchor.y)
                  readonly property bool apart: Math.hypot(at.x - pad.aim.x, at.y - pad.aim.y) > 3
                  x: at.x - width / 2
                  y: at.y - height / 2
                  width: 12; height: 12; radius: 6
                  color: "transparent"
                  border.width: 1.5
                  border.color: Color.accent
                  opacity: root.exploring && apart ? 0.55 : 0
                  visible: opacity > 0
                }
                Rectangle {
                  anchors.left: parent.left; anchors.top: parent.top
                  anchors.margins: 12
                  width: previewBadge.implicitWidth + 18; height: 24
                  radius: 4
                  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)
                  Label {
                    id: previewBadge
                    anchors.centerIn: parent
                    readonly property bool dive: Number(root.value("zoom")) > 0
                    text: root.exploring ? (dive ? "⊕  MAP  ·  DIVE PAUSED" : "⊕  MAP")
                      : (Number(root.value("motion")) > 0 || dive || Number(root.value("colorCycle")) > 0 ? "●  LIVE" : "●  STILL")
                        + (dive ? (root.loop.mode === "dive" ? "  ·  ∞ ENDLESS DIVE" : "  ·  DIVE & RETURN") : "")
                    font.pixelSize: 9
                    font.letterSpacing: 0.8
                  }
                }
                Row {
                  anchors.right: parent.right; anchors.bottom: parent.bottom
                  anchors.margins: 10
                  spacing: 4
                  MapButton { iconText: "+"; tooltipText: "Zoom in  ·  scroll, or +"; onClicked: root.zoomBy(1.5) }
                  MapButton { iconText: "−"; tooltipText: "Zoom out  ·  scroll, or −"; onClicked: root.zoomBy(1 / 1.5) }
                  MapButton {
                    iconText: "⌂"
                    tooltipText: "Back to " + (root.presetName() || "the composition") + "’s framing  ·  0"
                    onClicked: root.resetView()
                  }
                  MapButton {
                    iconText: "◎"
                    selected: root.aimMode
                    tooltipText: "Aim the dive: then click a point  ·  right-click, or D"
                    onClicked: root.aimMode = !root.aimMode
                  }
                }
                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.width: 2
                  border.color: Color.accent
                  visible: pad.keyboardFocused
                }
              }
              Label {
                anchors.centerIn: parent
                visible: preview.shaderFailed
                text: "Preview unavailable"
                color: Color.urgent
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 4
              Label { text: root.titleForPreset(); font.pixelSize: 18; Layout.fillWidth: true; elide: Text.ElideRight }
              Label { text: root.readout(); font.pixelSize: 10; color: Color.accent; Layout.fillWidth: true; elide: Text.ElideRight }
              Note {
                text: root.aimMode ? "Click where the dive should go  ·  Esc cancels"
                  : "Drag to explore  ·  scroll to zoom  ·  right-click to aim the dive"
                    + (root.divePoints.length ? "  ·  a gold ◆ can be followed forever" : "")
                font.pixelSize: 10
                // Always two lines' room, so the preview keeps its size.
                Layout.preferredHeight: Math.max(implicitHeight, 2 * implicitHeight / Math.max(1, lineCount))
                verticalAlignment: Text.AlignTop
              }
            }

            Rule {}

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 9
              Label { text: "ON YOUR DESKTOP"; font.pixelSize: 9; font.letterSpacing: 1.6; color: root.muted }
              Repeater {
                model: root.liveStatus.displays || []
                RowLayout {
                  required property var modelData
                  Layout.fillWidth: true
                  spacing: 8
                  Rectangle { width: 5; height: 5; radius: 3; color: modelData.animating ? Color.accent : root.muted }
                  Label { text: modelData.screen || "Display"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                  Label { text: root.reason(modelData); font.pixelSize: 10; color: modelData.animating ? Color.accent : root.muted }
                }
              }
              Note { text: "The corner marks in the preview show each display’s view. Desktop playback follows the status above."; font.pixelSize: 10 }
            }
          }

          Rectangle { Layout.fillHeight: true; width: 1; color: root.line }

          ColumnLayout {
            Layout.preferredWidth: 470
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 17

            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Repeater {
                model: ["Motion", "Fractal", "Color"]
                Action {
                  required property string modelData
                  required property int index
                  Layout.fillWidth: true
                  text: modelData
                  selected: root.page === index
                  background: root.page === index ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.09) : "transparent"
                  onClicked: { root.flush(); root.page = index }
                }
              }
            }

            QQC.ScrollView {
              id: controlsScroll
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: availableWidth
              QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
              QQC.ScrollBar.vertical: QQC.ScrollBar {
                policy: QQC.ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; radius: 2; color: root.muted; opacity: parent.active ? 0.7 : 0.25 }
              }

              ColumnLayout {
                width: controlsScroll.availableWidth - 12
                spacing: 22

                ColumnLayout {
                  visible: root.page === 0
                  Layout.fillWidth: true
                  spacing: 22
                  Section { title: "Almost still. Always alive."; detail: "Two theme-coloured lights circle the engraved plate, so highlights sweep slowly across every cut while a faint tide of light runs through the lace. The view can also sink slowly into the fractal, and the palette can flow along the grooves." }
                  Action {
                    Layout.fillWidth: true
                    text: root.value("paused") ? "▶  Resume desktop animation" : "Ⅱ  Pause desktop animation"
                    onClicked: root.change("paused", !root.value("paused"))
                  }
                  TuningSlider { label: "Animation speed"; setting: "speed"; minimum: 0.1; maximum: 8; step: 0.1; decimals: 1; suffix: "×"; hint: "Scales every motion. At 1× the lights make one full turn every 90 seconds." }
                  TuningSlider { label: "Motion amplitude"; setting: "motion"; displayScale: 100; decimals: 0; suffix: "%"; hint: "Strength of the tide of light. Zero holds the lights still." }
                  TuningSlider { label: "Zoom"; setting: "zoom"; minimum: 0; maximum: 3; step: 0.1; decimals: 1; suffix: "×"; hint: root.service && root.service.zoomLoop.mode === "dive" ? "An endless dive: this view repeats itself at every scale, so the zoom never has to end. At 1× the view sinks about 2.5× deeper every five minutes." : "The view sinks 3× deeper, then dissolves back to where it began. Filigree, Seahorse valley, Julia lace and the Mandelbrot atlas dive endlessly." }
                  TuningSlider { label: "Color cycle"; setting: "colorCycle"; displayScale: 100; decimals: 0; suffix: "%"; hint: "Tints the grooves with the theme palette, like heat-tinted steel, and lets the colours drift slowly in towards the lace." }
                  Rule {}
                  TuningSlider { label: "Frame rate limit"; setting: "fps"; minimum: 1; maximum: 30; step: 1; decimals: 0; suffix: " fps"; hint: "The wallpaper draws only as often as its motion needs: 10 fps for the lights, up to 15 while diving on a 4K screen. Lower caps save CPU when the desktop is rendered in software." }
                  TuningSlider { label: "Pause after inactivity"; setting: "idlePause"; minimum: 30; maximum: 600; step: 30; decimals: 0; suffix: " s"; hint: "Animation resumes when you return. Fullscreen apps, lock, and sleeping displays also pause it." }
                  Item { implicitHeight: 5 }
                }

                ColumnLayout {
                  visible: root.page === 1
                  Layout.fillWidth: true
                  spacing: 18
                  Section { title: "Choose a world."; detail: "Begin with a composition, then make it yours: drag the preview to travel, scroll to zoom in, and right-click the spot the dive should sink into." }
                  Choice {
                    label: "Composition"
                    current: String(root.value("preset"))
                    options: [{value: "filigree", label: "Filigree"}, {value: "seahorse", label: "Seahorse valley"},
                      {value: "julia", label: "Julia lace"}, {value: "mandelbrot", label: "Mandelbrot atlas"},
                      {value: "trinity", label: "Trinity · z³ + c"}]
                    onChanged: function(value) { root.change("preset", value); equationInput.text = String(root.value("equation")) }
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    Label { text: "Iteration equation  ·  zₙ₊₁ ="; color: root.muted; font.pixelSize: 10 }
                    Ui.TextField {
                      id: equationInput
                      Layout.fillWidth: true
                      text: String(root.value("equation"))
                      selectByMouse: true
                      placeholderText: "z*z+c"
                      font.pixelSize: 13
                      onAccepted: if (!root.service.equationBusy) root.setEquation(text)
                    }
                    RowLayout {
                      Layout.fillWidth: true
                      Note { text: "z is the orbit; c is the complex parameter."; font.pixelSize: 10 }
                      Action {
                        text: root.service && root.service.equationBusy ? "Compiling…" : "Apply equation"
                        enabled: !!root.service && !root.service.equationBusy
                        onClicked: root.setEquation(equationInput.text)
                      }
                    }
                    Note { text: root.service && root.service.equationError ? root.service.equationError : "Use + − * / ^, parentheses, sin, cos, exp, abs, abs2, conj, or complex(r, i)."; color: root.service && root.service.equationError ? Color.urgent : root.muted; font.pixelSize: 10 }
                  }
                  Choice {
                    label: "Parameter plane"
                    current: root.value("julia") ? "julia" : "mandelbrot"
                    options: [{value: "mandelbrot", label: "Mandelbrot · c follows the image"}, {value: "julia", label: "Julia · a constant c"}]
                    onChanged: function(value) { root.change("julia", value === "julia") }
                  }
                  RowLayout {
                    visible: !!root.value("julia")
                    Layout.fillWidth: true
                    spacing: 12
                    NumberInput { label: "Constant · real"; setting: "juliaReal"; minimum: -2; maximum: 2 }
                    NumberInput { label: "Constant · imaginary"; setting: "juliaImag"; minimum: -2; maximum: 2 }
                  }
                  Rule {}
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    NumberInput {
                      label: "Center · real"; setting: "centerX"; minimum: -3; maximum: 3
                      submit: function(next, live) { root.setView(next, root.view.centerY, root.view.span, live) }
                    }
                    NumberInput {
                      label: "Center · imaginary"; setting: "centerY"; minimum: -3; maximum: 3
                      submit: function(next, live) { root.setView(root.view.centerX, next, root.view.span, live) }
                    }
                  }
                  TuningSlider {
                    label: "Field of view"; setting: "span"; minimum: 0.002; maximum: 5; logarithmic: true; decimals: 4; rebakes: true
                    hint: "A smaller field reveals a deeper part of the fractal. Scrolling over the preview zooms too."
                    write: function(next) { root.setView(root.view.centerX, root.view.centerY, next, true) }
                  }
                  TuningSlider { label: "Iteration detail"; setting: "iterations"; minimum: 80; maximum: 5000; step: 50; decimals: 0; rebakes: true; hint: "More iterations resolve finer boundaries. The plate is engraved once, so this never slows the animation." }
                  Item { implicitHeight: 5 }
                }

                ColumnLayout {
                  visible: root.page === 2
                  Layout.fillWidth: true
                  spacing: 23
                  Section { title: "Color, from your theme."; detail: "Every mapping follows Omarchy’s current palette and changes with it instantly. Light themes print the engraving in ink on paper instead of lit metal." }
                  Choice {
                    label: "Color mapping"
                    current: String(root.value("colorMode"))
                    options: [{value: "0", label: "Theme spectrum"}, {value: "1", label: "Iridescent"},
                      {value: "2", label: "Duotone"}, {value: "3", label: "Platinum"}]
                    onChanged: function(value) { root.change("colorMode", Number(value)) }
                  }
                  Note {
                    text: ["A warm key light and a cool fill from your theme, over filigree in the theme’s gold.", "A third light in the theme’s magenta joins the orbit, so every cut shifts hue as the lights turn.",
                      "A restrained study: filigree in the accent colour, lit by the accent and foreground.", "Filigree in the theme’s foreground, like platinum set into the plate."][Number(root.value("colorMode"))] || ""
                  }
                  TuningSlider { label: "Color intensity"; setting: "intensity"; minimum: 0.1; maximum: 1.5; step: 0.05; decimals: 2; suffix: "×"; hint: "Low: a few quiet colours, drawn towards the gold. High: saturated colour, a third light, and more of the theme’s hues in the colour cycle." }
                  TuningSlider { label: "Engraving density"; setting: "density"; minimum: 0.2; maximum: 2.5; step: 0.05; decimals: 2; suffix: "×"; rebakes: true; hint: "Spacing of the engraved grooves. Changing it engraves the plate again." }
                  TuningSlider { label: "Wire weight"; setting: "wire"; minimum: 0.5; maximum: 2; step: 0.05; decimals: 2; suffix: "×"; rebakes: true; hint: "Thickness of the gold filigree. Changing it engraves the plate again." }
                  TuningSlider { label: "Finest detail"; setting: "detail"; minimum: 1; maximum: 4; step: 0.5; decimals: 1; suffix: " px"; hint: "Lace finer than this is lit as a satin sheen instead of glinting, so dense areas shimmer instead of crawling. 1 keeps every glint." }
                  Rule {}
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 11
                    Label { text: "CURRENT PALETTE"; font.pixelSize: 9; font.letterSpacing: 1.5; color: root.muted }
                    RowLayout {
                      Layout.fillWidth: true
                      spacing: 6
                      Repeater {
                        model: [Color.background, Color.accent, root.service ? root.service.secondaryColor : Color.accent,
                          root.service ? root.service.tertiaryColor : Color.foreground,
                          root.service ? root.service.goldColor : Color.accent, Color.foreground]
                        Rectangle {
                          required property color modelData
                          Layout.fillWidth: true
                          implicitHeight: 42
                          radius: 4
                          color: modelData
                          border.color: root.line
                          border.width: 1
                        }
                      }
                    }
                    Note { text: "Background · accent · cyan · magenta · gold · foreground"; font.pixelSize: 10 }
                  }
                  Item { Layout.fillHeight: true; implicitHeight: 5 }
                }
              }
            }
          }
        }

        Rule {}

        RowLayout {
          Layout.fillWidth: true
          spacing: 9
          Action { text: "Reset Filigree"; tooltipText: "Restore this wallpaper’s default composition and controls"; onClicked: root.restore(root.defaults) }
          Action { text: "Revert session"; tooltipText: "Return to the settings from when this window opened"; onClicked: root.restore(root.saved) }
          Label {
            text: root.message || "Changes save automatically"
            color: root.messageIsError ? Color.urgent : root.muted
            font.pixelSize: 10
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
          Action { text: "Done"; selected: true; onClicked: root.close() }
        }
      }
    }
  }
}
