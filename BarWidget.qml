import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "core/Schedule.js" as Schedule

// Pixel Shift: an invisible bar widget that slowly walks the bar's edge
// padding and center offset a few pixels back and forth, so the static bar
// pixels of an OLED panel wear evenly instead of burning in.
//
// It draws nothing and takes no space. Wherever it sits in the layout, it
// finds the three things the built-in bar pins to the screen — the left
// section, the right section and the centered module — and nudges them:
//   left/right sections   margin 8 ± edgeTravel  (both move inward together)
//   centered module       center offset ± centerTravel
// On a vertical bar the same happens along the bar's long axis.
BarWidget {
  id: root
  moduleName: "io.github.evindor.pixel-shift"

  implicitWidth: 0
  implicitHeight: 0
  visible: false

  readonly property int intervalSec: clampInt(setting("intervalSec", 180), 10, 3600)
  readonly property int edgeTravel: clampInt(setting("edgeTravel", 2), 0, 8)
  readonly property int edgeStep: clampInt(setting("edgeStep", 2), 1, 4)
  readonly property int centerTravel: clampInt(setting("centerTravel", 1), 0, 4)
  readonly property bool shiftOnWorkspaceSwitch: setting("shiftOnWorkspaceSwitch", true) !== false

  // The distance the bar keeps from the screen edge in the built-in bar; the
  // shift is applied on top of it, so the resting position is unchanged.
  readonly property int edgeBase: Style.space(8)

  property int phase: 0
  readonly property int edgeOffset: Schedule.positionAt(phase, edgeTravel, edgeStep)
  readonly property int centerOffset: Schedule.positionAt(phase, centerTravel, 1)

  // Items this instance has moved, so they can be put back when the plugin
  // is disabled or reloaded: [{ item, prop, edge }].
  property var touched: []

  // Section targets found by the scene-graph fallback, cached between applies,
  // and the flag that folds the edge and center moves of one step into one pass.
  property var targets: []
  property bool applyQueued: false

  function scheduleApply() {
    if (root.applyQueued) return
    root.applyQueued = true
    Qt.callLater(root.runApply)
  }

  function runApply() {
    root.applyQueued = false
    root.apply()
  }

  function clampInt(value, lo, hi) {
    var n = Math.round(Number(value))
    return isFinite(n) ? Math.min(hi, Math.max(lo, n)) : lo
  }

  // ------------------------------------------------------------- schedule

  // One wakeup per step: the timer is re-armed to the next phase boundary.
  // A second of slack keeps Qt's coarse timer from firing just before it.
  Timer {
    id: clock
    onTriggered: root.sync()
  }

  function sync() {
    var now = Date.now()
    var ms = root.intervalSec * 1000
    root.phase = Schedule.phase(Schedule.shared, now, ms)
    clock.interval = Schedule.nextBoundary(Schedule.shared, now, ms) - now + 1000
    clock.restart()
  }

  // A workspace switch redraws part of the bar anyway, which hides a shift
  // far better than a timer firing on a still screen. Take the opportunity
  // when at least a quarter of the interval has passed since the last move.
  // Every instance resyncs, so all monitors step together whichever one
  // advanced the shared clock.
  function maskedShift() {
    var now = Date.now()
    var ms = root.intervalSec * 1000
    if (Schedule.maskedShiftDue(Schedule.shared, now, ms, ms / 4)) Schedule.advance(Schedule.shared, now, ms)
    root.sync()
  }

  Connections {
    target: Hyprland
    enabled: root.shiftOnWorkspaceSwitch
    function onFocusedWorkspaceChanged() { root.maskedShift() }
  }

  onIntervalSecChanged: sync()
  onEdgeOffsetChanged: apply()
  onCenterOffsetChanged: apply()
  onEdgeBaseChanged: apply()
  onBarChanged: Qt.callLater(apply)

  // Slots register as each monitor's bar builds; re-apply when the set
  // changes so a late bar, or a new monitor, is covered too. Qt.callLater
  // folds a burst of registrations into one pass.
  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onModuleSlotsChanged() { Qt.callLater(root.apply) }
  }

  Component.onCompleted: sync()
  Component.onDestruction: restore()

  // ---------------------------------------------------------------- apply

  // The section list a slot belongs to: the Loader whose loaded Row/Column
  // is the slot's parent. It carries the section name in `region`.
  function sectionList(slot) {
    var row = slot.parent
    var list = row ? row.parent : null
    return list && list.item === row && typeof list.region === "string" ? list : null
  }

  // What the bar pins to the screen: one entry per section list, plus the
  // anchored center slot when the bar has a centerAnchor (that slot, not the
  // list around it, is what the bar pins to the middle of the screen).
  //
  // The built-in bar is handed the Bar itself and names its sections through
  // `moduleSlots`. A third-party widget only gets a PluginBarApi facade (no
  // `moduleSlots`) from Omarchy 4.0.3 on, so fall back to walking the scene
  // graph for the section Loaders, which carry their name in `region`.
  function sectionTargets() {
    var slots = root.bar ? root.bar.moduleSlots : null // qmllint disable missing-property
    if (Array.isArray(slots) && slots.length) {
      var out = [], seen = []
      for (var i = 0; i < slots.length; i++) {
        var slot = slots[i]
        var list = sectionList(slot)
        if (list && seen.indexOf(list) === -1) {
          seen.push(list)
          out.push({ list: list, anchored: slot.region === "center" && slot.anchors.centerIn ? slot : null })
        }
      }
      if (out.length) return out
    }
    return sceneSectionTargets()
  }

  // The fallback. The section Loaders move with the bar, so find them wherever
  // they are in this window and remember them: the walk is the expensive part
  // and the bar's shape only changes when it is rebuilt, which destroys the old
  // Loaders and drops the cache. The cache is re-validated on every use, and
  // dropped whenever the bar host itself changes.
  function sceneSectionTargets() {
    var cached = root.targets
    if (cached.length) {
      for (var v = 0; v < cached.length; v++) {
        if (!cached[v].list || !cached[v].list.parent || !cached[v].list.item) { cached = []; break }
      }
      if (cached.length) return cached
    }
    var top = root
    while (top.parent) top = top.parent
    var found = [], queue = [top], seen = []
    for (var guard = 0; queue.length && guard < 2000; guard++) {
      var n = queue.shift()
      if (!n || seen.indexOf(n) !== -1) continue
      seen.push(n)
      if (typeof n.region === "string" && n.item) found.push({ list: n, anchored: n.anchors.centerIn ? n : null })
      var kids = n.children
      if (kids) for (var c = 0; c < kids.length; c++) queue.push(kids[c])
    }
    root.targets = found
    return found
  }

  function poke(item, prop, value, edge) {
    if (item.anchors[prop] === value) return
    item.anchors[prop] = value
    for (var i = 0; i < touched.length; i++) {
      if (touched[i].item === item && touched[i].prop === prop) return
    }
    touched.push({ item: item, prop: prop, edge: edge })
  }

  function apply() {
    var targets = sectionTargets()
    if (!targets.length) return
    var edge = root.edgeBase + root.edgeOffset
    var centerProp = root.vertical ? "verticalCenterOffset" : "horizontalCenterOffset"
    for (var i = 0; i < targets.length; i++) {
      var list = targets[i].list
      if (!list) continue
      if (list.region === "left") poke(list, root.vertical ? "topMargin" : "leftMargin", edge, true)
      else if (list.region === "right") poke(list, root.vertical ? "bottomMargin" : "rightMargin", edge, true)
      else if (list.region === "center" && list.anchors.centerIn) poke(list, centerProp, root.centerOffset, false)
      // With a center anchor set, the anchored module's slot is what the bar
      // pins to the middle of the screen; the lists beside it follow it.
      var anchored = targets[i].anchored
      if (anchored && anchored !== list && anchored.anchors.centerIn) poke(anchored, centerProp, root.centerOffset, false)
    }
  }

  function restore() {
    var items = touched
    touched = []
    for (var i = 0; i < items.length; i++) {
      var t = items[i]
      if (t.item) t.item.anchors[t.prop] = t.edge ? root.edgeBase : 0
    }
  }
}
