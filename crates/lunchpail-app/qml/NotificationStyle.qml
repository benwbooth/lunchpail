import QtQuick

QtObject {
    property string severity: "info"
    readonly property color background: severity === "success" ? "#17392d"
                                        : severity === "warning" ? "#392e20" : "#1a2635"
    readonly property color accent: severity === "success" ? "#72dba3"
                                    : severity === "warning" ? "#ffbf69" : "#9fb9d3"
    readonly property string symbol: severity === "success" ? "✓"
                                     : severity === "warning" ? "!" : "i"
}
