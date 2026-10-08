pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Current media player (YouTube/Deezer in the browser, Spotify...) + live spectrum from cava
Singleton {
    id: root

    // playerctld just mirrors other players; skip it
    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.includes("playerctld"))
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players.find(p => p.trackTitle) ?? null
    readonly property bool playing: player?.isPlaying ?? false
    // Indicator visibility: hidden 10 s after playback stops (paused browser tabs never go away)
    readonly property bool shown: player !== null && (playing || grace.running)
    onPlayingChanged: if (!playing) grace.restart()
    Timer { id: grace; interval: 10000 }

    readonly property int barCount: 6
    property var bars: new Array(barCount).fill(0)

    Process {
        running: root.playing
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]
        onRunningChanged: if (!running) root.bars = new Array(root.barCount).fill(0)
        stdout: SplitParser {
            onRead: line => { root.bars = line.split(";").filter(v => v !== "").map(Number); }
        }
    }
}
