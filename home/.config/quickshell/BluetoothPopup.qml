import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// macOS-like Bluetooth menu: power toggle, your devices, nearby devices
Popup {
    id: pop
    name: "bluetooth"
    cardWidth: 300
    cardHeight: Math.min(480, col.implicitHeight + 24)

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var known: Bluetooth.devices.values
        .filter(d => d.paired || d.connected)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var nearby: Bluetooth.devices.values
        .filter(d => !d.paired && !d.connected && d.deviceName && d.deviceName !== d.address.replace(/:/g, "-"))
        .sort((a, b) => a.name.localeCompare(b.name))

    // Scan only while the menu is open
    onOpenChanged: if (adapter && adapter.enabled) adapter.discovering = open

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Label { text: "Bluetooth"; font.pixelSize: 14; font.weight: Font.Bold; Layout.fillWidth: true }
            Toggle {
                checked: pop.adapter?.enabled ?? false
                onToggled: if (pop.adapter) pop.adapter.enabled = !pop.adapter.enabled
            }
        }

        Divider {}

        Section { text: "My Devices"; visible: pop.known.length > 0 }
        Repeater {
            model: pop.known
            DeviceRow { required property BluetoothDevice modelData; device: modelData }
        }

        Section {
            text: "Nearby Devices"
            visible: pop.adapter?.enabled ?? false
            busy: pop.adapter?.discovering ?? false
        }
        Repeater {
            model: pop.adapter?.enabled ? pop.nearby : []
            DeviceRow { required property BluetoothDevice modelData; device: modelData }
        }
        Label {
            visible: (pop.adapter?.enabled ?? false) && pop.nearby.length === 0
            Layout.leftMargin: 6
            text: "Searching…"
            color: Theme.textFaint
            font.pixelSize: 12
        }

        Divider {}

        HoverBox {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: 8
            onClicked: { pop.shell.openPopup = ""; Quickshell.execDetached(["blueman-manager"]); }
            Label {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Bluetooth Settings…"
            }
        }
    }

    component Section: RowLayout {
        property alias text: lbl.text
        property bool busy: false
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.topMargin: 2
        Label { id: lbl; color: Theme.textDim; font.pixelSize: 11; font.weight: Font.DemiBold }
        Spinner { visible: parent.busy }
    }

    component DeviceRow: HoverBox {
        id: row
        property BluetoothDevice device
        readonly property bool busy: device.state === BluetoothDeviceState.Connecting
                                  || device.state === BluetoothDeviceState.Disconnecting || device.pairing
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 12
        onClicked: {
            if (device.connected) device.disconnect();
            else if (device.paired) device.connect();
            else { device.trusted = true; device.pair(); }
        }

        // Newly paired from "Nearby": connect right away, like macOS
        Connections {
            target: row.device
            function onPairedChanged() { if (row.device.paired && !row.device.connected) row.device.connect(); }
        }

        Rectangle {
            id: badge
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            width: 30; height: 30; radius: 15
            color: row.device.connected ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: Theme.normal } }
            Icon {
                anchors.centerIn: parent
                font.pixelSize: 15
                glyph: {
                    const i = row.device.icon || "";
                    if (i.includes("headset") || i.includes("headphone")) return "󰋋";
                    if (i.includes("audio")) return "󰓃";
                    if (i.includes("mouse")) return "󰍽";
                    if (i.includes("keyboard")) return "󰌌";
                    if (i.includes("phone")) return "󰏲";
                    if (i.includes("gaming")) return "󰊴";
                    if (i.includes("computer")) return "󰟀";
                    return "󰂯";
                }
            }
        }
        Column {
            anchors { left: badge.right; leftMargin: 10; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Label { width: parent.width; text: row.device.name; font.weight: Font.Medium }
            Label {
                width: parent.width
                visible: text !== ""
                font.pixelSize: 11
                color: Theme.textDim
                text: row.device.pairing ? "Pairing…"
                    : row.device.state === BluetoothDeviceState.Connecting ? "Connecting…"
                    : row.device.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : row.device.connected ? (row.device.batteryAvailable ? `Connected · ${Math.round(row.device.battery * 100)}%` : "Connected")
                    : ""
            }
        }
        Item {
            id: tail
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 16; height: 16
            Spinner { anchors.centerIn: parent; visible: row.busy }
        }
    }
}
