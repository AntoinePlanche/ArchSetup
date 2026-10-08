import QtQuick
import Quickshell

// Small glass menu whose right edge lines up with its bar button
Popup {
    id: menu
    // [{ label, glyph, color?, command? }] — an entry without command just closes the menu
    property var actions: []

    placement: "right"
    cardWidth: 232
    cardHeight: col.implicitHeight + 12
    cardRadius: 18

    Column {
        id: col
        anchors { fill: parent; margins: 6 }
        spacing: 2

        Repeater {
            model: menu.actions
            HoverBox {
                id: row
                required property var modelData
                required property int index
                width: col.width
                height: 40
                radius: 12
                onClicked: {
                    menu.shell.openPopup = "";
                    if (modelData.command) Quickshell.execDetached(modelData.command);
                }

                Rectangle { // icon tile
                    id: tile
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 9
                    color: row.hovered ? (row.modelData.color ?? Theme.accent) : Theme.well
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Icon {
                        anchors.centerIn: parent
                        glyph: row.modelData.glyph
                        font.pixelSize: 15
                        color: row.hovered ? "white" : (row.modelData.color ?? Theme.text)
                    }
                }
                Label {
                    anchors { left: tile.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                    text: row.modelData.label
                    font.weight: Font.Medium
                }
            }
        }
    }
}
