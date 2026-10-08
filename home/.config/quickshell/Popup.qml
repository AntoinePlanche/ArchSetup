import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Glass popover shown under the bar. Layer-shell surface, so it floats above apps
// without being a window. Closes on outside click (focus grab) or Escape.
PanelWindow {
    id: win

    required property var shell
    required property string name
    // "center": centered on screen; "under": centered under its button; "right": right edge aligned with its button
    property string placement: "under"
    property int cardWidth: 300
    property int cardHeight: 200
    property bool slide: false // slide in from the right instead of dropping down
    default property alias content: body.data
    property alias cardRadius: card.radius

    // Opened by its button (interactive), or flashed briefly by the shell (e.g. volume knob)
    readonly property bool interactive: shell.openPopup === name
    readonly property bool open: interactive || shell.flash === name
    readonly property int pad: 28 // transparent room for the shadow
    readonly property var geo: shell.anchors[name] ?? ({ center: 0, right: 0 })

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popup"
    // A flashed popup never takes keyboard focus away from the app you're typing in
    WlrLayershell.keyboardFocus: interactive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Stay mapped while the close animation plays
    visible: open || closing.running
    onOpenChanged: if (!open) closing.restart()
    onInteractiveChanged: {
        if (interactive) grabDelay.restart();
        else grab.active = false;
    }
    Timer { id: closing; interval: Theme.normal }

    anchors.top: true
    anchors.left: placement === "under"
    anchors.right: placement === "right"
    implicitWidth: cardWidth + pad * 2
    implicitHeight: cardHeight + pad * 2
    margins.top: Theme.barMargin + Theme.barHeight + Theme.popupGap - pad
    margins.left: Math.max(Theme.barSide - pad, Math.min(geo.center - implicitWidth / 2, screen.width - implicitWidth - Theme.barSide + pad))
    margins.right: screen.width - geo.right - pad

    mask: Region { item: card }

    // Grab only once the surface is mapped: a grab made before that is cleared instantly
    Timer { id: grabDelay; interval: 60; onTriggered: grab.active = win.interactive }
    onVisibleChanged: if (visible && interactive) grabDelay.restart()

    HyprlandFocusGrab {
        id: grab
        windows: [win, win.shell.barWindow]
        property double since: 0
        onActiveChanged: if (active) since = Date.now()
        onCleared: {
            if (!win.interactive) return;
            // Hyprland sometimes drops a fresh grab right away; a real outside click can't be that fast
            if (Date.now() - since < 300) grabDelay.restart();
            else win.shell.openPopup = "";
        }
    }

    RectangularShadow {
        anchors.fill: card
        opacity: card.opacity
        scale: card.scale
        radius: card.radius
        blur: 30
        offset.y: 8
        color: Qt.rgba(0, 0, 0, 0.30)
    }

    Glass {
        id: card
        x: win.pad + (win.slide && !win.open ? 40 : 0)
        y: win.pad + (win.slide || win.open ? 0 : -8)
        width: win.cardWidth
        height: win.cardHeight
        transformOrigin: Item.Top
        opacity: win.open ? 1 : 0
        scale: win.open || win.slide ? 1 : 0.95

        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Item {
            id: body
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: win.shell.openPopup = ""
        }
    }
}
