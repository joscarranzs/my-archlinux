-- Generated look
hl.config({
    general = {
        gaps_in = {{look.margins.gapsIn}},
        -- Sides are narrower than top/bottom on purpose: the scrolling layout
        -- adds gaps_in to both sides of every column, so this remainder is what
        -- lands the window border exactly on the bar's floating margin.
        gaps_out = {
            top = {{look.margins.gapsEdge}},
            right = {{look.margins.gapsSide}},
            bottom = {{look.margins.gapsEdge}},
            left = {{look.margins.gapsSide}},
        },
        border_size = {{look.borders.width}},
    },
    decoration = {
        rounding = {{look.borders.radius.md}},
        active_opacity = {{look.opacity.active}},
        inactive_opacity = {{look.opacity.inactive}},
        fullscreen_opacity = {{look.opacity.active}},
        blur = {
            enabled = {{look.blur.enabled}},
        },
    },
})
