import QtQuick
import QtQuick.Shapes

// Liquid glass card (Apple-style): a light tint over the backdrop that Hyprland blurs
// (layer rule for qs-widget in hyprland.lua), a top sheen, and a rim that only catches
// light at the top-left and bottom-right corners. Children are drawn on top.
Item {
    id: root
    property real radius: 26
    property color tintTop: Qt.rgba(1, 1, 1, 0.08)
    property color tintBottom: Qt.rgba(1, 1, 1, 0.04)
    property real sheen: 0.10

    // Tint
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.tintTop }
            GradientStop { position: 1.0; color: root.tintBottom }
        }
    }

    // Top sheen
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.sheen) }
            GradientStop { position: 0.30; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    // Rim: light catches the top-left and bottom-right corners, fades elsewhere
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: root.width / 2
                centerY: root.height / 2
                angle: 135
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.50) }
                GradientStop { position: 0.12; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.38; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.62; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.50) }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.radius }
            PathRectangle { x: 1.2; y: 1.2; width: root.width - 2.4; height: root.height - 2.4; radius: root.radius - 1.2 }
        }
    }
}
