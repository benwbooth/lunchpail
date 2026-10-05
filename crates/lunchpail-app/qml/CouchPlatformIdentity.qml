import QtQuick

QtObject {

function wordmark(platform) {
    const name = platform.toLowerCase()
    if (name.indexOf("super nintendo") >= 0) return "SNES"
    if (name.indexOf("nintendo entertainment") >= 0) return "NES"
    if (name.indexOf("nintendo 64") >= 0) return "N64"
    if (name.indexOf("game boy advance") >= 0) return "GBA"
    if (name.indexOf("game boy color") >= 0) return "GB COLOR"
    if (name.indexOf("game boy") >= 0) return "GAME BOY"
    if (name.indexOf("gamecube") >= 0) return "GAMECUBE"
    if (name.indexOf("playstation") >= 0) return platform.replace(/sony\s*/i, "").replace(/playstation/i, "PS").toUpperCase()
    if (name.indexOf("genesis") >= 0 || name.indexOf("mega drive") >= 0) return "GENESIS"
    if (name.indexOf("master system") >= 0) return "MASTER SYSTEM"
    if (name.indexOf("dreamcast") >= 0) return "DREAMCAST"
    if (name.indexOf("neo geo") >= 0) return "NEO·GEO"
    if (name.indexOf("arcade") >= 0 || name === "mame") return "ARCADE"
    return platform.replace(/^(sony|nintendo|sega|microsoft)\s+/i, "").toUpperCase()
}

function color(platform) {
    const name = platform.toLowerCase()
    if (name.indexOf("nintendo") >= 0 || name.indexOf("game boy") >= 0 || name.indexOf("wii") >= 0) return "#ef6670"
    if (name.indexOf("sega") >= 0) return "#62a6ff"
    if (name.indexOf("sony") >= 0 || name.indexOf("playstation") >= 0) return "#a499ff"
    if (name.indexOf("xbox") >= 0) return "#80d58a"
    if (name.indexOf("atari") >= 0) return "#ffa569"
    if (name.indexOf("arcade") >= 0) return "#f3bd61"
    return "#73ced0"
}
}
