pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The default audio output, read and written through Quickshell's PipeWire
// service. The value is live: no wpctl process per tick, and no risk of the
// panel showing a number that the mixer already moved on from.
//
// DUPLICATED ON PURPOSE in bar/services/ and volume/services/. Quickshell does
// not register a symlinked singleton in a directory's synthetic qmldir — the
// link loads as "AudioOutput is not defined" and the surface silently keeps
// drawing with the property undefined. So both copies are real files: change
// one, copy it over the other, or the bar glyph and the panel will disagree.
//
// `available` guards every read because the node arrives asynchronously and the
// bindings evaluate before PipeWire has answered.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool available: sink != null && sink.audio != null

    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available ? sink.audio.muted : false
    readonly property int percent: Math.round(root.volume * 100)

    readonly property string deviceName: {
        if (!available) return "No output";
        return sink.description && sink.description.length > 0
            ? sink.description
            : sink.name;
    }

    // The glyph follows the level, not just mute: a bar that always shows
    // "volume_up" while the mixer sits at 20 % is the same lie as a hardcoded
    // workspace index.
    readonly property string glyph: root.muted || root.volume <= 0.001
        ? "volume_off"
        : (root.volume < 0.34 ? "volume_mute"
            : (root.volume < 0.67 ? "volume_down" : "volume_up"))

    // Keeps the node subscribed. Without it the properties exist but never update,
    // so the panel would show whatever it read at start-up.
    property PwObjectTracker tracker: PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    function setVolume(value) {
        if (!available) return;
        sink.audio.volume = Math.max(0, Math.min(1, value));
    }

    function adjust(delta) {
        root.setVolume(root.volume + delta);
    }

    function toggleMute() {
        if (!available) return;
        sink.audio.muted = !sink.audio.muted;
    }
}
