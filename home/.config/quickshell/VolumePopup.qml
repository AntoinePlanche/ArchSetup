import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// macOS-like vertical volume slider
Popup {
    id: pop
    name: "volume"
    cardWidth: 64
    cardHeight: 236
    cardRadius: 32

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    function setVol(v) {
        if (!sink?.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1, v));
        if (sink.audio.muted && v > 0) sink.audio.muted = false;
    }

    PwObjectTracker { objects: [pop.sink] }

    Label {
        id: pct
        anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: pop.muted ? "Muted" : Math.round(pop.vol * 100)
        font.pixelSize: pop.muted ? 11 : 13
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: pop.muted ? Theme.textDim : Theme.text
    }

    Rectangle {
        id: track
        anchors { top: pct.bottom; topMargin: 10; bottom: muteBtn.top; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
        width: 40
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.10)
        clip: true
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        Rectangle {
            id: fill
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.max(parent.radius * 2 * (pop.vol > 0 ? 1 : 0), parent.height * (pop.muted ? 0 : pop.vol))
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.82) }
            }
            Behavior on height { enabled: !drag.pressed; NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function apply(y) { pop.setVol(1 - y / height); }
            onPressed: m => apply(m.y)
            onPositionChanged: m => { if (pressed) apply(m.y); }
            onWheel: w => pop.setVol(pop.vol + (w.angleDelta.y > 0 ? 0.05 : -0.05))
        }
    }

    HoverBox {
        id: muteBtn
        anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
        width: 40; height: 40; radius: 20
        onClicked: if (pop.sink?.audio) pop.sink.audio.muted = !pop.sink.audio.muted
        Icon {
            anchors.centerIn: parent
            glyph: VolumeGlyph.of(pop.vol, pop.muted)
            font.pixelSize: 18
            color: pop.muted ? Theme.textDim : Theme.text
        }
    }
}
