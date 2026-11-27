/* Generated from theme/colors.json by scripts/theme/apply-theme.py — do not edit.
 *
 * Adwaita reads its colours from these named colours, so redefining them puts a
 * GTK3 app on this palette without replacing the theme: geometry, widget
 * behaviour and every other style stay Adwaita's, only the ink changes. That is
 * the whole point of the exercise — one art direction across the desktop, not a
 * second theme to maintain.
 *
 * Only colours are defined here. Geometry belongs to the theme, and a rule that
 * re-draws a widget internals is what breaks a GTK app on the next release.
 */
@define-color theme_fg_color {{text.ink}};
@define-color theme_text_color {{text.ink}};
@define-color theme_bg_color {{surface.base}};
@define-color theme_base_color {{surface.raised}};
@define-color theme_selected_bg_color {{accent.primary}};
@define-color theme_selected_fg_color {{onAccent.primary}};
@define-color theme_unfocused_fg_color {{text.inkMuted}};
@define-color theme_unfocused_text_color {{text.ink}};
@define-color theme_unfocused_bg_color {{surface.base}};
@define-color theme_unfocused_base_color {{surface.raised}};
@define-color theme_unfocused_selected_bg_color {{accent.primary}};
@define-color theme_unfocused_selected_fg_color {{onAccent.primary}};
@define-color insensitive_fg_color {{text.inkFaint}};
@define-color insensitive_bg_color {{surface.raised}};
@define-color insensitive_base_color {{surface.raised}};
@define-color borders {{surface.border}};
@define-color unfocused_borders {{surface.line}};
@define-color content_view_bg {{surface.raised}};
@define-color text_view_bg {{surface.raised}};
@define-color warning_color {{signal.yellow}};
@define-color error_color {{signal.red}};
@define-color success_color {{signal.green}};
@define-color warning_fg_color {{onAccent.signal}};
@define-color warning_bg_color {{signal.yellow}};
@define-color error_fg_color {{onAccent.signal}};
@define-color error_bg_color {{signal.red}};
