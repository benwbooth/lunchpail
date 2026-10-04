import QtQuick

QtObject {
    id: history

    property var entries: []
    readonly property int count: entries.length

    function normalizeSeverity(value) {
        // Read older histories that only distinguished good/not-good.
        if (value === true) return "success"
        if (value === false) return "warning"
        return ["info", "success", "warning"].indexOf(value) >= 0 ? value : "info"
    }

    function initialize(serialized) {
        let restored = []
        try {
            const parsed = JSON.parse(serialized)
            if (Array.isArray(parsed)) {
                for (const entry of parsed) {
                    if (entry && typeof entry.message === "string"
                            && typeof entry.when === "string"
                            && (typeof entry.severity === "string"
                                || typeof entry.good === "boolean")) {
                        restored.push({ message: entry.message.slice(0, 2000),
                                        when: entry.when,
                                        severity: normalizeSeverity(entry.severity === undefined
                                                                    ? entry.good : entry.severity) })
                    }
                }
            }
        } catch (error) {
            // Corrupt saved UI preferences must not prevent the app opening.
        }
        entries = restored.slice(-100).reverse()
    }

    function append(message, severity, when) {
        const next = entries.slice()
        next.unshift({ message: String(message).slice(0, 2000),
                       severity: normalizeSeverity(severity),
                       when: when || new Date().toISOString() })
        entries = next.slice(0, 100)
    }

    function clear() {
        entries = []
    }

    function serialized() {
        return JSON.stringify(entries.slice().reverse())
    }
}
