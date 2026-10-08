//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

ShellRoot {
    Toasts {}
    MarketWidget {}
    WeatherWidget {}

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope
            required property ShellScreen modelData

            // Which popup is open on this screen ("" = none), and where each one anchors
            property string openPopup: ""
            property var anchors: ({})
            // Popup shown briefly without focus (volume knob), "" = none
            property string flash: ""
            readonly property var barWindow: bar

            function toggle(name) {
                if (openPopup === name) { openPopup = ""; return; }
                const a = Object.assign({}, anchors);
                a[name] = bar.geometryOf(name);
                anchors = a;
                openPopup = name;
            }

            function flashPopup(name) {
                if (openPopup === name) return;
                const a = Object.assign({}, anchors);
                a[name] = bar.geometryOf(name);
                anchors = a;
                flash = name;
                flashTimer.restart();
            }
            Timer { id: flashTimer; interval: 1500; onTriggered: scope.flash = "" }

            // Volume changed (keyboard knob, media keys, other apps): flash the volume slider.
            // Ignored for the first seconds so startup doesn't trigger it.
            Timer { id: settle; interval: 3000; running: true }
            Connections {
                target: Pipewire.defaultAudioSink?.audio ?? null
                enabled: !settle.running && scope.modelData.name === Hyprland.focusedMonitor?.name
                function onVolumeChanged() { scope.flashPopup("volume"); }
                function onMutedChanged() { scope.flashPopup("volume"); }
            }

            Bar { id: bar; shell: scope; screen: scope.modelData }

            CalendarPopup { shell: scope; screen: scope.modelData }
            BluetoothPopup { shell: scope; screen: scope.modelData }
            NetworkPopup { shell: scope; screen: scope.modelData }
            NotificationCenter { shell: scope; screen: scope.modelData }
            VolumePopup { shell: scope; screen: scope.modelData }
            ActionMenu {
                shell: scope
                screen: scope.modelData
                name: "windows"
                actions: [
                    { label: "Restart into Windows", glyph: "", color: "#4cc2ff",
                      command: ["sh", "-c", "$HOME/.local/bin/boot-to-windows"] },
                    { label: "Cancel", glyph: "󰜺" }
                ]
            }
            ActionMenu {
                shell: scope
                screen: scope.modelData
                name: "power"
                actions: [
                    { label: "Lock", glyph: "󰌾", command: ["hyprlock"] },
                    { label: "Restart", glyph: "󰜉", command: ["systemctl", "reboot"] },
                    { label: "Shut Down", glyph: "󰐥", color: "#ff6961", command: ["systemctl", "poweroff"] }
                ]
            }

            // `qs ipc call popup toggle calendar|network|notifications|bluetooth|volume|windows|power` (for keybinds)
            IpcHandler {
                target: "popup"
                enabled: scope.modelData.name === Hyprland.focusedMonitor?.name
                function toggle(name: string): void { scope.toggle(name); }
                function close(): void { scope.openPopup = ""; }
            }
        }
    }
}
