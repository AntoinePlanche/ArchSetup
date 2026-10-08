pragma Singleton

import Quickshell

Singleton {
    function of(vol, muted) {
        if (muted || vol <= 0) return "󰝟";
        if (vol < 0.34) return "󰕿";
        if (vol < 0.67) return "󰖀";
        return "󰕾";
    }
}
