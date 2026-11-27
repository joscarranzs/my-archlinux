local mainMod = "SUPER"
local home = os.getenv("HOME") or ""

-- Load a satellite config and report a failure instead of aborting the reload.
-- Hyprland does not auto-load *.lua from the config directory, so every file
-- that has to take effect must be loaded here.
local function load(name)
    local ok, err = pcall(dofile, home .. "/.config/hypr/" .. name .. ".lua")
    if not ok then
        print(name .. ".lua failed: " .. tostring(err))
    end
end

-- Monitors first: hl.env() only reaches processes spawned after this point.
load("monitors")

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
    },
    general = {
        layout = "scrolling",
    },
    scrolling = {
        column_width = 1.0,
        fullscreen_on_one_column = true,
        wrap_focus = false,
        wrap_swapcol = false,
    },
})

hl.config({
    misc = {
        enable_anr_dialog = false,
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        disable_splash_rendering = true,
        disable_hyprland_guiutils_check = true,
        disable_scale_notification = true,
        disable_watchdog_warning = true,
        disable_xdg_env_checks = true,
    },
})

hl.config({
    render = {
        direct_scanout = true,
    },
})


hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus --new-window"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("chromium"))
hl.bind(mainMod .. " + CTRL + RETURN", hl.dsp.exec_cmd("kitty herdr"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + BackSpace", hl.dsp.exit())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())

-- Screenshot: overlay de recorte (region/ventana/pantalla) + editor de
-- anotaciones. La misma tecla abre y cierra.
hl.bind("PRINT", hl.dsp.exec_cmd("omasnap"))
hl.bind("F12", hl.dsp.exec_cmd("omasnap"))

-- Sin animaciones en el overlay de captura.
-- NO usar no_screen_share: Hyprland pinta de negro la capa excluida y rompe el recorte.
hl.layer_rule({
    name = "screenshot-overlay-no-anim",
    match = { namespace = "^omasnap$" },
    no_anim = true,
})

-- Lock the session with the Quickshell lockscreen.
hl.bind(mainMod .. " + CTRL + L", hl.dsp.exec_cmd(home .. "/.scripts/session/lockscreen.sh"))

-- Lid close: lock, wait for the lock surface's readiness marker, then suspend.
-- logind ignores the lid (etc/systemd/logind.conf.d/00-suspend.conf), so this
-- bind owns the flow; a sleep hook cannot (systemd freezes user.slice first,
-- and the locker would only load after the thaw). The bind lives here with the
-- other binds, not next to hl.monitor() calls, where switch binds stop firing.
-- locked = true: a second lid close while already locked must still suspend.
hl.bind("switch:on:Lid Switch", function()
    hl.exec_cmd(home .. "/.scripts/session/lock-and-suspend.sh")
end, { locked = true })

-- App launcher (Quickshell).
hl.unbind(mainMod .. " + SPACE")
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(home .. "/.scripts/session/launcher.sh"))

-- Web app creator (Quickshell).
hl.unbind(mainMod .. " + SHIFT + W")
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(home .. "/.scripts/session/webapp.sh"))

-- Calendar panel (Quickshell).
hl.unbind(mainMod .. " + C")
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(home .. "/.scripts/session/calendar.sh"))

-- Brightness panel (Quickshell). SUPER+B is the browser, so this is SHIFT+B.
hl.unbind(mainMod .. " + SHIFT + B")
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(home .. "/.scripts/session/brightness.sh"))

-- Wifi panel (Quickshell).
hl.unbind(mainMod .. " + N")
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(home .. "/.scripts/session/wifi.sh"))

-- Token/credits panel (Quickshell). Same toggle contract as the bar click: a
-- second press closes the panel instead of stacking another surface.
hl.unbind(mainMod .. " + T")
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(home .. "/.scripts/session/tokens.sh"))

-- Battery panel (Quickshell). Same toggle contract as the bar glyph: a second
-- press closes the plaque instead of stacking another surface.
hl.unbind(mainMod .. " + P")
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(home .. "/.scripts/session/battery.sh"))

-- Monitor panel (Quickshell): external displays only, hot-applied resolution
-- and scale. SHIFT keeps it clear of SUPER + M (exit). Same toggle contract.
hl.unbind(mainMod .. " + SHIFT + M")
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd(home .. "/.scripts/session/monitor.sh"))

-- Focus and reorder windows in scrolling layout
hl.bind(mainMod .. " + left",  hl.dsp.layout("focus l"))
hl.bind(mainMod .. " + right", hl.dsp.layout("focus r"))
hl.bind(mainMod .. " + up",    hl.dsp.layout("focus u"))
hl.bind(mainMod .. " + down",  hl.dsp.layout("focus d"))

hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.layout("swapcol r"))

-- Workspaces 1-5 only (no 0, no beyond 5)
for i = 1, 5 do
    local key = tostring(i)
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Theme, look and animations are generated by scripts/theme/apply-theme.py;
-- looknfeel.lua holds the look knobs that have no theme token.
load("theme")
load("look")
load("animations")
load("looknfeel")

-- Disable shadows to reduce GPU load on the iGPU.
hl.config({ decoration = { shadow = { enabled = false } } })

-- Wallpaper renderer (Quickshell)
hl.exec_cmd(home .. "/.scripts/session/quickshell-wallpaper.sh &")

-- Status bar (Quickshell). Same session-start path as the wallpaper: the script
-- waits for the Wayland socket, takes a lock so a second copy exits, and
-- respawns the renderer if it crashes.
hl.exec_cmd(home .. "/.scripts/session/bar.sh &")

-- Captive-portal watcher: when NetworkManager reports connectivity 'portal'
-- (open wifi gated by a login page, e.g. the university student network), it
-- finds the probe's redirect and opens it in the browser. The lock dedupes
-- with a manual run; `captive-portal.sh open` forces it, `status` inspects it.
hl.exec_cmd(home .. "/.scripts/session/captive-portal.sh &")

hl.config({ xwayland = { force_zero_scaling = true } })

-- File chooser dialogs: the xdg-desktop-portal-gtk picker (what browsers,
-- Flatpak and portal-aware apps open) is a plain toplevel, so the scrolling
-- layout tiles it full-width and it overflows this 1280x720 logical screen.
-- Float it, give it a sane size and always center it.
hl.window_rule({
    name = "file-chooser-portal",
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float = true,
    center = true,
    size = { "monitor_w * 0.7", "monitor_h * 0.75" },
})

-- Same treatment for native GTK file dialogs (GTK3/GTK4 apps that do not go
-- through the portal). Static rules match the initial title, hence the anchor.
hl.window_rule({
    name = "file-chooser-gtk-native",
    match = {
        initial_title = "^(Open File|Open Files|Save File|Save As|Select Folder|Select a Folder|Choose a Folder|Choose File|Abrir archivo|Abrir archivos|Guardar como|Guardar archivo|Seleccionar carpeta|Seleccionar archivo)$",
    },
    float = true,
    center = true,
    size = { "monitor_w * 0.7", "monitor_h * 0.75" },
})
-- Wayland defaults for processes Hyprland spawns itself (binds, exec_cmd).
-- The same values live in ~/.config/environment.d/wayland.conf, which is what
-- the systemd user manager reads: Hyprland does not read environment.d and
-- systemd does not read hl.env(), so both files are needed. Keep them in sync.
hl.env("GDK_BACKEND", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GDK_DPI_SCALE", "1")
hl.env("QT_QPA_PLATFORMTHEME", "gtk2")
