use std::f64::consts::TAU;
use std::ops::{Add, AddAssign, Mul, Sub};

pub const MAX_PARTIALS: usize = 32;
pub const SIDEBAND_ORDER: usize = 3;
pub const MOD_RATIO: f64 = 0.271_828;
const TABLE_SIZE: usize = 2048;

#[derive(Clone, Copy, Debug, Default)]
pub struct Complex {
    pub re: f32,
    pub im: f32,
}

impl Complex {
    pub fn new(re: f32, im: f32) -> Self {
        Self { re, im }
    }

    pub fn energy(self) -> f32 {
        self.re * self.re + self.im * self.im
    }

    pub fn rotated(self, rotor: Self) -> Self {
        Self::new(
            self.re * rotor.re - self.im * rotor.im,
            self.im * rotor.re + self.re * rotor.im,
        )
    }

    pub fn perpendicular(self) -> Self {
        Self::new(-self.im, self.re)
    }
}

impl Add for Complex {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.re + rhs.re, self.im + rhs.im)
    }
}

impl AddAssign for Complex {
    fn add_assign(&mut self, rhs: Self) {
        *self = *self + rhs;
    }
}

impl Sub for Complex {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.re - rhs.re, self.im - rhs.im)
    }
}

impl Mul<f32> for Complex {
    type Output = Self;
    fn mul(self, scalar: f32) -> Self {
        Self::new(self.re * scalar, self.im * scalar)
    }
}

pub struct UnitCircle([Complex; TABLE_SIZE + 1]);

impl UnitCircle {
    pub fn new() -> Self {
        Self(std::array::from_fn(|index| {
            let (sin, cos) = (TAU * index as f64 / TABLE_SIZE as f64).sin_cos();
            Complex::new(cos as f32, sin as f32)
        }))
    }

    pub fn at(&self, phase: f64) -> Complex {
        let position = phase * TABLE_SIZE as f64;
        let index = (position as usize).min(TABLE_SIZE - 1);
        self.0[index] + (self.0[index + 1] - self.0[index]) * (position - index as f64) as f32
    }
}

/// Jₙ(β) for β ∈ [0, 2.5]. Evaluated at control rate only.
pub fn bessel_weights(index: f32) -> [f32; SIDEBAND_ORDER + 1] {
    let half = index * 0.5;
    let mut initial = 1.0;
    std::array::from_fn(|order| {
        if order > 0 {
            initial *= half / order as f32;
        }
        let mut term = initial;
        let mut sum = term;
        for k in 1..=8 {
            term *= -half * half / (k * (k + order)) as f32;
            sum += term;
        }
        sum
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bessel_weights_match_known_values() {
        assert_eq!(bessel_weights(0.0), [1.0, 0.0, 0.0, 0.0]);
        for (actual, expected) in bessel_weights(2.0)
            .into_iter()
            .zip([0.22389078, 0.5767248, 0.35283402, 0.12894325])
        {
            assert!((actual - expected).abs() < 1e-6);
        }
    }
}
