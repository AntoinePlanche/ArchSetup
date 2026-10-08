-- ~/.config/hypr/hyprland.lua
-- Converti depuis hyprland.conf (hyprlang) vers le nouveau format Lua (Hyprland 0.55+)

-------------------------
---- CLAVIER & SOURIS ----
-------------------------
hl.config({
    input = {
        kb_layout      = "us",
        sensitivity    = 0.0,
        accel_profile  = "flat",
    },
})

--------------------------------------
---- APPARENCE (LIGHT MODE) ----------
--------------------------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(0066ccee)", "rgba(3388ffee)" }, angle = 45 },
            inactive_border = "rgba(ccccccaa)",
        },
        -- master: one main window on the left half, all others share the right half
        layout      = "master",
        -- Drag the gap between tiled windows with the mouse to resize them
        resize_on_border = true,
        allow_tearing = true,
    },

    master = {
        mfact = 0.5,
    },
    
    decoration = {
        rounding         = 8,
        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        blur = {
            enabled = true,
            -- Light enough that the wallpaper stays recognisable behind glass surfaces
            -- (was size 8 / passes 3: everything turned into a flat colour)
            size    = 6,
            passes  = 2,
        },
    },

    render = {
        direct_scanout = 2,
    }
})

-- Règle pour CS2 : Débloquer le tearing / Immediate scanout (latence minimale)


hl.window_rule({
    match     = { class = "cs2" },
    immediate = true,
})

-- Welcome fastfetch terminal (autostart): floating, centered, 1/4 of the screen
hl.window_rule({
    name   = "welcome-fastfetch",
    match  = { class = "^com\\.welcome\\.fastfetch$" },
    float  = true,
    size   = "monitor_w*0.5 monitor_h*0.5",
    center = true,
})

-- Règle de layer pour flouter waybar
hl.layer_rule({
    match = { namespace = "waybar" },
    blur  = true,
})

-- Quickshell bar + popovers: liquid-glass blur. ignore_alpha keeps the soft
-- popup shadows (low alpha) from being blurred; popups animate themselves.
hl.layer_rule({
    match        = { namespace = "^qs-(bar|popup|notify)$" },
    blur         = true,
    ignore_alpha = 0.3,
})
-- Desktop widgets (weather, markets): liquid glass cards with a light tint, so blur
-- everything but the fully transparent corners around the rounded card
hl.layer_rule({
    match        = { namespace = "^qs-widget$" },
    blur         = true,
    ignore_alpha = 0.05,
})
hl.layer_rule({
    match   = { namespace = "^qs-popup$" },
    no_anim = true,
})

-- Rofi (Spotlight theme, ~/.config/rofi/spotlight.rasi): rofi is fullscreen with a
-- faint tint, so the whole desktop gets blurred behind the glass card; fade in/out.
hl.layer_rule({
    match     = { namespace = "^rofi$" },
    blur      = true,
    animation = "fade",
})

-------------------------
---- AUTOSTART -----------
-------------------------
hl.on("hyprland.start", function()
    -- Bar + popovers (Quickshell, ~/.config/quickshell). Replaces waybar + waybar-fullscreen.sh
    hl.exec_cmd("env QS_ICON_THEME=Papirus-Dark qs")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper-rotate.sh")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    -- Light theme, or dark while the WOLED monitor is plugged in (burn-in care)
    hl.exec_cmd("~/.config/hypr/scripts/oled-theme.sh")
    -- Screen off after 10 min idle (~/.config/hypr/hypridle.conf)
    hl.exec_cmd("hypridle")
    -- Welcome terminal with fastfetch (~/.config/fastfetch, hook at the end of ~/.zshrc)
    hl.exec_cmd("env FASTFETCH_ON_START=1 ghostty --class=com.welcome.fastfetch")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP & gnome-keyring-daemon --start --components=secrets")
    -- New-machine setup wizard (~/Workspace/ArchSetup): logins, Secure Boot, plugins.
    -- Exits at once when nothing is left to do.
    hl.exec_cmd("~/.local/bin/arch-setup-wizard --if-pending")
end)

--------------------------------------
---- RACCOURCIS PRINCIPAUX ------------
--------------------------------------
local mainMod = "SUPER"

-- Apps
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd("ghostty"))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("google-chrome-stable"))
hl.bind(mainMod .. " + C",      hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("nautilus"))
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd("~/.local/bin/spotlight"))
-- Fuzzy launcher now bound in zsh (Alt+r)

-- Windows
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
-- Maximize keeps the bar and the app's own UI (Chrome tabs); F is real fullscreen
hl.bind(mainMod .. " + A",      hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen({ action = "toggle" }))
-- Make the focused window the master (left half) and keep focus on it.
-- Already the master: do nothing (the built-in would swap it away with the next window).
hl.bind(mainMod .. " + M", function()
    local w = hl.get_active_window()
    if w and not w.floating and not (w.layout and w.layout.is_master) then
        hl.dispatch(hl.dsp.layout("swapwithmaster master"))
    end
end)

-- Session (exit moved off SUPER+SHIFT+M, too close to window keys)
hl.bind(mainMod .. " + SHIFT + Escape", hl.dsp.exit())

------------------------------------------------------------
---- DÉPLACEMENT DU FOCUS (Changer de fenêtre active) --------
------------------------------------------------------------
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

--------------------------------------------------------------------------
---- DÉPLACEMENT DES FENÊTRES (Basculer Droite / Gauche / Haut / Bas) ------
--------------------------------------------------------------------------
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

--------------------------------------------
---- WORKSPACES (Bureaux virtuels) -----------
--------------------------------------------
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
    -- Send the window away but stay here (to gather several windows in a row)
    hl.bind(mainMod .. " + CTRL + " .. i, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Souris : Déplacer/Redimensionner
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-------------------------------
---- Capture d'écran ------------
-------------------------------
-- SUPER+Z: show / hide the auto-hidden bar (OLED monitor). Was a tap on Super alone,
-- too easy to trigger by accident.
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("qs ipc call bar toggle"))

hl.bind(mainMod .. " + SHIFT + S",hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"))

-------------------------------
---- Touches multimédia ---------
-------------------------------
-- Keychron knob: rotate = volume (2% per notch, capped at 100%), press = mute
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-------------------------
---- Écran ----------------
-------------------------
hl.monitor({
    output   = "desc:ASUSTek COMPUTER INC XG27AQWMG TCLMTF028142",
    mode     = "2560x1440@280",
    position = "auto",
    scale    = 1,
    bitdepth = 10, -- à vérifier : le champ bitdepth n'est pas confirmé dans l'API hl.monitor(),
                       -- garde-le en commentaire si Hyprland refuse de charger la config
})

-------------------------------------------------
---- HYPRSPACE (workspace overview, SUPER+Tab) ---
-------------------------------------------------
-- Managed by hyprpm (`hyprpm list`); rebuilt by `hyprpm update` after Hyprland updates
-- (done by ~/.local/bin/auto-update.sh). hyprpm loads it at login, after this file
-- was read, then the config is reloaded so the settings below apply.
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpm reload && hyprctl reload config-only")
end)

-- Plugin settings only exist once the plugin is loaded
if hl.plugin.overview then
hl.config({
    plugin = {
        overview = {
            autoDrag           = true,  -- click + drag a window onto another workspace to move it
            exitOnClick        = true,  -- a click without dragging closes the overview
            exitOnSwitch       = true,  -- clicking a workspace switches to it and closes
            showNewWorkspace   = true,  -- empty slot at the end: drop a window there for a fresh workspace
            showEmptyWorkspace = true,
        },
    },
})
end

hl.bind(mainMod .. " + Tab", function()
    hl.plugin.overview.toggle()
end, { description = "Toggle Hyprspace workspace overview" })

-------------------------------------------------
---- HYPRFOCUS (focus-change animation) ----------
-------------------------------------------------
-- Also managed by hyprpm (repo: hyprland-plugins). A soft "breath" on the newly
-- focused window: it dips to 99% and springs back, with a light opacity blink
-- when focus follows the mouse. Settings only exist once the plugin is loaded.
local function plugin_loaded(name)
    for _, p in ipairs(hl.get_loaded_plugins()) do
        if p.name == name then return true end
    end
    return false
end

if plugin_loaded("hyprfocus") then
    hl.config({
        plugin = {
            hyprfocus = {
                keyboard_focus_animation = "shrink", -- SUPER+arrows, alt-tab, etc.
                mouse_focus_animation    = "flash",  -- hover / click focus
                animate_floating         = true,
                shrink_percentage        = 0.99,     -- barely-there scale dip
                fade_opacity             = 0.90,     -- gentle blink, never a strobe
            },
        },
    })

    -- Quick ease-out into the dip, then a soft spring settle back to rest
    hl.curve("focusDip",    { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
    hl.curve("focusSettle", { type = "spring", mass = 1, stiffness = 180, dampening = 18 })
    hl.animation({ leaf = "hyprfocusIn",  enabled = true, speed = 1.6, bezier = "focusDip" })
    hl.animation({ leaf = "hyprfocusOut", enabled = true, speed = 4.5, spring = "focusSettle" })
end
