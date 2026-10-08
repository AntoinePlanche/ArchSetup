import QtQuick

Item {
    implicitWidth: 12
    implicitHeight: 12
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.18)
    }
    Rectangle { // rotating arc dot
        width: 4; height: 4; radius: 2
        color: Theme.text
        x: parent.width / 2 - 2 + Math.cos(angle) * (parent.width / 2 - 1)
        y: parent.height / 2 - 2 + Math.sin(angle) * (parent.height / 2 - 1)
        property real angle: 0
        NumberAnimation on angle { from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite; running: parent.visible }
    }
}
