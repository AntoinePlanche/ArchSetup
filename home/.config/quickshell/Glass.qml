import QtQuick

// A rounded glass card: tinted fill, top specular sheen, hairline rim.
Rectangle {
    id: root
    property color tint: Theme.panelTint
    property real sheen: 0.09

    color: tint
    radius: Theme.radius
    border.width: 1
    border.color: Theme.stroke

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.sheen) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
