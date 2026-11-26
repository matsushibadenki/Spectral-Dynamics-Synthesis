#ifndef SPECTRAL_DSP_H
#define SPECTRAL_DSP_H

#include <stdbool.h>
#include <stdint.h>

typedef struct SpectralDSP SpectralDSP;

SpectralDSP * _Nonnull sds_create(double sample_rate);
void sds_destroy(SpectralDSP * _Nonnull synth);
void sds_note_on(SpectralDSP * _Nonnull synth, uint32_t note, float velocity, bool soft);
void sds_note_off(SpectralDSP * _Nonnull synth, uint32_t note);
void sds_sustain(SpectralDSP * _Nonnull synth, float position);
void sds_all_off(SpectralDSP * _Nonnull synth);
void sds_set_parameter(SpectralDSP * _Nonnull synth, uint32_t address, float amount);
void sds_render(SpectralDSP * _Nonnull synth, float * _Nonnull left,
                     float * _Nonnull right, uint32_t frames);

typedef struct SDSOscillatorBank SDSOscillatorBank;

typedef struct {
    float timbre, modulation, tilt, balance, diffusion, flow, coupling, motion;
} SDSOscillatorControls;

SDSOscillatorBank * _Nonnull sds_osc_create(void);
void sds_osc_destroy(SDSOscillatorBank * _Nonnull bank);
void sds_osc_reset(SDSOscillatorBank * _Nonnull bank);
void sds_osc_prepare(SDSOscillatorBank * _Nonnull bank, float rate, uint32_t oversampling,
                     SDSOscillatorControls controls);
float sds_osc_sample(SDSOscillatorBank * _Nonnull bank, uint32_t slot, uint64_t trigger,
                     double phase, float increment, float sideband_amount, bool synced);

#endif
