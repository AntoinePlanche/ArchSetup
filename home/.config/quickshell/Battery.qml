import QtQuick
import QtQuick.Shapes
import Quickshell.Services.UPower

// iOS-style battery for the bar. Only shown when the machine has a laptop battery
// (UPower display device), so desktops show nothing and headsets don't count.
//  - pill with a cap, filled with the charge; the percentage sits inside, two-toned
//    (dark over the fill, light over the empty part) so it reads at any level
//  - green + lightning bolt while charging / full on the charger, red at <= 20 %,
//    soft pulse at <= 10 %
//  - hover: the time left (or until full) slides out beside it
HoverBox {
    id: root
    readonly property var dev: UPower.displayDevice
    // Optional preview without a battery: "0.42,charging" (fraction, state)
    property string fake: ""

    readonly property bool present: fake !== "" || (!!dev && dev.ready && dev.isLaptopBattery && dev.isPresent)
    readonly property real level: {
        if (fake !== "") return Number(fake.split(",")[0]);
        const p = dev ? dev.percentage : 0;
        return Math.max(0, Math.min(1, p > 1 ? p / 100 : p)); // 0..1 (older Quickshell: 0..100)
    }
    readonly property bool charging: fake !== "" ? fake.split(",")[1] === "charging"
        : !!dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged
                    || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool low: !charging && level <= 0.20
    readonly property bool critical: !charging && level <= 0.10
    readonly property int pct: Math.round(level * 100)
    readonly property color fillColor: charging ? Theme.green : low ? Theme.red : Theme.text

    readonly property string timeText: {
        if (fake !== "" || !dev) return charging ? "1 h 05 until full" : "3 h 20 left";
        const s = charging ? dev.timeToFull : dev.timeToEmpty;
        if (!s || s <= 0) return charging && level >= 0.995 ? "Fully charged" : "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        const t = h > 0 ? h + " h " + String(m).padStart(2, "0") : m + " min";
        return charging ? t + " until full" : t + " left";
    }

    visible: present
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 28

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        // ---- The battery ----
        Item {
            id: battery
            width: 31
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.critical ? pulse.value : 1

            QtObject { id: pulse; property real value: 1 }
            SequentialAnimation {
                running: root.critical
                loops: Animation.Infinite
                onStopped: pulse.value = 1
                NumberAnimation { target: pulse; property: "value"; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { target: pulse; property: "value"; to: 1; duration: 900; easing.type: Easing.InOutSine }
            }

            // Body: translucent track
            Rectangle {
                id: body
                width: 28
                height: parent.height
                radius: 4.5
                color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 0

                // Fill
                Rectangle {
                    id: fill
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: Math.max(root.level > 0 ? radius * 2 : 0, parent.width * root.level)
                    radius: parent.radius
                    color: root.fillColor
                    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }

                // Content (bolt + number), drawn twice and clipped: dark over the fill, light over the track
                Item {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: fill.width
                    clip: true
                    BatteryContent { width: body.width; height: body.height; tone: Qt.rgba(0, 0, 0, 0.82) }
                }
                Item {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: parent.width - fill.width
                    clip: true
                    BatteryContent { x: -fill.width; width: body.width; height: body.height; tone: Theme.text }
                }
            }

            // Cap
            Rectangle {
                anchors { left: body.right; leftMargin: 1; verticalCenter: body.verticalCenter }
                width: 2
                height: 5
                radius: 1
                color: root.level >= 0.995 ? root.fillColor : Qt.rgba(1, 1, 1, 0.35)
            }
        }

        // ---- Time left, slides out on hover ----
        Item {
            anchors.verticalCenter: parent.verticalCenter
            height: timeLbl.implicitHeight
            width: root.hovered && root.timeText ? timeLbl.implicitWidth : 0
            clip: true
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Label {
                id: timeLbl
                text: root.timeText
                color: Theme.textDim
                font.pixelSize: 12
                font.features: { "tnum": 1 }
            }
        }
    }

    component BatteryContent: Item {
        id: content
        property color tone
        Row {
            anchors.centerIn: parent
            spacing: 1
            Shape { // lightning bolt
                visible: root.charging
                width: 6
                height: 9
                anchors.verticalCenter: parent.verticalCenter
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: content.tone
                    startX: 3.7; startY: 0
                    PathLine { x: 0.2; y: 5.2 }
                    PathLine { x: 2.7; y: 5.2 }
                    PathLine { x: 2.1; y: 9 }
                    PathLine { x: 5.8; y: 3.6 }
                    PathLine { x: 3.3; y: 3.6 }
                    PathLine { x: 3.7; y: 0 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.pct
                color: content.tone
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                renderType: Text.CurveRendering // grayscale AA: no colour fringes on the clipped halves
            }
        }
    }
}
