pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification daemon (replaces mako). Every notification stays in the history
// (tracked) until dismissed; `toasts` are the ones currently shown as banners.
Singleton {
    id: root

    readonly property var history: server.trackedNotifications.values.slice().reverse()
    property var toasts: []
    property var arrived: ({}) // notification id -> arrival time (ms)
    property int unread: 0
    property bool dnd: false
    property bool centerOpen: false

    onCenterOpenChanged: if (centerOpen) { unread = 0; toasts = []; }

    function hideToast(n) { toasts = toasts.filter(t => t !== n); }
    function dismiss(n) { hideToast(n); n.dismiss(); }
    function clearAll() {
        toasts = [];
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
    }
    // Clicking a notification: run its default action if it has one
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        dismiss(n);
    }
    function ago(n) {
        const t = arrived[n.id];
        if (!t) return "";
        const m = Math.floor((clock.date.getTime() - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m ago";
        return Qt.formatTime(new Date(t), "HH:mm");
    }
    function iconFor(n) {
        const src = n.image || n.appIcon;
        if (src && (src.startsWith("/") || src.includes("://"))) return src.startsWith("/") ? "file://" + src : src;
        const entry = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : DesktopEntries.heuristicLookup(n.appName);
        const name = src || entry?.icon || "";
        return name ? Quickshell.iconPath(name, true) : "";
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            const a = Object.assign({}, root.arrived);
            a[n.id] = Date.now();
            root.arrived = a;
            if (root.centerOpen) return;
            root.unread++;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.toasts = [n, ...root.toasts.filter(t => t.id !== n.id)].slice(0, 4);
        }
    }
}
