//! A cheap, bounded input gate, not a speech-recognition model. Hardware mute
//! can still produce callbacks (and sometimes a DC offset or tiny noise).
//! Never run ASR just because the device delivered another buffer.
use std::collections::VecDeque;

const FRAME_MS: usize = 20;
const START_WINDOW: usize = 10;
const START_FRAMES: usize = 5;
const PRE_ROLL_FRAMES: usize = 13;
const VOICE_RMS: f64 = 0.003;
const SILENT_RMS: f64 = 0.00001;

#[derive(Debug)]
pub(super) enum Input {
    Start(Vec<f32>),
    Audio(Vec<f32>),
    End,
    Silent(bool),
}

pub(super) struct ActivityGate {
    frame_size: usize,
    max_samples: usize,
    end_silence: usize,
    pending: Vec<f32>,
    pre_roll: VecDeque<Vec<f32>>,
    onset: VecDeque<bool>,
    active: bool,
    utterance_samples: usize,
    trailing_frames: usize,
    silent_frames: usize,
    silent: bool,
}

impl ActivityGate {
    pub(super) fn new(rate: u32, pause_ms: usize) -> Self {
        Self {
            frame_size: (rate as usize * FRAME_MS / 1000).max(1),
            max_samples: rate as usize * 15,
            end_silence: pause_ms.div_ceil(FRAME_MS),
            pending: Vec::new(),
            pre_roll: VecDeque::new(),
            onset: VecDeque::new(),
            active: false,
            utterance_samples: 0,
            trailing_frames: 0,
            silent_frames: 0,
            silent: false,
        }
    }

    pub(super) fn active(&self) -> bool {
        self.active
    }

    pub(super) fn push(&mut self, samples: &[f32]) -> Vec<Input> {
        let mut output = Vec::new();
        for &sample in samples {
            self.pending.push(if sample.is_finite() {
                sample.clamp(-1.0, 1.0)
            } else {
                0.0
            });
            if self.pending.len() == self.frame_size {
                let frame = std::mem::take(&mut self.pending);
                self.frame(frame, &mut output);
            }
        }
        output
    }

    fn frame(&mut self, frame: Vec<f32>, output: &mut Vec<Input>) {
        // Variance rejects a constant nonzero USB/ADC offset. Accumulate in
        // f64 so tiny input and large buffers cannot overflow or produce NaN.
        let mean = frame.iter().map(|&x| x as f64).sum::<f64>() / frame.len() as f64;
        let power = frame
            .iter()
            .map(|&x| (x as f64 - mean).powi(2))
            .sum::<f64>()
            / frame.len() as f64;
        self.silent_frames = if power <= SILENT_RMS * SILENT_RMS {
            (self.silent_frames + 1).min(1000 / FRAME_MS)
        } else {
            0
        };
        let silent = self.silent_frames >= 1000 / FRAME_MS;
        if silent != self.silent {
            self.silent = silent;
            output.push(Input::Silent(silent));
        }
        let voiced = power >= VOICE_RMS * VOICE_RMS;
        if !self.active {
            self.pre_roll.push_back(frame);
            if self.pre_roll.len() > PRE_ROLL_FRAMES {
                self.pre_roll.pop_front();
            }
            self.onset.push_back(voiced);
            if self.onset.len() > START_WINDOW {
                self.onset.pop_front();
            }
            // At least 100 ms of activity in 200 ms: a mute-button pop or
            // single keyboard/mouse click must not start an utterance.
            if self.onset.iter().filter(|&&v| v).count() >= START_FRAMES {
                self.active = true;
                self.trailing_frames = 0;
                let audio: Vec<_> = self.pre_roll.drain(..).flatten().collect();
                self.utterance_samples = audio.len();
                self.onset.clear();
                output.push(Input::Start(audio));
            }
        } else {
            self.trailing_frames = if voiced { 0 } else { self.trailing_frames + 1 };
            self.utterance_samples += frame.len();
            output.push(Input::Audio(frame));
            if self.trailing_frames >= self.end_silence
                || self.utterance_samples >= self.max_samples
            {
                self.active = false;
                self.utterance_samples = 0;
                self.trailing_frames = 0;
                output.push(Input::End);
            }
        }
    }

    // Manual Stop flushes a real utterance, but never turns unqualified
    // pre-roll/silent input into a transcription request.
    pub(super) fn finish(&mut self) -> Vec<Input> {
        let mut output = Vec::new();
        if self.active {
            if !self.pending.is_empty() {
                output.push(Input::Audio(std::mem::take(&mut self.pending)));
            }
            output.push(Input::End);
        }
        self.active = false;
        self.pending.clear();
        self.pre_roll.clear();
        self.onset.clear();
        self.utterance_samples = 0;
        self.trailing_frames = 0;
        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(rate: usize, ms: usize, level: f32) -> Vec<f32> {
        (0..rate * ms / 1000)
            .map(|i| level * (i as f32 * std::f32::consts::TAU * 230.0 / rate as f32).sin())
            .collect()
    }
    fn starts(events: &[Input]) -> usize {
        events
            .iter()
            .filter(|e| matches!(e, Input::Start(_)))
            .count()
    }
    fn ends(events: &[Input]) -> usize {
        events.iter().filter(|e| matches!(e, Input::End)).count()
    }

    #[test]
    fn muted_zero_dc_offset_and_tiny_noise_never_reach_asr() {
        for level in [0.0, 0.2, -0.8] {
            let mut gate = ActivityGate::new(48000, 1200);
            let samples: Vec<_> = (0..48000 * 30)
                .map(|i| level + if i % 2 == 0 { 0.000001 } else { -0.000001 })
                .collect();
            let mut events = Vec::new();
            for chunk in samples.chunks(731) {
                events.extend(gate.push(chunk));
            }
            events.extend(gate.finish());
            assert_eq!(events.len(), 1);
            assert!(matches!(events[0], Input::Silent(true)));
            assert!(!gate.active());
        }
    }

    #[test]
    fn invalid_samples_and_empty_callbacks_are_silent() {
        let mut gate = ActivityGate::new(16000, 1200);
        assert!(gate.push(&[]).is_empty());
        let samples: Vec<_> = [f32::NAN, f32::INFINITY, f32::NEG_INFINITY]
            .into_iter()
            .cycle()
            .take(16000)
            .collect();
        assert!(matches!(
            gate.push(&samples).as_slice(),
            [Input::Silent(true)]
        ));
        assert!(gate.finish().is_empty());
    }

    #[test]
    fn isolated_pop_or_short_noise_burst_cannot_start_a_request() {
        let mut gate = ActivityGate::new(16000, 1200);
        let mut audio = vec![0.0; 16000];
        audio[1000] = 1.0;
        audio[9000] = -1.0;
        assert_eq!(starts(&gate.push(&audio)), 0);
        assert_eq!(starts(&gate.push(&tone(16000, 60, 0.4))), 0);
        assert_eq!(starts(&gate.push(&vec![0.0; 32000])), 0);
        assert!(gate.finish().is_empty());
    }

    #[test]
    fn low_noise_is_idle_without_claiming_the_device_is_silent() {
        let mut gate = ActivityGate::new(16000, 1200);
        let events = gate.push(&tone(16000, 2000, 0.001));
        assert!(events.is_empty());
        assert!(!gate.active());
        assert!(gate.finish().is_empty());
    }

    #[test]
    fn sustained_quiet_speech_keeps_onset_and_ends_once_on_a_pause() {
        for rate in [8000, 16000, 44100, 48000, 192000] {
            let mut gate = ActivityGate::new(rate, 1200);
            gate.push(&vec![0.0; rate as usize]);
            let voice = tone(rate as usize, 600, 0.008);
            let mut events = Vec::new();
            for chunk in voice.chunks(137) {
                events.extend(gate.push(chunk));
            }
            assert_eq!(starts(&events), 1);
            assert_eq!(ends(&events), 0);
            assert!(events.iter().any(|e| matches!(e, Input::Silent(false))));
            let delivered: Vec<_> = events
                .into_iter()
                .flat_map(|e| match e {
                    Input::Start(a) | Input::Audio(a) => a,
                    _ => Vec::new(),
                })
                .collect();
            assert!(delivered.ends_with(&voice));
            let tail = gate.push(&vec![0.0; rate as usize * 2]);
            assert_eq!(ends(&tail), 1);
            assert!(!gate.active());
            assert_eq!(
                starts(&gate.push(&voice)),
                1,
                "unmuting must recover without restarting the mic"
            );
            assert_eq!(ends(&gate.finish()), 1);
            assert!(gate.finish().is_empty());
        }
    }

    #[test]
    fn long_noise_is_bounded_and_streaming_chunks_do_not_change_the_gate() {
        let voice = tone(16000, 16000, 0.08);
        let mut whole = ActivityGate::new(16000, 1200);
        let mut split = ActivityGate::new(16000, 1200);
        let all = whole.push(&voice);
        let mut chunks = Vec::new();
        for chunk in voice.chunks(613) {
            chunks.extend(split.push(chunk));
        }
        assert_eq!(starts(&all), starts(&chunks));
        assert_eq!(ends(&all), 1);
        assert_eq!(ends(&all), ends(&chunks));
    }
}
