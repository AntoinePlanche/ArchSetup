import QtQuick

// Nerd Font glyph
Text {
    property alias glyph: root.text
    id: root
    color: Theme.text
    font.family: Theme.iconFont
    font.pixelSize: 15
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
