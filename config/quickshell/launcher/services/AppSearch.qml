pragma Singleton

import Quickshell
import QtQuick

// App search over Freedesktop desktop entries.
// Fuzzy score, acronym matching, multi-term queries, alphabetical tie-break.
// Exposes a reactive `results` list.
Singleton {
    id: root

    property string query: ""
    property var results: []

    onQueryChanged: root.refresh()

    Connections {
        target: DesktopEntries.applications
        function onObjectInsertedPost() { root.refresh(); }
    }

    Component.onCompleted: root.refresh()

    function entryName(entry) {
        return String((entry && entry.name) || (entry && entry.id) || "");
    }

    function keywordText(entry) {
        try {
            if (entry && entry.keywords && typeof entry.keywords.join === "function") {
                return entry.keywords.join(" ");
            }
        } catch (e) { }
        return "";
    }

    function entrySearchText(entry) {
        if (!entry) return "";
        return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id]
            .join(" ").toLowerCase();
    }

    function wordText(value) {
        return String(value || "")
            .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
            .replace(/[._:/\\-]+/g, " ")
            .toLowerCase();
    }

    function words(value) {
        var vals = wordText(value).split(/[^a-z0-9]+/);
        var result = [];
        for (var i = 0; i < vals.length; i++) {
            if (vals[i]) result.push(vals[i]);
        }
        return result;
    }

    function entryAcronym(entry) {
        var vals = words([entry && entry.name, entry && entry.genericName,
                         keywordText(entry), entry && entry.id].join(" "));
        var result = "";
        for (var i = 0; i < vals.length; i++) result += vals[i].charAt(0);
        return result;
    }

    function termMatches(entry, term) {
        if (!term) return true;
        var name = entryName(entry).toLowerCase();
        var id = String((entry && entry.id) || "").toLowerCase();
        var haystack = entrySearchText(entry);
        if (name.indexOf(term) >= 0) return true;
        if (id.indexOf(term) >= 0) return true;
        if (haystack.indexOf(term) >= 0) return true;
        return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0;
    }

    function allTermsMatch(entry, query) {
        var terms = String(query || "").toLowerCase().trim().split(/\s+/);
        for (var i = 0; i < terms.length; i++) {
            if (terms[i] && !termMatches(entry, terms[i])) return false;
        }
        return true;
    }

    function fuzzyScore(entry, query) {
        var q = String(query || "").trim().toLowerCase();
        if (!q) return 0;
        if (!allTermsMatch(entry, q)) return -1;

        var name = entryName(entry).toLowerCase();
        var id = String((entry && entry.id) || "").toLowerCase();
        var haystack = entrySearchText(entry);
        var directName = name.indexOf(q);
        var directId = id.indexOf(q);
        if (directName === 0) return 10000 - name.length;
        if (directId === 0) return 9500 - id.length;
        if (directName > 0) return 8000 - directName * 10 - name.length;
        if (directId > 0) return 7600 - directId * 10 - id.length;

        var hayIndex = haystack.indexOf(q);
        if (hayIndex >= 0) return 6000 - hayIndex;

        var acronym = entryAcronym(entry);
        var acronymIndex = acronym.indexOf(q);
        if (acronymIndex === 0) return 5000 - acronym.length;
        if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length;

        return 4000 - name.length;
    }

    function allApps() {
        const values = DesktopEntries.applications.values;
        const entries = (values && values.length !== undefined)
            ? Array.from(values)
            : [];
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (!e || e.noDisplay) continue;
            if (!entryName(e)) continue;
            out.push(e);
        }
        return out;
    }

    function search(q) {
        var qq = String(q || "").trim();
        var apps = root.allApps();
        var rows = [];
        for (var i = 0; i < apps.length; i++) {
            var entry = apps[i];
            var score = root.fuzzyScore(entry, qq);
            if (score < 0) continue;
            rows.push({ entry: entry, score: score,
                        key: entryName(entry).toLowerCase() });
        }
        rows.sort(function(a, b) {
            if (qq && a.score !== b.score) return b.score - a.score;
            if (a.key < b.key) return -1;
            if (a.key > b.key) return 1;
            return 0;
        });
        return rows.map(function(r) { return r.entry; });
    }

    function refresh() {
        root.results = root.search(root.query);
    }
}