import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop widget (top-left, behind windows): markets with sparkline, price, daily change.
// Data: scripts/markets.py (Yahoo Finance), refreshed every 10 minutes.
PanelWindow {
    id: win

    property var markets: []
    property var rates: []
    property double updated: 0

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-widget"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; left: true }
    margins { top: Theme.barMargin + Theme.barHeight + 18; left: Theme.barSide + 8 }
    implicitWidth: 340
    implicitHeight: card.height
    mask: Region { item: card }

    Process {
        id: fetch
        command: [Quickshell.shellPath("scripts/markets.py")]
        onExited: exitCode => { if (exitCode !== 0) retry.restart(); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.markets = d.markets;
                    win.rates = d.rates || [];
                    win.updated = d.updated;
                } catch (e) {}
            }
        }
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fetch.running = true }
    // A failed fetch (e.g. network not up yet right after login) retries in 15 s
    // instead of waiting for the next regular refresh; the script shows the last data meanwhile.
    Timer { id: retry; interval: 15000; onTriggered: fetch.running = true }

    function fmt(n) {
        return Number(n).toLocaleString(Qt.locale("en_US"), "f", n >= 1000 ? 0 : 2);
    }

    LiquidGlass {
        id: card
        width: parent.width
        height: col.implicitHeight + 28
        radius: 24
        // Light smoky tint: enough contrast for the white text, clear enough to see the blur
        tintTop: Qt.rgba(0.10, 0.10, 0.12, 0.26)
        tintBottom: Qt.rgba(0.06, 0.06, 0.08, 0.32)

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 14 }
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                Icon { glyph: "󰄨"; font.pixelSize: 15; color: Theme.accent }
                Label { text: "Markets"; font.pixelSize: 14; font.weight: Font.Bold; Layout.fillWidth: true }
                Label {
                    text: win.updated ? Qt.formatTime(new Date(win.updated), "HH:mm") : "…"
                    font.pixelSize: 11
                    color: Theme.textFaint
                }
            }

            Repeater {
                model: win.markets
                MarketRow { required property var modelData; m: modelData }
            }

            RowLayout { // 10Y sovereign yields section
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 2
                visible: win.rates.length > 0
                Icon { glyph: "󰞯"; font.pixelSize: 14; color: Theme.accent }
                Label { text: "10-Year Government Bonds"; font.pixelSize: 13; font.weight: Font.Bold; Layout.fillWidth: true }
            }

            Repeater {
                model: win.rates
                MarketRow { required property var modelData; m: modelData }
            }
        }
    }

    component MarketRow: Item {
        id: row
        property var m
        readonly property bool up: (m.change ?? 0) >= 0
        readonly property color tone: up ? "#30d158" : "#ff453a"
        Layout.fillWidth: true
        implicitHeight: 52

        Rectangle { // hover highlight
            anchors { fill: parent; leftMargin: -8; rightMargin: -8 }
            radius: 12
            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(row.m.url || ("https://finance.yahoo.com/quote/" + encodeURIComponent(row.m.symbol)))
        }

        Column {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 112
            spacing: 1
            Label { width: parent.width; text: row.m.name; font.weight: Font.DemiBold; font.pixelSize: 13 }
            Label {
                width: parent.width
                text: row.m.subtitle + (row.m.currency ? " · " + row.m.currency : "")
                font.pixelSize: 11
                color: Theme.textFaint
            }
        }

        // Sparkline: ~1 month of daily closes, with a soft gradient under the line
        Canvas {
            id: spark
            anchors { left: parent.left; leftMargin: 120; verticalCenter: parent.verticalCenter }
            width: 92
            height: 30
            visible: !row.m.error
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const p = row.m.points || [];
                if (p.length < 2) return;
                const lo = Math.min(...p), hi = Math.max(...p), span = (hi - lo) || 1;
                const X = i => i / (p.length - 1) * (width - 2) + 1;
                const Y = v => height - 3 - (v - lo) / span * (height - 6);

                ctx.beginPath();
                p.forEach((v, i) => i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v)));
                ctx.lineTo(X(p.length - 1), height);
                ctx.lineTo(X(0), height);
                ctx.closePath();
                const g = ctx.createLinearGradient(0, 0, 0, height);
                g.addColorStop(0, Qt.rgba(row.tone.r, row.tone.g, row.tone.b, 0.30));
                g.addColorStop(1, Qt.rgba(row.tone.r, row.tone.g, row.tone.b, 0.0));
                ctx.fillStyle = g;
                ctx.fill();

                ctx.beginPath();
                p.forEach((v, i) => i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v)));
                ctx.strokeStyle = row.tone;
                ctx.lineWidth = 1.6;
                ctx.lineJoin = "round";
                ctx.stroke();
            }
            Connections { target: row; function onMChanged() { spark.requestPaint(); } }
        }

        Column {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Label {
                anchors.right: parent.right
                text: row.m.error ? "—" : row.m.kind === "yield" ? Number(row.m.price).toFixed(3) + "%" : win.fmt(row.m.price)
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Rectangle { // change pill, iOS Stocks style
                anchors.right: parent.right
                visible: !row.m.error
                width: pct.implicitWidth + 12
                height: 18
                radius: 6
                color: row.tone
                Label {
                    id: pct
                    anchors.centerIn: parent
                    text: row.m.kind === "yield"
                          ? (row.up ? "+" : "") + Number(row.m.changeBp ?? 0).toFixed(1) + " bp"
                          : (row.up ? "+" : "") + Number(row.m.change ?? 0).toFixed(2) + "%"
                    color: "white"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
