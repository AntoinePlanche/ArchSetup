import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// One notification, macOS-style: icon, app + time, title, body, action pills.
// Hover shows a close button in the top-left corner.
Item {
    id: root
    required property Notification notif
    property bool toast: false
    signal closed()

    readonly property bool critical: notif.urgency === NotificationUrgency.Critical
    readonly property string icon: Notifs.iconFor(notif)
    readonly property var buttons: notif.actions.filter(a => a.identifier !== "default" && a.text)

    implicitHeight: card.implicitHeight

    Glass {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        radius: 18
        tint: root.toast ? Theme.panelTint : Qt.rgba(1, 1, 1, hover.hovered ? 0.11 : 0.07)
        sheen: root.toast ? 0.09 : 0.04
        border.color: root.critical ? Qt.rgba(1, 0.27, 0.23, 0.55) : Theme.stroke
        Behavior on tint { ColorAnimation { duration: Theme.fast } }

        HoverHandler { id: hover }
        TapHandler { onTapped: Notifs.activate(root.notif) }

        RowLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 12

            Rectangle { // app icon tile
                Layout.alignment: Qt.AlignTop
                implicitWidth: 38
                implicitHeight: 38
                radius: 10
                color: root.icon ? "transparent" : Theme.well
                IconImage {
                    anchors.fill: parent
                    visible: root.icon !== ""
                    source: root.icon
                    asynchronous: true
                }
                Icon { anchors.centerIn: parent; visible: root.icon === ""; glyph: "󰂚"; font.pixelSize: 18 }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: root.notif.appName || "Notification"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.textDim
                    }
                    Label { text: Notifs.ago(root.notif); font.pixelSize: 11; color: Theme.textFaint }
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.notif.summary
                    font.weight: Font.DemiBold
                    textFormat: Text.PlainText
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.notif.body
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    textFormat: Text.PlainText
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: root.buttons.length > 0
                    spacing: 6
                    Repeater {
                        model: root.buttons
                        HoverBox {
                            required property NotificationAction modelData
                            width: actLbl.implicitWidth + 24
                            height: 26
                            radius: 13
                            color: hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
                            onClicked: { modelData.invoke(); Notifs.dismiss(root.notif); }
                            Label { id: actLbl; anchors.centerIn: parent; text: parent.parent.modelData.text; font.pixelSize: 12; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }
    }

    // Close button (macOS: top-left, on hover)
    Rectangle {
        x: -6; y: -6
        width: 20; height: 20; radius: 10
        color: closeMouse.containsMouse ? Qt.rgba(0.35, 0.35, 0.38, 1) : Qt.rgba(0.22, 0.22, 0.25, 0.95)
        border.width: 1
        border.color: Theme.stroke
        opacity: hover.hovered || closeMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Icon { anchors.centerIn: parent; glyph: "󰅖"; font.pixelSize: 11 }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closed()
        }
    }
}
