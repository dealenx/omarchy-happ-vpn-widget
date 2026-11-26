import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Happ's own tray item paints a dark 22px tile whatever the theme, so it never
// sits right on the bar, and it says nothing about the tunnel. This widget is
// the stand-in: an H in the bar foreground while the tunnel is down, in the
// theme accent while it is up. Left click focuses Happ, or starts it.
BarWidget {
  id: root
  moduleName: "io.github.dealenx.happ-vpn"

  // Happ brings the tunnel up as a TUN device (happ-tun, happ-xray, happ-wg,
  // happ-default-tun, sing-box-tun) or, in proxy mode, as a core process with
  // no interface at all. Either one means traffic is being carried.
  property bool tunnelUp: false

  readonly property int refreshIntervalSec: {
    var value = Number(setting("refreshIntervalSec", 2))
    return isFinite(value) && value >= 1 ? Math.round(value) : 2
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function refresh() {
    if (probe.running) return
    probe.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: probe
    command: ["bash", "-c",
      "for d in /sys/class/net/happ-* /sys/class/net/sing-box-tun; do "
        + "[ -e \"$d\" ] && { echo up; exit 0; }; done; "
        + "pgrep -f '[c]ore/xray |[t]un2proxy-bin' >/dev/null 2>&1 "
        + "&& echo up || echo down"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.tunnelUp = String(text).trim() === "up"
      }
    }
  }

  // A device or a core process can appear and vanish without anything telling
  // the shell, so the probe repeats. It reads /sys and the process table only.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Panel lifecycle forwarded from this entry point, as the Omarchy plugin
  // contract expects: the bar widget owns the button, HappMenu.qml the surface.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.tunnelUp = root.tunnelUp
  }

  onBarChanged: injectPanel()

  // Forward the probed state into the loaded panel without waiting for a
  // reload, so the header row never shows a stale "down".
  onTunnelUpChanged: if (panelLoader.item) panelLoader.item.tunnelUp = root.tunnelUp

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("HappMenu.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // "H" is a plain letter, so BarIconButton lays it out as a label rather
    // than an icon glyph, and the active state tints it through activeColor.
    text: "H"
    fontSize: Style.bar.iconFont
    active: root.tunnelUp
    activeColor: Commons.Color.accent
    tooltipText: root.tunnelUp ? strings.t("bar.connected") : strings.t("bar.disconnected")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        root.refresh()
        return
      }
      // Left opens Happ's own menu as a panel here; right starts or raises the
      // app. Plain `happ`, not omarchy-launch-or-focus: that helper matches a
      // window by pattern, and "Happ" also matches a terminal titled after it.
      // A second Happ is a SingleApplication no-op that raises the running one.
      if (buttonCode === Qt.RightButton) Util.execDetached("happ")
      else root.toggle()
    }
  }
}
