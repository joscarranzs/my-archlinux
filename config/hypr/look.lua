-- Generated look
hl.config({
    general = {
        gaps_in = 4,
        -- Sides are narrower than top/bottom on purpose: the scrolling layout
        -- adds gaps_in to both sides of every column, so this remainder is what
        -- lands the window border exactly on the bar's floating margin.
        gaps_out = {
            top = 6,
            right = 2,
            bottom = 6,
            left = 2,
        },
        border_size = 1,
    },
    decoration = {
        rounding = 6,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,
        blur = {
            enabled = false,
        },
    },
})
