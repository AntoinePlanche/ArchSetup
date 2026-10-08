import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// Notification history panel on the right edge of the screen
Popup {
    id: pop
    name: "notifications"
    placement: "right"
    slide: true
    cardWidth: 400
    cardHeight: screen.height - (Theme.barMargin + Theme.barHeight + Theme.popupGap) - Theme.barSide
    cardRadius: 24

    onOpenChanged: Notifs.centerOpen = open

    // Group by app, newest group first
    readonly property var groups: {
        const map = new Map();
        for (const n of Notifs.history) {
            const key = n.appName || "Other";
            if (!map.has(key)) map.set(key, []);
            map.get(key).push(n);
        }
        return [...map.entries()].map(([app, items]) => ({ app, items }));
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 14

        // Header: date + controls
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Label { text: Qt.formatDate(clock.date, "dddd"); font.pixelSize: 22; font.weight: Font.Bold }
                Label { text: Qt.formatDate(clock.date, "d MMMM"); color: Theme.textDim; font.pixelSize: 13 }
            }
            HoverBox {
                implicitWidth: 34; implicitHeight: 34; radius: 17
                active: Notifs.dnd
                color: Notifs.dnd ? Qt.rgba(0.37, 0.36, 0.9, 0.85) : hovered ? Theme.hover : Theme.well
                onClicked: Notifs.dnd = !Notifs.dnd
                Icon { anchors.centerIn: parent; glyph: Notifs.dnd ? "󰂛" : "󰂚"; font.pixelSize: 16 }
            }
            HoverBox {
                visible: Notifs.history.length > 0
                implicitWidth: clearLbl.implicitWidth + 24; implicitHeight: 34; radius: 17
                color: hovered ? Theme.hover : Theme.well
                onClicked: Notifs.clearAll()
                Label { id: clearLbl; anchors.centerIn: parent; text: "Clear All"; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
        }

        Label {
            visible: Notifs.dnd
            Layout.fillWidth: true
            text: "Do Not Disturb is on — banners are hidden"
            color: Theme.textDim
            font.pixelSize: 12
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: groupsCol.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: groupsCol
                x: 6
                y: 6
                width: parent.width - 12
                spacing: 18

                Repeater {
                    model: pop.groups
                    Column {
                        id: group
                        required property var modelData
                        width: groupsCol.width
                        spacing: 8

                        RowLayout {
                            width: parent.width
                            Label {
                                Layout.fillWidth: true
                                text: group.modelData.app
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            HoverBox {
                                implicitWidth: 22; implicitHeight: 22; radius: 11
                                color: hovered ? Theme.hover : Theme.well
                                onClicked: { for (const n of group.modelData.items.slice()) Notifs.dismiss(n); }
                                Icon { anchors.centerIn: parent; glyph: "󰅖"; font.pixelSize: 11; color: Theme.textDim }
                            }
                        }
                        Repeater {
                            model: group.modelData.items
                            NotifCard {
                                required property Notification modelData
                                notif: modelData
                                width: group.width
                                onClosed: Notifs.dismiss(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // Empty state
    Column {
        anchors.centerIn: parent
        visible: Notifs.history.length === 0
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "󰂚"; font.pixelSize: 34; color: Theme.textFaint }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: "No Notifications"; color: Theme.textFaint; font.pixelSize: 14; font.weight: Font.DemiBold }
    }
}
