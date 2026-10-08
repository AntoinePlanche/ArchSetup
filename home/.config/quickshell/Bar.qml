import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Io

PanelWindow {
    id: bar
    required property var shell

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int activeWs: monitor?.activeWorkspace?.id ?? 1
    readonly property PwNode sink: Pipewire.defaultAudioSink

    // Screen-space geometry of a bar button, used to place its popup
    function geometryOf(name) {
        const item = ({ calendar: clockBtn, network: netBtn, bluetooth: btBtn, volume: volBtn, windows: winBtn, power: powerBtn })[name];
        if (!item) return { center: screen.width / 2, right: screen.width - Theme.barSide };
        const p = item.mapToItem(null, 0, 0);
        return { center: Theme.barSide + p.x + item.width / 2, right: Theme.barSide + p.x + item.width };
    }

    // Auto-hide on OLED monitors (burn-in): revealed by the top screen edge or an open
    // popup; SUPER+Z (`qs ipc call bar toggle`) pins it until pressed again.
    // Elsewhere the bar is always shown.
    readonly property bool autoHide: Theme.oledMonitors.some(m => (monitor?.description ?? "").includes(m))
    readonly property bool wantShown: !autoHide || hover.hovered || shell.openPopup !== "" || shell.flash !== "" || pinned
    property bool shown: true
    onWantShownChanged: {
        if (wantShown) { hideDelay.stop(); shown = true; }
        else hideDelay.restart();
    }
    Timer { id: hideDelay; interval: 600; onTriggered: bar.shown = bar.wantShown }

    // "Restart into Windows" button only on dual-boot machines (a Windows Boot Manager UEFI entry exists)
    property bool hasWindows: false
    Process {
        running: true
        command: ["sh", "-c", "efibootmgr | grep -q 'Windows Boot Manager'"]
        onExited: exitCode => bar.hasWindows = exitCode === 0
    }
    property bool pinned: false
    Component.onCompleted: shown = wantShown

    IpcHandler {
        target: "bar"
        enabled: bar.monitor?.focused ?? false
        function toggle(): void {
            bar.pinned = !bar.pinned;
            // Explicit unpin hides right away; the 600 ms grace is only for the mouse leaving
            if (!bar.wantShown) { hideDelay.stop(); bar.shown = false; }
        }
    }

    WlrLayershell.namespace: "qs-bar"
    color: "transparent"
    // Hide only for real fullscreen (SUPER+F, mode 2). Hyprland also reports a maximized
    // window (SUPER+A, mode 1) as hasFullscreen, so check each window's mode.
    readonly property bool realFullscreen: (monitor?.activeWorkspace?.hasFullscreen ?? false)
        && Hyprland.toplevels.values.some(t => t.workspace === monitor.activeWorkspace
                                                && t.lastIpcObject?.fullscreen === 2)
    visible: !realFullscreen
    // lastIpcObject is only refreshed on demand
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") Hyprland.refreshToplevels();
        }
    }

    anchors { top: true; left: true; right: true }
    // Auto-hide: the window touches the screen edge (hot zone) and only reserves
    // space while shown, so windows move below the bar like when it's always on
    margins { top: autoHide ? 0 : Theme.barMargin; left: Theme.barSide; right: Theme.barSide }
    implicitHeight: autoHide ? Theme.barMargin + Theme.barHeight : Theme.barHeight
    exclusionMode: autoHide ? ExclusionMode.Normal : ExclusionMode.Auto
    exclusiveZone: autoHide && shown ? Theme.barMargin + Theme.barHeight : 0
    mask: Region { item: bar.shown ? content : hotZone }

    Item {
        anchors.fill: parent
        HoverHandler { id: hover }

        Item { // 2 px strip along the top edge that reveals the hidden bar
            id: hotZone
            width: parent.width
            height: 2
        }

        Item {
            id: content
            width: parent.width
            height: Theme.barHeight
            y: bar.shown ? (bar.autoHide ? Theme.barMargin : 0) : -Theme.barHeight - 4
            opacity: bar.shown ? 1 : 0
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            PwObjectTracker { objects: [bar.sink] }
            SystemClock { id: clock; precision: SystemClock.Minutes }

            Glass {
                anchors.fill: parent
                radius: 14
                tint: Theme.barTint
                sheen: 0.07
            }

            // left | gap | music | gap | date | gap | right — the three gaps stay equal.
            // Without music the date is centered on the bar instead.
            RowLayout {
                id: row
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                spacing: 0

                // ---------- Workspaces + apps of the current workspace ----------
                RowLayout {
                    spacing: 8

                    Bubble {
                        id: wsTrack
                        // Only workspaces that exist (Hyprland deletes empty ones you leave)
                        readonly property var ids: {
                            const s = new Set([bar.activeWs]);
                            for (const w of Hyprland.workspaces.values)
                                if (w.id > 0 && (!w.monitor || w.monitor === bar.monitor)) s.add(w.id);
                            return [...s].sort((a, b) => a - b);
                        }
                        implicitWidth: wsRow.implicitWidth + 6

                        Rectangle { // sliding active pill
                            readonly property Item target: wsRepeater.itemAt(Math.max(0, wsTrack.ids.indexOf(bar.activeWs)))
                            x: target ? target.x + wsRow.x : 3
                            width: target ? target.width : 24
                            y: 3
                            height: parent.height - 6
                            radius: 7
                            color: Qt.rgba(1, 1, 1, 0.20)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.16)
                            Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            id: wsRow
                            x: 3
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                id: wsRepeater
                                model: wsTrack.ids
                                Item {
                                    id: ws
                                    required property int modelData
                                    width: 26
                                    height: 22
                                    Label {
                                        anchors.centerIn: parent
                                        text: ws.modelData
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: ws.modelData === bar.activeWs ? Theme.text : Theme.textDim
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Hyprland.dispatch(Hyprland.usingLua
                                            ? `hl.dsp.focus({ workspace = ${ws.modelData} })`
                                            : `workspace ${ws.modelData}`)
                                    }
                                }
                            }
                        }
                    }

                    Bubble {
                        visible: appsRepeater.count > 0
                        implicitWidth: appsRow.implicitWidth + 8

                        Row {
                            id: appsRow
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                id: appsRepeater
                                model: ScriptModel {
                                    values: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === bar.activeWs)
                                }
                                HoverBox {
                                    id: app
                                    required property HyprlandToplevel modelData
                                    readonly property string appId: modelData.wayland?.appId || modelData.lastIpcObject?.class || ""
                                    width: 28
                                    height: 24
                                    radius: 7
                                    active: modelData.activated
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: m => m.button === Qt.MiddleButton ? modelData.wayland?.close() : modelData.wayland?.activate()

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 18
                                        // .values makes this re-evaluate once desktop entries finish loading
                                        source: DesktopEntries.applications.values.length >= 0
                                            && Quickshell.iconPath(DesktopEntries.heuristicLookup(app.appId)?.icon || app.appId, "application-x-executable")
                                    }
                                }
                            }
                        }
                    }
                }

                Gap {}

                // ---------- Now playing ----------
                Bubble {
                    id: music
                    visible: Media.shown
                    implicitWidth: musicRow.implicitWidth + 16
                    readonly property var p: Media.player

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        // left: play/pause · right: next · middle: previous
                        onClicked: m => {
                            if (!music.p) return;
                            if (m.button === Qt.RightButton) music.p.next();
                            else if (m.button === Qt.MiddleButton) music.p.previous();
                            else music.p.togglePlaying();
                        }
                    }

                    Row {
                        id: musicRow
                        anchors.centerIn: parent
                        spacing: 8

                        ClippingRectangle { // album art / video thumbnail
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 5
                            color: Theme.well
                            Image {
                                anchors.fill: parent
                                source: music.p?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(40, 40)
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: !(music.p?.trackArtUrl)
                                glyph: "󰎆"
                                font.pixelSize: 12
                            }
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 280)
                            text: (music.p?.trackTitle ?? "") + (music.p?.trackArtist ? "  ·  " + music.p.trackArtist : "")
                            color: Media.playing ? Theme.text : Theme.textDim
                            font.weight: Font.Medium
                        }

                        Row { // live spectrum
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: Media.barCount
                                Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 3 + Math.min(1, Math.sqrt((Media.bars[index] ?? 0) / 70)) * 15
                                    radius: 1.5
                                    color: Media.playing ? Theme.text : Theme.textFaint
                                    Behavior on height { NumberAnimation { duration: 60 } }
                                }
                            }
                        }
                    }
                }

                Gap { visible: music.visible }

                // ---------- Date slot (the date itself is below, outside the layout) ----------
                Item {
                    id: clockSlot
                    visible: music.visible
                    implicitWidth: clockBtn.width
                    implicitHeight: clockBtn.height
                }

                Gap {}

                // ---------- Right: stats | network | notifications | bluetooth + volume | windows + power ----------
                RowLayout {
                    spacing: 2

                    Stat { glyph: "󰢮"; value: SysStats.gpu + "%" }
                    Stat { glyph: ""; value: SysStats.cpu + "%" }
                    Stat { glyph: "\uefc5"; value: SysStats.mem + "%" } // RAM stick (nf-fa-memory)

                    Sep {}

                    HoverBox {
                        id: netBtn
                        implicitWidth: netRow.implicitWidth + 18
                        implicitHeight: 28
                        active: bar.shell.openPopup === "network"
                        onClicked: bar.shell.toggle("network")
                        Row {
                            id: netRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { glyph: SysStats.netType === "wifi" ? "󰖩" : SysStats.netType ? "󰈀" : "󰖪" }
                            Label { text: SysStats.netType === "wifi" ? SysStats.netName : SysStats.netType ? "Wired" : "Offline" }
                        }
                    }

                    Sep {}

                    HoverBox {
                        id: notifBtn
                        implicitWidth: 34
                        implicitHeight: 28
                        active: bar.shell.openPopup === "notifications"
                        onClicked: bar.shell.toggle("notifications")
                        Icon {
                            anchors.centerIn: parent
                            glyph: Notifs.dnd ? "󰂛" : "󰂚"
                            color: Notifs.dnd ? Theme.textDim : Theme.text
                        }
                        Rectangle { // unread badge
                            visible: Notifs.unread > 0
                            anchors { right: parent.right; top: parent.top; rightMargin: 3; topMargin: 2 }
                            width: Math.max(14, badgeLbl.implicitWidth + 7)
                            height: 14
                            radius: 7
                            color: Theme.red
                            Label {
                                id: badgeLbl
                                anchors.centerIn: parent
                                text: Notifs.unread > 9 ? "9+" : Notifs.unread
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: "white"
                            }
                        }
                    }

                    Sep {}

                    HoverBox {
                        id: btBtn
                        readonly property var adapter: Bluetooth.defaultAdapter
                        readonly property bool anyConnected: Bluetooth.devices.values.some(d => d.connected)
                        implicitWidth: 34
                        implicitHeight: 28
                        active: bar.shell.openPopup === "bluetooth"
                        onClicked: bar.shell.toggle("bluetooth")
                        Icon {
                            anchors.centerIn: parent
                            glyph: !btBtn.adapter?.enabled ? "󰂲" : btBtn.anyConnected ? "󰂱" : "󰂯"
                            color: btBtn.anyConnected ? Theme.accent : Theme.text
                        }
                    }

                    HoverBox {
                        id: volBtn
                        readonly property real vol: bar.sink?.audio?.volume ?? 0
                        readonly property bool muted: bar.sink?.audio?.muted ?? false
                        implicitWidth: volRow.implicitWidth + 18
                        implicitHeight: 28
                        active: bar.shell.openPopup === "volume"
                        onClicked: bar.shell.toggle("volume")
                        onWheel: w => {
                            if (!bar.sink?.audio) return;
                            bar.sink.audio.volume = Math.max(0, Math.min(1, volBtn.vol + (w.angleDelta.y > 0 ? 0.05 : -0.05)));
                        }
                        Row {
                            id: volRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { glyph: VolumeGlyph.of(volBtn.vol, volBtn.muted) }
                            Label { text: Math.round(volBtn.vol * 100) + "%"; font.features: { "tnum": 1 } }
                        }
                    }

                    // Laptop battery (hidden on desktops)
                    Sep { visible: battery.present }
                    Battery { id: battery }

                    Sep {}

                    HoverBox {
                        id: winBtn
                        visible: bar.hasWindows
                        implicitWidth: 34
                        implicitHeight: 28
                        active: bar.shell.openPopup === "windows"
                        onClicked: bar.shell.toggle("windows")
                        Icon { anchors.centerIn: parent; glyph: ""; color: "#4cc2ff" }
                    }

                    HoverBox {
                        id: powerBtn
                        implicitWidth: 34
                        implicitHeight: 28
                        active: bar.shell.openPopup === "power"
                        onClicked: bar.shell.toggle("power")
                        Icon { anchors.centerIn: parent; glyph: "󰐥"; color: "#ff6961"; font.pixelSize: 16 }
                    }
                }
            }

            // ---------- Date: in its slot next to the music, or centered on the bar ----------
            Bubble {
                id: clockBtn
                x: music.visible ? row.x + clockSlot.x : (parent.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                implicitWidth: clockLabel.implicitWidth + 40
                color: clockMouse.pressed ? Theme.pressed : clockMouse.containsMouse || bar.shell.openPopup === "calendar" ? Qt.rgba(1, 1, 1, 0.14) : Theme.well
                Label {
                    id: clockLabel
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ddd dd MMM, HH:mm")
                    font.weight: Font.Bold
                }
                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shell.toggle("calendar")
                }
            }
        } // content
    } // hover area

    // Waybar-style module bubble
    component Bubble: Rectangle {
        implicitHeight: 28
        radius: 9
        color: Theme.well
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
    }

    component Gap: Item {
        Layout.fillWidth: true
        Layout.horizontalStretchFactor: 1
        implicitWidth: 0
    }

    component Stat: Row {
        property alias glyph: ic.glyph
        property alias value: val.text
        spacing: 5
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Icon { id: ic; color: Theme.textDim; font.pixelSize: 14 }
        Label { id: val; font.features: { "tnum": 1 } }
    }

    component Sep: Rectangle {
        implicitWidth: 1
        implicitHeight: 16
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        color: Qt.rgba(1, 1, 1, 0.14)
    }
}
