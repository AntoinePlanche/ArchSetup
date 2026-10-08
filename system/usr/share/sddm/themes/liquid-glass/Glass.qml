import QtQuick
import QtQuick.Effects

// Frosted glass: shows the blurred wallpaper behind this item, clipped to a
// rounded rect, with a light tint, top sheen and hairline rim.
Item {
    id: root
    required property Item blurSource // full-screen blurred wallpaper
    property real radius: height / 2
    property color tint: Qt.rgba(0.08, 0.08, 0.10, 0.28)

    readonly property point origin: mapToItem(blurSource, 0, 0)

    ShaderEffectSource {
        id: behind
        anchors.fill: parent
        sourceItem: root.blurSource
        sourceRect: Qt.rect(root.origin.x, root.origin.y, root.width, root.height)
        visible: false
    }
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: behind
        maskEnabled: true
        maskSource: shape
        brightness: -0.08
        saturation: 0.25
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
    }
    Rectangle { // sheen
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
