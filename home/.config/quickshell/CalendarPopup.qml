import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Month view + agenda for the selected day. Events come from evolution-data-server
// (accounts added in Evolution, e.g. Google), read by scripts/calendar-events.py.
Popup {
    id: pop
    name: "calendar"
    placement: "under" // centered under the date button
    // A quarter of the screen in each dimension
    cardWidth: Math.round(screen.width / 4)
    cardHeight: Math.round(screen.height / 4)

    readonly property date today: new Date()
    property date viewMonth: new Date(today.getFullYear(), today.getMonth(), 1)
    property date selected: new Date(today.getFullYear(), today.getMonth(), today.getDate())
    property var events: []
    property bool remote: true
    property bool loading: false

    // First Monday on or before the 1st; the grid shows 6 weeks from there
    readonly property date gridStart: {
        const d = new Date(viewMonth);
        d.setDate(1 - ((d.getDay() + 6) % 7));
        return d;
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function eventsOn(day) {
        const s = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
        const e = s + 86400000;
        return events.filter(ev => ev.start < e && ev.end > s);
    }
    function iso(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function shiftMonth(n) { viewMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth() + n, 1); }
    function goToday() {
        const t = new Date();
        viewMonth = new Date(t.getFullYear(), t.getMonth(), 1);
        selected = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    }
    function refresh() {
        const end = new Date(gridStart);
        end.setDate(end.getDate() + 42);
        loader.command = [Quickshell.shellPath("scripts/calendar-events.py"), iso(gridStart), iso(end)];
        loader.running = true;
    }

    onOpenChanged: if (open) { goToday(); refresh(); }
    onViewMonthChanged: if (open) refresh()

    Process {
        id: loader
        onRunningChanged: pop.loading = running
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    pop.events = r.events;
                    pop.remote = r.remote;
                } catch (e) {}
            }
        }
    }
    Timer { interval: 300000; repeat: true; running: pop.open; onTriggered: pop.refresh() }

    RowLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 16

        // ---------------- Month grid ----------------
        ColumnLayout {
            Layout.preferredWidth: 7 * 38
            Layout.fillHeight: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Label {
                    text: Qt.formatDate(pop.viewMonth, "MMMM")
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Label {
                    text: Qt.formatDate(pop.viewMonth, "yyyy")
                    font.pixelSize: 16
                    color: Theme.textDim
                    Layout.fillWidth: true
                }
                IconButton { glyph: "󰅁"; onClicked: pop.shiftMonth(-1) }
                IconButton { glyph: "󰧞"; size: 10; onClicked: pop.goToday() }
                IconButton { glyph: "󰅂"; onClicked: pop.shiftMonth(1) }
            }

            Grid {
                columns: 7
                Layout.topMargin: 2
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    Label {
                        required property string modelData
                        width: 38; height: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.textFaint
                    }
                }
            }

            Grid {
                id: grid
                columns: 7
                Layout.fillHeight: true
                readonly property real cellH: height / 6

                Repeater {
                    model: 42
                    Item {
                        id: cell
                        required property int index
                        readonly property date day: new Date(pop.gridStart.getFullYear(), pop.gridStart.getMonth(), pop.gridStart.getDate() + index)
                        readonly property bool inMonth: day.getMonth() === pop.viewMonth.getMonth()
                        readonly property bool isToday: pop.sameDay(day, pop.today)
                        readonly property bool isSel: pop.sameDay(day, pop.selected)
                        readonly property var dayEvents: pop.eventsOn(day)
                        width: 38
                        height: grid.cellH

                        Rectangle {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -2
                            width: 28; height: 28; radius: 14
                            color: cell.isToday ? Theme.accent
                                 : cell.isSel ? Qt.rgba(1, 1, 1, 0.20)
                                 : dayMouse.containsMouse ? Theme.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            Label {
                                anchors.centerIn: parent
                                text: cell.day.getDate()
                                font.pixelSize: 12
                                font.weight: cell.isToday || cell.isSel ? Font.Bold : Font.Normal
                                font.features: { "tnum": 1 }
                                color: cell.isToday ? "white" : cell.inMonth ? Theme.text : Theme.textFaint
                            }
                        }
                        Row { // event dots
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                            spacing: 2
                            Repeater {
                                model: cell.dayEvents.slice(0, 3)
                                Rectangle {
                                    required property var modelData
                                    width: 4; height: 4; radius: 2
                                    color: modelData.color
                                    opacity: cell.inMonth ? 1 : 0.4
                                }
                            }
                        }
                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pop.selected = cell.day;
                                if (!cell.inMonth) pop.viewMonth = new Date(cell.day.getFullYear(), cell.day.getMonth(), 1);
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Qt.rgba(1, 1, 1, 0.10) }

        // ---------------- Agenda ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label {
                        text: pop.sameDay(pop.selected, pop.today) ? "Today" : Qt.formatDate(pop.selected, "dddd")
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    Label {
                        text: Qt.formatDate(pop.selected, "d MMMM yyyy")
                        color: Theme.textDim
                        font.pixelSize: 12
                    }
                }
                IconButton {
                    glyph: "󰏌"
                    onClicked: {
                        pop.shell.openPopup = "";
                        Quickshell.execDetached(["/opt/google/chrome/google-chrome", "--profile-directory=Default", "--app-id=kjbdgfilnfhdoflbpgamdcdgpehopbep"]);
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: pop.eventsOn(pop.selected)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: ev
                    required property var modelData
                    width: list.width
                    height: evCol.implicitHeight + 14
                    radius: 12
                    color: Theme.well

                    Rectangle {
                        anchors { left: parent.left; leftMargin: 8; top: parent.top; bottom: parent.bottom; margins: 8 }
                        width: 3; radius: 2
                        color: ev.modelData.color
                    }
                    Column {
                        id: evCol
                        anchors { left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Label { width: parent.width; text: ev.modelData.title; font.weight: Font.DemiBold }
                        Label {
                            width: parent.width
                            font.pixelSize: 11
                            color: Theme.textDim
                            text: (ev.modelData.allDay ? "All day"
                                  : Qt.formatTime(new Date(ev.modelData.start), "HH:mm") + " – " + Qt.formatTime(new Date(ev.modelData.end), "HH:mm"))
                                  + (ev.modelData.location ? "  ·  " + ev.modelData.location : "")
                        }
                    }
                }

                // Empty / setup states
                Column {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: 6
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "󰃭"; font.pixelSize: 26; color: Theme.textFaint }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pop.loading && pop.events.length === 0 ? "Loading…" : "No events"
                        color: Theme.textFaint
                    }
                    HoverBox {
                        visible: !pop.remote
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: connectLbl.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: hovered ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                        onClicked: { pop.shell.openPopup = ""; Quickshell.execDetached(["evolution"]); }
                        Label { id: connectLbl; anchors.centerIn: parent; text: "Connect Google Calendar"; color: "white"; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    }
                }
            }
        }
    }

    component IconButton: HoverBox {
        id: ib
        property alias glyph: ic.glyph
        property int size: 15
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        Icon { id: ic; anchors.centerIn: parent; font.pixelSize: ib.size; color: Theme.textDim }
    }
}
