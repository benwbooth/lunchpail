import QtMultimedia

// AudioOutput otherwise keeps the device selected when it was constructed.
// Follow later headset/HDMI/default-output changes without rebuilding players
// or changing their mute, volume, position, or playback state.
AudioOutput {
    property MediaDevices mediaDevices: MediaDevices {}
    device: mediaDevices.defaultAudioOutput
}
