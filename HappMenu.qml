import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Happ's own tray menu, as a bar panel. The rows come from the app's
// com.canonical.dbusmenu over its StatusNotifierItem, so Подключиться,
// Сменить сервер, Показать окно and Выйти do exactly what the tray does,
// without copying any of that logic here.
Panel {
  id: root
  moduleName: "io.github.dealenx.happ-vpn"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  // Tunnel state, owned by the bar widget that hosts this panel.
  property bool tunnelUp: false

  // Happ's item appears when it runs and goes when it exits, so the menu is
  // read live instead of cached at open time.
  readonly property var trayItem: {
    var values = SystemTray.items.values
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item && String(item.id) === "Happ") return item
    }
    return null
  }
  readonly property bool available: trayItem !== null && trayItem.menu !== null

  // The level being shown: the menu's root opener, or one drilled into. Each
  // level keeps its own live opener, because a child entry is owned by its
  // parent opener's model — collapsing to a single opener destroys the very
  // entry being displayed, and the submenu turns up empty.
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : rootMenuOpener.children

  // Qt resets a Repeater when its model is reassigned mid-click; ignore row
  // clicks for a beat after a level change, as the tray drawer does.
  property bool levelSettling: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.submenuStack = []
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    levelSettleTimer.restart()
    levelSettling = true
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    levelSettleTimer.restart()
    levelSettling = true
  }

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: levelSettleTimer
    interval: 250
    onTriggered: root.levelSettling = false
  }

  QsMenuOpener {
    id: rootMenuOpener
    menu: root.trayItem ? root.trayItem.menu : null
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(252))
    contentHeight: panel.fittedContentHeight(menuColumn.implicitHeight, Style.space(460))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: menuColumn
        width: parent.width
        spacing: Style.space(2)

        // State first: the mark on the bar says the same thing, but a panel is
        // where someone looks to confirm it before trusting a click.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.tunnelUp ? strings.t("panel.up") : strings.t("panel.down")
          color: root.tunnelUp ? Commons.Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          bottomPadding: Style.space(6)
        }

        // Way back out of a submenu, named after where we are.
        Item {
          visible: root.submenuDepth > 0
          width: menuColumn.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            textFormat: Text.PlainText
            text: Commons.I18n.rightToLeft ? "\u203a" : "\u2039"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(26)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            textFormat: Text.PlainText
            text: root.currentTitle
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.levelSettling) return
              root.leaveSubmenu()
            }
          }
        }

        // No tray item means Happ is not running, so the useful row is starting
        // it rather than a menu that would be empty.
        Item {
          visible: !root.available
          width: menuColumn.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: launchMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            textFormat: Text.PlainText
            text: strings.t("panel.launch")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: launchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Util.execDetached("happ")
              root.close()
            }
          }
        }

        Repeater {
          model: root.available ? root.currentChildren : []

          delegate: Item {
            id: row
            required property var modelData
            readonly property bool separator: modelData.isSeparator === true
            readonly property bool drillable: !separator && modelData.hasChildren === true
            readonly property string rowText: String(modelData.text || "")

            width: menuColumn.width
            implicitHeight: separator ? Style.space(9) : Style.space(30)

            Rectangle {
              visible: row.separator
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              height: 1
              color: Commons.Color.popups.border
              opacity: 0.45
            }

            Rectangle {
              visible: !row.separator
              anchors.fill: parent
              radius: Math.max(2, Style.cornerRadius)
              color: rowMouse.containsMouse && row.modelData.enabled !== false
                ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
            }

            Text {
              visible: !row.separator
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: chevron.left
              anchors.rightMargin: Style.space(6)
              textFormat: Text.PlainText
              text: row.rowText
              elide: Text.ElideRight
              color: row.modelData.enabled === false ? root.dim : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: chevron
              visible: row.drillable
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              textFormat: Text.PlainText
              text: Commons.I18n.rightToLeft ? "\u2039" : "\u203a"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: !row.separator
              enabled: !row.separator && row.modelData.enabled !== false
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (root.levelSettling) return
                if (row.drillable) root.enterSubmenu(row.modelData, row.rowText)
                else {
                  row.modelData.triggered()
                  root.close()
                }
              }
            }
          }
        }
      }
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
}
