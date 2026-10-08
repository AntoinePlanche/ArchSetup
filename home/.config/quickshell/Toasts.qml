import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notification banners, top-right under the bar. Hovering pauses the auto-hide.
PanelWindow {
    id: win
    readonly property int pad: 28

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notify"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: Notifs.toasts.length > 0 || hold.running

    anchors { top: true; right: true }
    margins.top: Theme.barMargin + Theme.barHeight + Theme.popupGap - pad
    margins.right: Theme.barSide - pad
    implicitWidth: 380 + pad * 2
    implicitHeight: Math.max(1, col.implicitHeight + pad * 2)

    mask: Region { item: col }

    // Keep the surface mapped while the last banner animates out
    Timer { id: hold; interval: Theme.normal }
    Connections {
        target: Notifs
        function onToastsChanged() { if (Notifs.toasts.length === 0) hold.restart(); }
    }

    Column {
        id: col
        x: win.pad
        y: win.pad
        width: 380
        spacing: 10

        move: Transition { NumberAnimation { properties: "y"; duration: Theme.normal; easing.type: Easing.OutCubic } }

        Repeater {
            model: Notifs.toasts
            NotifCard {
                id: toast
                required property Notification modelData
                notif: modelData
                toast: true
                width: col.width
                onClosed: Notifs.dismiss(modelData)

                // Slide in from the right
                property real slide: 40
                transform: Translate { x: toast.slide }
                opacity: 1 - toast.slide / 40
                Component.onCompleted: slide = 0
                Behavior on slide { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                HoverHandler { id: toastHover }
                Timer {
                    // expireTimeout: <= 0 means "server default"; accept seconds or ms
                    interval: {
                        const t = toast.modelData.expireTimeout;
                        return t <= 0 ? 6000 : t < 1000 ? t * 1000 : t;
                    }
                    running: !toastHover.hovered && toast.modelData.urgency !== NotificationUrgency.Critical
                    onTriggered: Notifs.hideToast(toast.modelData)
                }
            }
        }
    }
}
