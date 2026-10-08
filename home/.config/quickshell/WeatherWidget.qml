import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop widget (top-right, behind windows): Apple-style weather on borderless liquid glass.
// Data: scripts/weather.py (IP location + Open-Meteo), refreshed every 15 minutes.
PanelWindow {
    id: win

    property var w: null
    readonly property var cond: w ? w.condition : null

    // Sky tint follows the conditions (kept above Hyprland's ignore_alpha 0.3 so the blur shows)
    readonly property var sky: {
        if (!w) return ["#2c2c34", "#1c1c22"];
        const k = cond.kind;
        if (!w.isDay) return k === "clear" ? ["#1b2a4e", "#0b1226"] : ["#262c3c", "#12141c"];
        if (k === "clear") return ["#3a8ee6", "#1f5fb8"];
        if (k === "partly") return ["#4f86c6", "#2d5a91"];
        if (k === "rain" || k === "storm") return ["#4a5668", "#262d3a"];
        if (k === "snow") return ["#8a9bb3", "#56657d"];
        return ["#62738a", "#3a4657"]; // cloudy / fog
    }

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-widget"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; right: true }
    margins { top: Theme.barMargin + Theme.barHeight + 18; right: Theme.barSide + 8 }
    implicitWidth: 340
    implicitHeight: card.height
    mask: Region { item: card }

    Process {
        id: fetch
        command: [Quickshell.shellPath("scripts/weather.py")]
        onExited: exitCode => { if (exitCode !== 0) retry.restart(); }
        stdout: StdioCollector {
            onStreamFinished: { try { win.w = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fetch.running = true }
    // A failed fetch (e.g. network not up yet right after login) retries in 15 s
    // instead of waiting for the next regular refresh; the script shows the last data meanwhile.
    Timer { id: retry; interval: 15000; onTriggered: fetch.running = true }

    // Week range for the Apple-style temperature bars
    readonly property int weekLo: w ? Math.min(...w.days.map(d => d.lo)) : 0
    readonly property int weekHi: w ? Math.max(...w.days.map(d => d.hi)) : 1

    function tempColor(t) { // cool → warm, like Apple Weather's range bars
        if (t <= 0) return "#5ac8fa";
        if (t <= 10) return "#64d2ff";
        if (t <= 18) return "#a3e36b";
        if (t <= 25) return "#ffd60a";
        return "#ff9f0a";
    }

    LiquidGlass {
        id: card
        width: parent.width
        height: col.implicitHeight + 36
        radius: 30
        opacity: win.w ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        // Sky colour of the current weather, as a clear tint over the blurred wallpaper
        tintTop: Qt.alpha(win.sky[0], 0.34)
        tintBottom: Qt.alpha(win.sky[1], 0.28)
        Behavior on tintTop { ColorAnimation { duration: 800 } }
        Behavior on tintBottom { ColorAnimation { duration: 800 } }
        sheen: 0.14

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (win.w) Qt.openUrlExternally("https://open-meteo.com/en/docs")
            onDoubleClicked: fetch.running = true
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20; topMargin: 18 }
            spacing: 0

            // ── Header: city, big thin temperature, condition ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: -4
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 5
                        Label { text: win.w ? win.w.city : ""; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Icon { glyph: ""; font.pixelSize: 10; color: Theme.text }
                    }
                    Label {
                        text: win.w ? win.w.temp + "°" : ""
                        font.family: "Inter Display"
                        font.weight: Font.Thin
                        font.pixelSize: 66
                        font.features: { "tnum": 1 }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop | Qt.AlignRight
                    spacing: 2
                    Icon {
                        Layout.alignment: Qt.AlignRight
                        glyph: win.cond ? win.cond.glyph : ""
                        color: win.cond ? win.cond.color : Theme.text
                        font.pixelSize: 34
                        Layout.bottomMargin: 8
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: win.cond ? win.cond.label : ""
                        font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: win.w ? "H:" + win.w.hi + "°  L:" + win.w.lo + "°" : ""
                        font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: win.w ? "Feels " + win.w.feels + "° · " + win.w.humidity + "%" : ""
                        font.pixelSize: 11; color: Theme.textDim
                    }
                }
            }

            Hairline { Layout.topMargin: 12; Layout.bottomMargin: 12 }

            // ── Hourly ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: win.w ? win.w.hours : []
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 6
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            color: modelData.label === "Now" ? Theme.text : Theme.textDim
                        }
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 24; implicitHeight: 30
                            Icon {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                                glyph: modelData.glyph; color: modelData.color; font.pixelSize: 19
                            }
                            Label {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                                visible: modelData.pop >= 20
                                text: modelData.pop + "%"
                                font.pixelSize: 9; font.weight: Font.Bold; color: "#64d2ff"
                            }
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.temp + "°"
                            font.pixelSize: 14; font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            Hairline { Layout.topMargin: 12; Layout.bottomMargin: 6 }

            // ── 5-day with range bars ──
            Repeater {
                model: win.w ? win.w.days : []
                RowLayout {
                    id: day
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 10

                    Label {
                        Layout.preferredWidth: 46
                        text: day.modelData.label
                        font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Icon {
                        Layout.preferredWidth: 22
                        glyph: day.modelData.glyph; color: day.modelData.color; font.pixelSize: 17
                    }
                    Label {
                        Layout.preferredWidth: 28
                        horizontalAlignment: Text.AlignRight
                        text: day.modelData.lo + "°"
                        font.pixelSize: 14; color: Theme.textDim
                        font.features: { "tnum": 1 }
                    }
                    Item { // track + this day's range
                        Layout.fillWidth: true
                        implicitHeight: 5
                        Rectangle {
                            anchors.fill: parent
                            radius: 2.5
                            color: Qt.rgba(0, 0, 0, 0.22)
                        }
                        Rectangle {
                            readonly property real span: Math.max(1, win.weekHi - win.weekLo)
                            x: (day.modelData.lo - win.weekLo) / span * parent.width
                            width: Math.max(height, (day.modelData.hi - day.modelData.lo) / span * parent.width)
                            height: parent.height
                            radius: 2.5
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: win.tempColor(day.modelData.lo) }
                                GradientStop { position: 1; color: win.tempColor(day.modelData.hi) }
                            }
                            // Current temperature dot on today's bar
                            Rectangle {
                                visible: day.index === 0 && win.w
                                width: 7; height: 7; radius: 3.5
                                anchors.verticalCenter: parent.verticalCenter
                                x: win.w ? Math.max(0, Math.min(parent.width - width,
                                       (win.w.temp - day.modelData.lo) / Math.max(1, day.modelData.hi - day.modelData.lo) * parent.width - width / 2)) : 0
                                color: "white"
                            }
                        }
                    }
                    Label {
                        Layout.preferredWidth: 28
                        text: day.modelData.hi + "°"
                        font.pixelSize: 14; font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }

    component Hairline: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.rgba(1, 1, 1, 0.10)
    }
}
