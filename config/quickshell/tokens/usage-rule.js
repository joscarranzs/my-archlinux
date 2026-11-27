.pragma library

// The one ladder every usage bar walks.
//
// Green while there is room, gold at the warning threshold, red at the critical
// one, and muted when the reading is stale or missing -- a colour is a claim
// about a number, and that number has to be true right now. The thresholds come
// from the look tokens, so the plaque, the bar's own glyph and the helper's
// desktop notices cannot disagree about where "getting close" starts.
//
// One rule, every call site: a bar that tunes its own pair of numbers is how the
// same panel ended up painting three different scales for the same question.

function usable(percent) {
    return percent !== null && percent !== undefined && isFinite(percent);
}

/// The bar's own colour.
function fill(appearance, percent, muted) {
    if (muted || !usable(percent))
        return appearance.textMuted;
    if (percent >= appearance.tokensCriticalThreshold)
        return appearance.danger;
    if (percent >= appearance.tokensAlertThreshold)
        return appearance.gilt;
    return appearance.accent;
}

/// The number beside the bar: plain ink until it has something to say.
function ink(appearance, percent, muted) {
    if (muted || !usable(percent))
        return appearance.textMuted;
    if (percent >= appearance.tokensCriticalThreshold)
        return appearance.danger;
    if (percent >= appearance.tokensAlertThreshold)
        return appearance.gilt;
    return appearance.text;
}
