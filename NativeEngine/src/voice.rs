use crate::spectrum::{
    bessel_weights, Complex, UnitCircle, MAX_PARTIALS, MOD_RATIO, SIDEBAND_ORDER,
};
use crate::PARAMETER_COUNT;

const MAX_MOD_RATIO: f64 = std::f64::consts::SQRT_2;

#[derive(Clone, Copy)]
struct Timbre {
    spectrum: fn(usize, f32) -> Complex,
    modulation: f32,
    ratio: f64,
    articulation: f32,
    interaction: f32,
    attack_seconds: f32,
}

// Each profile supplies its own spectrum and articulation. Intermediate
// automation values interpolate the complex drive and modulation settings.
const TIMBRES: [Timbre; 5] = [
    Timbre {
        spectrum: |n, _| Complex::new(if n == 1 { 1.2 } else { 0.0 }, 0.0),
        modulation: 0.16,
        ratio: MOD_RATIO,
        articulation: 0.0,
        interaction: 0.08,
        attack_seconds: 0.012,
    },
    Timbre {
        spectrum: |n, tilt| {
            Complex::new(
                0.0,
                if n % 2 == 1 {
                    -0.95 / (n as f32).powf(1.75 - tilt)
                } else {
                    0.0
                },
            )
        },
        modulation: 0.24,
        ratio: 0.5,
        articulation: 0.0,
        interaction: 0.14,
        attack_seconds: 0.008,
    },
    Timbre {
        spectrum: |n, tilt| Complex::new(0.0, -0.72 / (n as f32).powf(1.65 - tilt)),
        modulation: 0.65,
        ratio: MOD_RATIO,
        articulation: 0.0,
        interaction: 0.55,
        attack_seconds: 0.005,
    },
    Timbre {
        spectrum: |n, tilt| {
            let amplitude = match n {
                1 => 0.62,
                2 => 0.18,
                3 => 0.9,
                5 => 0.67,
                8 => 0.43,
                13 => 0.24,
                _ => 0.0,
            };
            let (sin, cos) = (n as f32 * 1.37).sin_cos();
            Complex::new(cos, sin) * (amplitude * (0.65 + tilt * 0.8))
        },
        modulation: 1.0,
        ratio: MAX_MOD_RATIO,
        articulation: 1.0,
        interaction: 0.25,
        attack_seconds: 0.002,
    },
    Timbre {
        spectrum: |n, tilt| {
            let harmonic = n as f32;
            let center = 3.0 + 12.0 * tilt;
            let cluster = (-((harmonic - center) / 3.2).powi(2)).exp() * 0.48;
            let floor = if n == 1 { 0.44 } else { 0.02 };
            let (sin, cos) = (0.22 * harmonic * harmonic).sin_cos();
            Complex::new(cos, sin) * (floor + cluster)
        },
        modulation: 0.8,
        ratio: 0.618_034,
        articulation: -1.0,
        interaction: 1.35,
        attack_seconds: 0.24,
    },
];

pub struct SpectralField {
    pub source: [Complex; MAX_PARTIALS],
    pub phase_gradient: [f32; MAX_PARTIALS],
    pub spread: f32,
    pub upward: f32,
    pub downward: f32,
    pub coupling: f32,
    pub motion: f32,
    pub mod_ratio: f64,
    pub articulation: f32,
    pub attack: f32,
    pub sidebands: [[f32; SIDEBAND_ORDER + 1]; 2],
}

impl SpectralField {
    pub fn new(controls: &[f32; PARAMETER_COUNT], sample_rate: f32) -> Self {
        let [_, diffusion, index, tilt, _, motion, flow, coupling, _, timbre] = *controls;
        let transport = (flow * 2.0 - 1.0) * 16.0;
        let position = timbre * (TIMBRES.len() - 1) as f32;
        let left = TIMBRES[position as usize];
        let right = TIMBRES[((position as usize) + 1).min(TIMBRES.len() - 1)];
        let blend = position.fract();
        let mix = |a: f32, b: f32| a + (b - a) * blend;
        let interaction = mix(left.interaction, right.interaction);
        let depth = index * mix(left.modulation, right.modulation);
        let attack_seconds = mix(left.attack_seconds, right.attack_seconds);
        Self {
            source: std::array::from_fn(|bin| {
                let a = (left.spectrum)(bin + 1, tilt);
                let drive = if blend == 0.0 {
                    a
                } else {
                    a + ((right.spectrum)(bin + 1, tilt) - a) * blend
                };
                drive * 18.0
            }),
            phase_gradient: std::array::from_fn(|bin| ((bin + 1) as f32 * 2.17).sin()),
            spread: diffusion * 18.0 * interaction,
            upward: transport.max(0.0) * interaction,
            downward: (-transport).max(0.0) * interaction,
            coupling: coupling * 24.0 * interaction,
            motion: motion * (0.4 + interaction),
            mod_ratio: left.ratio + (right.ratio - left.ratio) * blend as f64,
            articulation: mix(left.articulation, right.articulation),
            attack: 1.0 - (-1.0 / (sample_rate * attack_seconds)).exp(),
            sidebands: [bessel_weights(depth * 2.5), bessel_weights(depth * 0.7)],
        }
    }
}

#[derive(Clone, Copy, Default)]
struct Partial {
    state: Complex,
    output: Complex,
    step: Complex,
}

#[derive(Clone, Copy, Default)]
pub struct Voice {
    pub held: bool,
    pub partial_count: usize,
    velocity: f32,
    reduced_modulation: bool,
    envelope: f32,
    phase: f64,
    mod_phase: f64,
    motion_phase: f32,
    age: f32,
    mod_ratio: f64,
    attack: f32,
    increment: f64,
    modulation_order: usize,
    partials: [Partial; MAX_PARTIALS],
    sidebands: [f32; SIDEBAND_ORDER + 1],
    sideband_steps: [f32; SIDEBAND_ORDER + 1],
}

impl Voice {
    pub fn new(increment: f64) -> Self {
        let bandwidth = 0.46 / increment;
        let modulation_order =
            SIDEBAND_ORDER.min(((bandwidth - 1.0).max(0.0) / MAX_MOD_RATIO) as usize);
        // Reserve Nyquist headroom for all sidebands used by this voice.
        let partial_count =
            MAX_PARTIALS.min((bandwidth - modulation_order as f64 * MAX_MOD_RATIO) as usize);
        Self {
            increment,
            modulation_order,
            partial_count,
            ..Self::default()
        }
    }

    pub fn restart_articulation(&mut self) {
        self.age = 0.0;
    }

    pub fn gate_on(&mut self, velocity: f32, reduced_modulation: bool) {
        self.held = true;
        self.age = 0.0;
        self.velocity = velocity.clamp(0.0, 1.0);
        self.reduced_modulation = reduced_modulation;
    }

    pub fn oscillator() -> Self {
        Self {
            partial_count: MAX_PARTIALS,
            modulation_order: SIDEBAND_ORDER,
            ..Self::default()
        }
    }

    pub fn update(&mut self, field: &SpectralField, dt: f32, frames: usize) {
        self.age = (self.age + dt).min(60.0);
        self.attack = field.attack;
        self.mod_ratio = field.mod_ratio;
        let metallic_decay = (-self.age * 3.8).exp();
        let bloom = 1.0 - (-self.age * 1.8).exp();
        let rate = 1.0 / frames as f32;
        let old = self.partials.map(|partial| partial.state);
        let weights = field.sidebands[usize::from(self.reduced_modulation)];
        self.motion_phase = (self.motion_phase + dt * (0.15 + field.motion * 2.3)).fract();
        let motion = field.motion * 25.0 * (std::f32::consts::TAU * self.motion_phase).sin();
        for (order, weight) in weights.into_iter().enumerate() {
            let target = if order <= self.modulation_order {
                weight
            } else {
                0.0
            };
            self.sideband_steps[order] = (target - self.sidebands[order]) * rate;
        }

        for (bin, partial) in self.partials[..self.partial_count].iter_mut().enumerate() {
            let current = old[bin];
            let lower = bin.checked_sub(1).map(|index| old[index]);
            let upper = (bin + 1 < self.partial_count).then(|| old[bin + 1]);
            let lower = lower.unwrap_or(current);
            let upper = upper.unwrap_or(current);
            let laplacian = lower + upper - current * 2.0;
            let spread = laplacian * field.spread;
            let drift = (lower - current) * field.upward + (upper - current) * field.downward;
            let phase_drift = current.perpendicular() * (motion * field.phase_gradient[bin]);
            let interaction = laplacian.perpendicular() * field.coupling;
            let damping = current * (10.0 + 35.0 * current.energy());
            let upper_weight = bin as f32 / (bin as f32 + 2.0);
            let articulation = 1.0
                - field.articulation.max(0.0) * upper_weight * (1.0 - metallic_decay) * 0.92
                - (-field.articulation).max(0.0) * upper_weight * (1.0 - bloom) * 0.95;
            let drive = field.source[bin] * articulation;
            let next =
                current + (drive + spread + drift + phase_drift + interaction - damping) * dt;
            partial.state = next * (1.2 / next.energy().sqrt().max(1.2));
            partial.step = (partial.state - partial.output) * rate;
        }
    }

    pub fn sample(
        &mut self,
        circle: &UnitCircle,
        release: f32,
        sustain: f32,
        balance: f32,
    ) -> Option<f32> {
        let target = if self.held { self.velocity } else { 0.0 };
        if self.held {
            self.envelope += (target - self.envelope) * self.attack;
        } else if sustain < 0.98 {
            self.envelope -= self.envelope * release;
        }
        if !self.held && self.envelope < 0.00005 {
            return None;
        }

        let sample = self.spectrum(circle, self.phase, self.increment, balance, 1.0, false);
        self.phase = (self.phase + self.increment).fract();
        Some(sample * self.envelope)
    }

    pub fn spectrum(
        &mut self,
        circle: &UnitCircle,
        phase: f64,
        increment: f64,
        balance: f32,
        depth: f32,
        synced: bool,
    ) -> f32 {
        self.mod_phase = if synced {
            (phase * self.mod_ratio).fract()
        } else {
            (self.mod_phase + increment * self.mod_ratio).fract()
        };
        let fundamental = circle.at(phase);
        let budget = 0.46 / increment - self.modulation_order as f64 * self.mod_ratio;
        let mut rotor = fundamental;
        let mut carrier = Complex::default();
        for (bin, partial) in self.partials[..self.partial_count].iter_mut().enumerate() {
            partial.output += partial.step;
            let weight = ((budget - bin as f64 - 1.0) * 2.0).clamp(0.0, 1.0) as f32;
            carrier += partial.output.rotated(rotor) * weight;
            rotor = rotor.rotated(fundamental);
        }
        // The same sideband kernel multiplies every retained carrier. Evaluate
        // it once per sample, preserving independent upper and lower weights.
        let mut modulation = Complex::default();
        for order in 0..=self.modulation_order {
            self.sidebands[order] += self.sideband_steps[order];
            let weight = self.sidebands[order];
            if order == 0 {
                modulation.re = weight;
                continue;
            }
            let side = circle.at((self.mod_phase * order as f64).fract());
            let upper = weight * (1.0 + balance);
            let lower = weight * (1.0 - balance) * if order.is_multiple_of(2) { 1.0 } else { -1.0 };
            modulation += Complex::new(side.re * (upper + lower), side.im * (upper - lower));
        }
        (carrier + (carrier.rotated(modulation) - carrier) * depth).re
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn carriers_and_sidebands_fit_within_the_frequency_budget() {
        for sample_rate in [8_000.0, 44_100.0, 48_000.0, 192_000.0] {
            for note in 0..128 {
                let frequency = 440.0 * 2.0_f64.powf((note as f64 - 69.0) / 12.0);
                let voice = Voice::new(frequency / sample_rate);
                if voice.partial_count > 0 {
                    let top =
                        voice.partial_count as f64 + voice.modulation_order as f64 * MAX_MOD_RATIO;
                    assert!(top * voice.increment <= 0.46);
                }
            }
        }
    }
}
