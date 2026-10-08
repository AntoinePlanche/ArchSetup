import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// macOS-like network menu: Wi-Fi toggle + networks, then Ethernet. Driven by nmcli.
Popup {
    id: pop
    name: "network"
    cardWidth: 300
    cardHeight: col.implicitHeight + 24

    property bool wifiOn: true
    property var networks: []      // [{ ssid, signal, secure, active, known }]
    property var known: []         // saved Wi-Fi connection names
    property string expanded: ""   // SSID whose password field is open
    property string busy: ""       // SSID / device currently connecting
    property string error: ""

    readonly property var wired: SysStats.netDevices.filter(d => d.type === "ethernet")
    readonly property bool hasWifi: SysStats.netDevices.some(d => d.type === "wifi")

    // nmcli -t escapes ':' inside fields as '\:'
    function fields(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && i + 1 < line.length) cur += line[++i];
            else if (line[i] === ":") { out.push(cur); cur = ""; }
            else cur += line[i];
        }
        out.push(cur);
        return out;
    }
    function refresh() {
        radioProc.running = true;
        knownProc.running = true;
        scanProc.running = true;
    }
    function run(cmd, tag) {
        busy = tag;
        error = "";
        action.command = cmd;
        action.running = true;
    }
    function clickWifi(n) {
        if (n.active) run(["nmcli", "connection", "down", "id", n.ssid], n.ssid);
        else if (n.known) run(["nmcli", "connection", "up", "id", n.ssid], n.ssid);
        else if (n.secure) expanded = expanded === n.ssid ? "" : n.ssid;
        else run(["nmcli", "device", "wifi", "connect", n.ssid], n.ssid);
    }

    onOpenChanged: if (open) { expanded = ""; error = ""; refresh(); }
    Timer { interval: 10000; repeat: true; running: pop.open; onTriggered: scanProc.running = true }

    Process {
        id: radioProc
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: pop.wifiOn = text.trim() === "enabled" }
    }
    Process {
        id: knownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: pop.known = text.trim().split("\n").map(pop.fields)
                .filter(f => f[1] === "802-11-wireless").map(f => f[0])
        }
    }
    Process {
        id: scanProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const best = new Map(); // two Wi-Fi adapters see the same SSIDs: keep the strongest
                for (const line of text.trim().split("\n")) {
                    const f = pop.fields(line);
                    if (f.length < 4 || !f[1]) continue;
                    const n = { ssid: f[1], signal: Number(f[2]), secure: f[3] !== "" && f[3] !== "--", active: f[0] === "*" };
                    const prev = best.get(n.ssid);
                    if (!prev || n.active || (!prev.active && n.signal > prev.signal)) best.set(n.ssid, n);
                }
                pop.networks = [...best.values()]
                    .map(n => Object.assign(n, { known: pop.known.includes(n.ssid) }))
                    .sort((a, b) => (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal))
                    .slice(0, 12);
            }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: actionErr }
        onExited: code => {
            if (code !== 0) pop.error = (actionErr.text.trim().split("\n").pop() || "Failed").replace(/^Error: /, "");
            else pop.expanded = "";
            pop.busy = "";
            pop.refresh();
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6

        // ---- Wi-Fi ----
        RowLayout {
            visible: pop.hasWifi
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Label { text: "Wi-Fi"; font.pixelSize: 14; font.weight: Font.Bold; Layout.fillWidth: true }
            Toggle {
                checked: pop.wifiOn
                onToggled: pop.run(["nmcli", "radio", "wifi", pop.wifiOn ? "off" : "on"], "radio")
            }
        }

        // Scrolls after ~6 networks so Ethernet stays visible below
        ListView {
            id: wifiList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 6 * 44)
            visible: count > 0
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: pop.wifiOn && pop.hasWifi ? pop.networks : []
            delegate: ColumnLayout {
                id: net
                required property var modelData
                width: wifiList.width
                spacing: 4

                HoverBox {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    onClicked: pop.clickWifi(net.modelData)

                    Rectangle {
                        id: badge
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28; radius: 14
                        color: net.modelData.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                        Icon {
                            anchors.centerIn: parent
                            font.pixelSize: 14
                            glyph: net.modelData.signal > 75 ? "󰤨" : net.modelData.signal > 50 ? "󰤥" : net.modelData.signal > 25 ? "󰤢" : "󰤟"
                        }
                    }
                    Label {
                        anchors { left: badge.right; leftMargin: 10; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: net.modelData.ssid
                        font.weight: net.modelData.active ? Font.DemiBold : Font.Normal
                    }
                    Row {
                        id: tail
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Spinner { visible: pop.busy === net.modelData.ssid; anchors.verticalCenter: parent.verticalCenter }
                        Icon { visible: net.modelData.secure; glyph: "󰌾"; font.pixelSize: 12; color: Theme.textFaint }
                    }
                }

                // Password field for new secured networks
                RowLayout {
                    visible: pop.expanded === net.modelData.ssid
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 6
                    onVisibleChanged: if (visible) pw.forceActiveFocus()

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 15
                        color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        border.color: pw.activeFocus ? Qt.rgba(0.04, 0.52, 1, 0.8) : Theme.stroke
                        TextInput {
                            id: pw
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13
                            clip: true
                            onAccepted: join.clicked(null)
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !pw.text
                                text: "Password"
                                color: Theme.textFaint
                            }
                        }
                    }
                    HoverBox {
                        id: join
                        implicitWidth: 52; implicitHeight: 30; radius: 15
                        color: hovered ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                        onClicked: pop.run(["nmcli", "device", "wifi", "connect", net.modelData.ssid, "password", pw.text], net.modelData.ssid)
                        Label { anchors.centerIn: parent; text: "Join"; color: "white"; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    }
                }
            }
        }

        Label {
            visible: pop.error !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 6
            text: pop.error
            color: Theme.red
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        Divider { visible: pop.hasWifi }

        // ---- Ethernet ----
        Label {
            Layout.leftMargin: 6
            text: "Ethernet"
            color: Theme.textDim
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        Repeater {
            model: pop.wired
            HoverBox {
                id: eth
                required property var modelData
                readonly property bool on: modelData.state === "connected"
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 12
                onClicked: pop.run(["nmcli", "device", on ? "disconnect" : "connect", modelData.device], modelData.device)

                Rectangle {
                    id: ethBadge
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 14
                    color: eth.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                    Icon { anchors.centerIn: parent; glyph: "󰈀"; font.pixelSize: 14 }
                }
                Column {
                    anchors { left: ethBadge.right; leftMargin: 10; right: ethTail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Label { width: parent.width; text: eth.modelData.connection || eth.modelData.device; font.weight: eth.on ? Font.DemiBold : Font.Normal }
                    Label { width: parent.width; text: eth.on ? "Connected" : "Not connected"; font.pixelSize: 11; color: Theme.textDim }
                }
                Item {
                    id: ethTail
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 16; height: 16
                    Spinner { anchors.centerIn: parent; visible: pop.busy === eth.modelData.device }
                    Icon { anchors.centerIn: parent; visible: eth.on && pop.busy !== eth.modelData.device; glyph: "󰄬"; color: Theme.accent; font.pixelSize: 14 }
                }
            }
        }

        Divider {}

        HoverBox {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: 8
            onClicked: { pop.shell.openPopup = ""; Quickshell.execDetached(["nm-connection-editor"]); }
            Label {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Network Settings…"
            }
        }
    }
}
