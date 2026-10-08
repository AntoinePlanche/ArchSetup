pragma Singleton

import QtQuick
import Quickshell

// Shared look: dark liquid glass (Hyprland blurs everything behind these surfaces)
Singleton {
    readonly property string font: "Inter"
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    readonly property color text: "#f5f5f7"
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.55)
    readonly property color textFaint: Qt.rgba(1, 1, 1, 0.32)
    readonly property color accent: "#0a84ff"
    readonly property color red: "#ff453a"
    readonly property color green: "#30d158"

    // Glass surfaces
    readonly property color barTint: Qt.rgba(0.08, 0.08, 0.10, 0.30)
    readonly property color panelTint: Qt.rgba(0.10, 0.10, 0.12, 0.46)
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.16)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.10)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.16)
    readonly property color well: Qt.rgba(1, 1, 1, 0.07)

    // OLED monitors (part of `hyprctl monitors` description): the bar auto-hides there.
    // Keep in sync with OLED_MONITORS in ~/.config/hypr/scripts/oled-theme.sh
    readonly property var oledMonitors: ["XG27AQWMG"]

    readonly property int barHeight: 36
    readonly property int barMargin: 6
    readonly property int barSide: 10
    readonly property int popupGap: 8
    readonly property int radius: 22

    readonly property int fast: 140
    readonly property int normal: 220
}
