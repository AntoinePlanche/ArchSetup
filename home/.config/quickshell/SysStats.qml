pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU / RAM / GPU usage, sampled every 2 s
Singleton {
    id: root
    property int cpu: 0
    property int mem: 0
    property int gpu: 0

    property string netType: "" // "ethernet" | "wifi" | "" (offline)
    property string netName: ""
    property var netDevices: [] // [{ device, type, state, connection }]

    property var lastCpu: null

    // Network: first connected ethernet/wifi device, refreshed on every NetworkManager change
    Process {
        id: netQuery
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.netDevices = text.trim().split("\n").map(l => l.split(":"))
                    .filter(f => f[1] === "ethernet" || f[1] === "wifi")
                    .map(f => ({ device: f[0], type: f[1], state: f[2], connection: f.slice(3).join(":").replace(/\\:/g, ":") }));
                const up = root.netDevices.find(d => d.state === "connected");
                root.netType = up ? up.type : "";
                root.netName = up ? up.connection : "";
            }
        }
    }
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: netQuery.running = true }
    }
    Component.onCompleted: netQuery.running = true

    // GPU load of the card with the most VRAM (the dGPU next to an iGPU). Found by sysfs, not by
    // cardN or PCI address: cardN isn't stable across boots and the address differs per machine.
    // Only amdgpu exposes gpu_busy_percent; elsewhere the path stays empty and the GPU stat is unavailable.
    property string gpuBusyPath: ""
    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/drm/card*/device; do [ -r $d/gpu_busy_percent ] && echo \"$(cat $d/mem_info_vram_total 2>/dev/null || echo 0) $(readlink -f $d)/gpu_busy_percent\"; done | sort -n | tail -1 | cut -d' ' -f2"]
        stdout: StdioCollector { onStreamFinished: root.gpuBusyPath = text.trim() }
    }
    FileView { id: gpuFile; path: root.gpuBusyPath; blockLoading: true }
    FileView { id: statFile; path: "/proc/stat"; blockLoading: true }
    FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload(); memFile.reload(); gpuFile.reload();

            const f = statFile.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total;
                if (dt > 0) root.cpu = Math.round(100 * (1 - (idle - root.lastCpu.idle) / dt));
            }
            root.lastCpu = { idle, total };

            const m = memFile.text();
            const kb = k => Number((m.match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
            const memTotal = kb("MemTotal");
            if (memTotal) root.mem = Math.round(100 * (1 - kb("MemAvailable") / memTotal));

            root.gpu = parseInt(gpuFile.text()) || 0;
        }
    }
}
