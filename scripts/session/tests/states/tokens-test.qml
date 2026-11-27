import QtQuick
import Quickshell
import "@URL@/tokens/components"

// Empty and error, forced through the panel's own `feed` property: no blob at
// all (the feed has not answered yet) and a blob whose blocks carry errors.
//
// The stub has the same shape as services/TokenFeed, so the panel's bindings are
// exercised as written. Nothing here reads the network or the real feed file.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    function check(name, condition, detail) {
        if (condition) {
            root.pass += 1;
            console.log("PASS " + name);
        } else {
            root.fail += 1;
            console.log("FAIL " + name + " :: " + (detail === undefined ? "" : detail));
        }
    }

    function byText(item, text, found) {
        if (item.text !== undefined && item.text === text)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byText(item.children[i], text, found);
        return found;
    }

    QtObject {
        id: stubFeed

        property var data: ({})
        readonly property bool hasData: !!data.tokens
        readonly property var nous: data.nous || ({})
        readonly property var go: data.go || ({})
        readonly property var tokens: data.tokens || ({})
    }

    Window {
        width: 470
        height: 460
        visible: true

        TokensPanel {
            id: panel
            anchors.centerIn: parent
            feed: stubFeed
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            root.check("an empty feed puts the plaque in reading…",
                root.byText(panel, "reading…", []).length === 1);
            root.check("an empty feed carries no allowance rows",
                root.byText(panel, "no data", []).length === 0);
            root.check("an empty feed still draws its metric cells", panel.width > 0);
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            stubFeed.data = ({
                tokens: {},
                go: { error: "429 rate limited" },
                nous: { error: "unauthorized", ok: false }
            });
        }
    }

    Timer {
        interval: 900
        running: true
        onTriggered: {
            const goError = root.byText(panel, "429 rate limited", []);
            root.check("a refused allowance request is named", goError.length === 1,
                goError.length);
            if (goError.length === 1) {
                root.check("the refusal is visible", goError[0].visible);
                root.check("the refusal is muted ink, not a wash",
                    goError[0].opacity === 1
                    && Qt.colorEqual(goError[0].color, panel.appearance.textMuted),
                    goError[0].color);
            }

            const nousError = root.byText(panel, "unauthorized", []);
            root.check("a refused balance request is named", nousError.length === 1,
                nousError.length);
        }
    }

    // Context pressure: the ceiling is reported even when the buffer is not, so
    // the row has to survive a null percentage instead of painting nothing.
    Timer {
        interval: 1100
        running: true
        onTriggered: {
            stubFeed.data = ({
                nous: { ok: true, balance_usd: 26.7, spent_usd: 8.2, purchased_usd: 34.9 },
                go: { ok: true, windows: [] },
                tokens: {
                    session: {
                        id: "s", model: "deepseek-v4.1-flash", provider: "opencode-go",
                        route: "plan", input: 1000, output: 100, cache_read: 2000,
                        cache_write: 0, calls: 3,
                        context_used: 95171, context_max: 1048576, context_pct: 9,
                        context_estimated: false
                    }
                }
            });
        }
    }

    Timer {
        interval: 1400
        running: true
        onTriggered: {
            const percent = root.byText(panel, "9%", []);
            root.check("the context percentage is painted", percent.length === 1,
                percent.length);
            const capacity = root.byText(panel, "95K / 1.0M", []);
            root.check("the model's context capacity is painted", capacity.length === 1,
                capacity.length);
            root.check("9 % of the window is not near the limit",
                Qt.colorEqual(panel.contextFill, panel.appearance.accent),
                panel.contextFill);
        }
    }

    Timer {
        interval: 1700
        running: true
        onTriggered: {
            stubFeed.data = ({
                nous: { ok: true, balance_usd: 26.7, spent_usd: 8.2, purchased_usd: 34.9 },
                go: { ok: true, windows: [] },
                tokens: {
                    session: {
                        id: "s", model: "deepseek-v4.1-flash", provider: "opencode-go",
                        route: "plan", input: 1000, output: 100, cache_read: 2000,
                        cache_write: 0, calls: 3,
                        context_used: null, context_max: 1048576, context_pct: null,
                        context_source: null, context_estimated: false
                    }
                }
            });
        }
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            const blank = root.byText(panel, "— / 1.0M", []);
            root.check("an unknown buffer keeps the capacity, blank percentage",
                blank.length === 1, blank.length);
            root.check("no percentage is invented for an unknown buffer",
                root.byText(panel, "null%", []).length === 0);
            root.check("a blank percentage is muted ink",
                Qt.colorEqual(panel.contextFill, panel.appearance.textMuted),
                panel.contextFill);
        }
    }

    // The ladder itself: gold at the warning threshold, red at the critical one,
    // on the ctx bar and on the allowance bars, from the same rule.
    Timer {
        interval: 2100
        running: true
        onTriggered: {
            stubFeed.data = ({
                nous: { ok: true, balance_usd: 26.7, spent_usd: 8.2, purchased_usd: 34.9 },
                go: {
                    ok: true,
                    windows: [
                        { key: "rolling", percent: 55, resets_at: "2026-11-29T18:13:02Z" },
                        { key: "weekly", percent: 85, resets_at: "2026-11-29T18:13:02Z" }
                    ]
                },
                tokens: {
                    session: {
                        id: "s", model: "deepseek-v4.1-flash", provider: "opencode-go",
                        route: "plan", input: 1000, output: 100, cache_read: 2000,
                        cache_write: 0, calls: 3,
                        context_used: 860000, context_max: 1048576, context_pct: 82,
                        context_estimated: false
                    }
                }
            });
        }
    }

    Timer {
        interval: 2600
        running: true
        onTriggered: {
            root.check("the ctx bar turns red at the critical threshold",
                Qt.colorEqual(panel.contextFill, panel.appearance.danger),
                panel.contextFill);
            const warning = root.byText(panel, "55%", []);
            root.check("an allowance at the warning threshold turns gold",
                warning.length === 1
                && Qt.colorEqual(warning[0].color, panel.appearance.gilt),
                warning.length === 1 ? warning[0].color : "not found");
            const critical = root.byText(panel, "85%", []);
            root.check("an allowance at the critical threshold turns red",
                critical.length === 1
                && Qt.colorEqual(critical[0].color, panel.appearance.danger),
                critical.length === 1 ? critical[0].color : "not found");
        }
    }

    // A model whose ceiling has not been cached yet: the row must stay, with the
    // buffer it knows and no invented window.
    Timer {
        interval: 2700
        running: true
        onTriggered: {
            stubFeed.data = ({
                nous: { ok: true, balance_usd: 26.7, spent_usd: 8.2, purchased_usd: 34.9 },
                go: { ok: true, windows: [] },
                tokens: {
                    session: {
                        id: "s", model: "mimo-v2.6-flash", provider: "opencode-go",
                        route: "plan", input: 1000, output: 100, cache_read: 2000,
                        cache_write: 0, calls: 3,
                        context_used: 95171, context_max: null, context_pct: null,
                        context_source: null, context_estimated: false,
                        context_window_known: false
                    }
                }
            });
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            const unknown = root.byText(panel, "95K / —", []);
            root.check("an uncached window keeps the row and the buffer it knows",
                unknown.length === 1 && unknown[0].visible, unknown.length);
            root.check("an uncached window is not a percentage",
                panel.contextCapacity === false && panel.contextPercent === false);
        }
    }

    Timer {
        interval: 3300
        running: true
        onTriggered: {
            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: Qt.quit()
    }
}
