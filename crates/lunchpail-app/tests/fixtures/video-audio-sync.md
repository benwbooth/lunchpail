# Video/audio synchronization fixture

`video-audio-sync.mp4` is an original, synthetic 12-second test pattern and
440 Hz tone, not game footage. It exercises real decoding, seeking, looping,
and mute transitions in `tst_video_audio_playback.qml`.

Regenerate with FFmpeg:

```sh
ffmpeg -f lavfi -i testsrc2=size=160x90:rate=20 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 -t 12 \
  -c:v libx264 -preset veryfast -crf 35 -g 20 -pix_fmt yuv420p \
  -c:a aac -b:a 32k -movflags +faststart video-audio-sync.mp4
```
