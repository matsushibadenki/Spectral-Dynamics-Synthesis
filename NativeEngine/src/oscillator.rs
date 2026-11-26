// file:///Users/Shared/Program/Xcode/Spectral-Dynamics-Synthesis/NativeEngine/src/oscillator.rs
// oscillator.rs
// OSC A 向けに SDS スペクトル合成を提供するオシレーターバンクの C FFI 実装

use crate::spectrum::UnitCircle;
use crate::voice::{SpectralField, Voice};
use crate::{CONTROL_FRAMES, DEFAULTS};

#[repr(C)]
#[derive(Clone, Copy, PartialEq)]
pub struct SDSOscillatorControls {
    pub timbre: f32,
    pub modulation: f32,
    pub tilt: f32,
    pub balance: f32,
    pub diffusion: f32,
    pub flow: f32,
    pub coupling: f32,
    pub motion: f32,
}

impl SDSOscillatorControls {
    fn normalized(self) -> Self {
        fn unit(value: f32) -> f32 {
            if value.is_finite() {
                value.clamp(0.0, 1.0)
            } else {
                0.5
            }
        }
        Self {
            timbre: unit(self.timbre),
            modulation: unit(self.modulation),
            tilt: unit(self.tilt),
            balance: unit(self.balance),
            diffusion: unit(self.diffusion),
            flow: unit(self.flow),
            coupling: unit(self.coupling),
            motion: unit(self.motion),
        }
    }

    fn field(self, rate: f32) -> SpectralField {
        let mut controls = DEFAULTS;
        controls[0] = self.balance;
        controls[1] = self.diffusion;
        controls[2] = self.modulation;
        controls[3] = self.tilt;
        controls[5] = self.motion;
        controls[6] = self.flow;
        controls[7] = self.coupling;
        controls[9] = self.timbre;
        SpectralField::new(&controls, rate)
    }
}

struct Slot {
    voice: Voice,
    trigger: u64,
    remaining: usize,
}

impl Slot {
    fn new() -> Self {
        Self {
            voice: Voice::oscillator(),
            trigger: 0,
            remaining: 0,
        }
    }
}

pub struct SDSOscillatorBank {
    circle: UnitCircle,
    field: SpectralField,
    controls: SDSOscillatorControls,
    rate: f32,
    interval: usize,
    slots: [Slot; 8],
}

#[no_mangle]
pub extern "C" fn sds_osc_create() -> *mut SDSOscillatorBank {
    let controls = SDSOscillatorControls {
        timbre: 0.62,
        modulation: 0.65,
        tilt: 0.75,
        balance: 0.5,
        diffusion: 0.25,
        flow: 0.5,
        coupling: 0.42,
        motion: 0.35,
    };
    let rate = 48_000.0;
    Box::into_raw(Box::new(SDSOscillatorBank {
        circle: UnitCircle::new(),
        field: controls.field(rate),
        controls,
        rate,
        interval: CONTROL_FRAMES,
        slots: std::array::from_fn(|_| Slot::new()),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn sds_osc_destroy(bank: *mut SDSOscillatorBank) {
    drop(Box::from_raw(bank));
}

#[no_mangle]
pub unsafe extern "C" fn sds_osc_reset(bank: *mut SDSOscillatorBank) {
    (*bank).slots = std::array::from_fn(|_| Slot::new());
}

#[no_mangle]
pub unsafe extern "C" fn sds_osc_prepare(
    bank: *mut SDSOscillatorBank,
    rate: f32,
    oversampling: u32,
    controls: SDSOscillatorControls,
) {
    let bank = &mut *bank;
    let controls = controls.normalized();
    let interval = CONTROL_FRAMES * oversampling.clamp(1, 16) as usize;
    if bank.rate != rate || bank.interval != interval {
        bank.rate = rate;
        bank.interval = interval;
        bank.slots = std::array::from_fn(|_| Slot::new());
        bank.field = controls.field(rate);
    } else if bank.controls != controls {
        bank.field = controls.field(rate);
    }
    bank.controls = controls;
}

#[no_mangle]
pub unsafe extern "C" fn sds_osc_sample(
    bank: *mut SDSOscillatorBank,
    slot: u32,
    trigger: u64,
    phase: f64,
    increment: f32,
    sideband_amount: f32,
    synced: bool,
) -> f32 {
    let bank = &mut *bank;
    let slot = &mut bank.slots[slot as usize];
    if slot.trigger != trigger {
        slot.trigger = trigger;
        slot.voice.restart_articulation();
    }
    if slot.remaining == 0 {
        slot.voice
            .update(&bank.field, bank.interval as f32 / bank.rate, bank.interval);
        slot.remaining = bank.interval;
    }
    slot.remaining -= 1;
    slot.voice.spectrum(
        &bank.circle,
        phase,
        increment as f64,
        bank.controls.balance * 2.0 - 1.0,
        sideband_amount,
        synced,
    )
}
