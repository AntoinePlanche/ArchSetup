import QtQuick

Rectangle {
    id: tg
    property bool checked: false
    signal toggled()
    implicitWidth: 38
    implicitHeight: 22
    radius: 11
    color: checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
    Behavior on color { ColorAnimation { duration: Theme.normal } }
    Rectangle {
        width: 18; height: 18; radius: 9
        y: 2
        x: tg.checked ? tg.width - width - 2 : 2
        color: "white"
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
}
