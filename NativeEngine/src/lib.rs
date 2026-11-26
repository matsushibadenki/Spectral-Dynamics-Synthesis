// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/NativeEngine/src/lib.rs
// lib.rs
// SDS ネイティブDSPエンジンのエントリポイントとデフォルトパラメーター定義

mod oscillator;
mod spectrum;
mod voice;

use spectrum::UnitCircle;
use voice::{SpectralField, Voice};

const CONTROL_FRAMES: usize = 32;
const PARAMETER_COUNT: usize = 10;
const DEFAULTS: [f32; PARAMETER_COUNT] =
    [0.50, 0.18, 0.65, 0.78, 0.50, 0.35, 0.50, 0.38, 0.50, 0.50];

pub struct SpectralDSP {
    sample_rate: f64,
    voices: [Voice; 128],
    active: [usize; 128],
    count: usize,
    circle: UnitCircle,
    controls: [f32; PARAMETER_COUNT],
    targets: [f32; PARAMETER_COUNT],
    pedal: f32,
    tick: usize,
}

impl SpectralDSP {
    fn new(sample_rate: f64) -> Self {
        let sample_rate = if sample_rate.is_finite() && (8_000.0..=384_000.0).contains(&sample_rate)
        {
            sample_rate
        } else {
            48_000.0
        };
        Self {
            sample_rate,
            voices: [Voice::default(); 128],
            active: [0; 128],
            count: 0,
            circle: UnitCircle::new(),
            controls: DEFAULTS,
            targets: DEFAULTS,
            pedal: 0.0,
            tick: 0,
        }
    }

    fn note_on(&mut self, note: usize, velocity: f32, soft: bool) {
        if note >= self.voices.len() || !velocity.is_finite() {
            return;
        }
        if velocity <= 0.0 {
            self.voices[note].held = false;
            return;
        }
        let frequency = 440.0 * 2.0_f64.powf((note as f64 - 69.0) / 12.0);
        let voice = &mut self.voices[note];
        if voice.partial_count == 0 {
            *voice = Voice::new(frequency / self.sample_rate);
            if voice.partial_count == 0 {
                return;
            }
            self.active[self.count] = note;
            self.count += 1;
        }
        voice.gate_on(velocity, soft);
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let dt = CONTROL_FRAMES as f32 / self.sample_rate as f32;
        let smooth = 1.0 - (-dt / 0.024).exp();
        let mut release = 0.0;
        // Derive from the current smoothed value so buffer boundaries do not change the envelope.
        let release_step = |amount: f32| {
            let seconds = 0.035 + amount * amount * 1.25 + self.pedal * self.pedal * 2.0;
            1.0 - (-1.0 / (self.sample_rate as f32 * seconds)).exp()
        };
        for (out_l, out_r) in left.iter_mut().zip(right) {
            if self.tick == 0 {
                for (value, target) in self.controls.iter_mut().zip(self.targets) {
                    *value += (target - *value) * smooth;
                }
                release = release_step(self.controls[4]);
                if self.count != 0 {
                    let field = SpectralField::new(&self.controls, self.sample_rate as f32);
                    for &note in &self.active[..self.count] {
                        self.voices[note].update(&field, dt, CONTROL_FRAMES);
                    }
                }
            } else if release == 0.0 {
                release = release_step(self.controls[4]);
            }
            self.tick = (self.tick + 1) % CONTROL_FRAMES;
            let balance = self.controls[0] * 2.0 - 1.0;
            let mut mixed = 0.0;
            let mut slot = 0;
            while slot < self.count {
                let note = self.active[slot];
                let voice = &mut self.voices[note];
                if let Some(sample) = voice.sample(&self.circle, release, self.pedal, balance) {
                    mixed += sample;
                    slot += 1;
                } else {
                    *voice = Voice::default();
                    self.count -= 1;
                    self.active[slot] = self.active[self.count];
                }
            }
            let gain = 0.22 * (2.0 * self.controls[8]).powi(2);
            let sample = gain * mixed;
            let limited = sample / (1.0 + sample.abs());
            *out_l = limited;
            *out_r = limited;
        }
    }
}

#[no_mangle]
pub extern "C" fn sds_create(sample_rate: f64) -> *mut SpectralDSP {
    Box::into_raw(Box::new(SpectralDSP::new(sample_rate)))
}

#[no_mangle]
pub unsafe extern "C" fn sds_destroy(synth: *mut SpectralDSP) {
    drop(Box::from_raw(synth));
}

#[no_mangle]
pub unsafe extern "C" fn sds_note_on(
    synth: *mut SpectralDSP,
    note: u32,
    velocity: f32,
    soft: bool,
) {
    (*synth).note_on(note as usize, velocity, soft);
}

#[no_mangle]
pub unsafe extern "C" fn sds_note_off(synth: *mut SpectralDSP, note: u32) {
    if let Some(voice) = (&mut (*synth).voices).get_mut(note as usize) {
        voice.held = false;
    }
}

#[no_mangle]
pub unsafe extern "C" fn sds_sustain(synth: *mut SpectralDSP, position: f32) {
    if position.is_finite() {
        (*synth).pedal = position.clamp(0.0, 1.0);
    }
}

#[no_mangle]
pub unsafe extern "C" fn sds_all_off(synth: *mut SpectralDSP) {
    let synth = &mut *synth;
    synth.pedal = 0.0;
    for voice in &mut synth.voices {
        voice.held = false;
    }
}

#[no_mangle]
pub unsafe extern "C" fn sds_set_parameter(synth: *mut SpectralDSP, address: u32, amount: f32) {
    if amount.is_finite() {
        if let Some(target) = (&mut (*synth).targets).get_mut(address as usize) {
            *target = amount.clamp(0.0, 1.0);
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sds_render(
    synth: *mut SpectralDSP,
    left: *mut f32,
    right: *mut f32,
    frames: u32,
) {
    if frames == 0 {
        return;
    }
    (*synth).render(
        std::slice::from_raw_parts_mut(left, frames as usize),
        std::slice::from_raw_parts_mut(right, frames as usize),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(synth: &mut SpectralDSP, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let mut left = vec![0.0; frames];
        let mut right = vec![0.0; frames];
        synth.render(&mut left, &mut right);
        (left, right)
    }

    #[test]
    fn callback_boundaries_preserve_phase_and_envelopes() {
        let mut whole = SpectralDSP::new(48_000.0);
        let mut split = SpectralDSP::new(48_000.0);
        for synth in [&mut whole, &mut split] {
            synth.targets[4] = 0.2;
            synth.note_on(69, 0.8, false);
            render(synth, 500);
            synth.voices[69].held = false;
        }
        let (mut left, mut right) = render(&mut split, 93);
        let (next_left, next_right) = render(&mut split, 307);
        left.extend(next_left);
        right.extend(next_right);
        assert_eq!(render(&mut whole, 400), (left, right));
    }

    fn magnitude(samples: &[f32], frequency: f64) -> f64 {
        let (re, im) = samples
            .iter()
            .enumerate()
            .fold((0.0, 0.0), |(re, im), (i, sample)| {
                let phase = std::f64::consts::TAU * i as f64 / 48_000.0;
                let window = 0.5 - 0.5 * phase.cos();
                let (sin, cos) = (phase * frequency).sin_cos();
                (
                    re + *sample as f64 * window * cos,
                    im + *sample as f64 * window * sin,
                )
            });
        re.hypot(im)
    }

    #[test]
    fn modulation_produces_independently_weighted_sidebands() {
        let spectrum = |balance, index| {
            let mut synth = SpectralDSP::new(48_000.0);
            synth.targets[0] = balance;
            synth.targets[2] = index;
            synth.targets[5] = 0.0;
            synth.targets[8] = 0.10;
            synth.note_on(69, 1.0, false);
            render(&mut synth, 48_000);
            let (signal, _) = render(&mut synth, 48_000);
            (
                magnitude(&signal, 440.0 * (1.0 - spectrum::MOD_RATIO)),
                magnitude(&signal, 440.0 * (1.0 + spectrum::MOD_RATIO)),
            )
        };

        let (unmodulated_lower, unmodulated_upper) = spectrum(0.5, 0.0);
        let (lower, suppressed_upper) = spectrum(0.0, 0.5);
        let (suppressed_lower, upper) = spectrum(1.0, 0.5);
        assert!(lower > 1.0 && upper > 1.0);
        assert!(lower > 20.0 * unmodulated_lower.max(suppressed_lower));
        assert!(upper > 20.0 * unmodulated_upper.max(suppressed_upper));
    }

    #[test]
    fn timbre_changes_the_rendered_harmonics_and_attack() {
        let capture = |timbre| {
            let mut synth = SpectralDSP::new(48_000.0);
            synth.controls[9] = timbre;
            synth.targets[9] = timbre;
            for control in [1, 2, 5, 7] {
                synth.controls[control] = 0.0;
                synth.targets[control] = 0.0;
            }
            synth.note_on(69, 1.0, false);
            let (attack, _) = render(&mut synth, 2_400);
            render(&mut synth, 48_000);
            let (steady, _) = render(&mut synth, 48_000);
            let fundamental = magnitude(&steady, 440.0);
            let second = magnitude(&steady, 880.0) / fundamental;
            let third = magnitude(&steady, 1320.0) / fundamental;
            let early_peak = attack.into_iter().map(f32::abs).fold(0.0, f32::max);
            (second, third, early_peak)
        };

        let (_, pure_third, _) = capture(0.0);
        let (hollow_second, hollow_third, _) = capture(0.25);
        let (saw_second, _, saw_attack) = capture(0.5);
        let (_, metal_third, _) = capture(0.75);
        let (_, _, bloom_attack) = capture(1.0);
        assert!(hollow_third > pure_third * 4.0);
        assert!(saw_second > hollow_second * 4.0);
        assert!(metal_third > hollow_third);
        assert!(bloom_attack < saw_attack * 0.35);
    }

    #[test]
    fn damper_and_extreme_parameters_keep_output_bounded() {
        let mut synth = SpectralDSP::new(44_100.0);
        synth.targets = [1.0; PARAMETER_COUNT];
        synth.pedal = 1.0;
        for note in 0..128 {
            synth.note_on(note, 1.0, false);
        }
        assert_eq!(synth.count, 128);
        let (left, right) = render(&mut synth, 4096);
        assert!(left
            .iter()
            .chain(&right)
            .all(|value| value.is_finite() && value.abs() <= 1.0));
        assert!(left.iter().any(|value| value.abs() > 0.01));
        for voice in &mut synth.voices {
            voice.held = false;
        }
        render(&mut synth, 1024);
        assert_eq!(synth.count, 128);
        synth.pedal = 0.0;
        synth.targets[4] = 0.0;
        render(&mut synth, 44_100);
        assert_eq!(synth.count, 0);
    }
}
