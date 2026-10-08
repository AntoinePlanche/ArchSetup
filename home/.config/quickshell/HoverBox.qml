import QtQuick

// Rounded hit area that lights up on hover / press
Rectangle {
    id: root
    property bool active: false
    signal clicked(var mouse)
    signal wheel(var wheel)
    default property alias content: inner.data
    property alias hovered: mouse.containsMouse
    property alias acceptedButtons: mouse.acceptedButtons

    radius: 10
    color: mouse.pressed ? Theme.pressed : (mouse.containsMouse || active) ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.fast } }

    Item { id: inner; anchors.fill: parent }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: m => root.clicked(m)
        onWheel: w => root.wheel(w)
    }
}
