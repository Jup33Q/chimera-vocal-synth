#ifndef CHIMERA_BRIDGE_H
#define CHIMERA_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef void *ChimeraHandle;

uint32_t chimera_layout_version(void);
uint8_t *chimera_alloc(size_t n);
void chimera_free(uint8_t *p, size_t n);
uint32_t chimera_call(const uint8_t *ptr, size_t len);
const uint8_t *chimera_result_ptr(void);
size_t chimera_result_len(void);

ChimeraHandle engine_new(double sample_rate);
void engine_free(ChimeraHandle h);
const float *engine_render(ChimeraHandle h, size_t n);
uint8_t *engine_records(ChimeraHandle h);
double engine_schedule(ChimeraHandle h, size_t count, double lead, uint32_t replace);
double *engine_values(ChimeraHandle h);
void engine_set_artic(ChimeraHandle h, uint32_t tip_free);
void engine_set_source(ChimeraHandle h);
void engine_set_gate(ChimeraHandle h, double level);
void engine_set_body(ChimeraHandle h, double female, double child);
void engine_stop_speech(ChimeraHandle h);
void engine_release(ChimeraHandle h, double tag);
double engine_clock(ChimeraHandle h);
const double *engine_telemetry(ChimeraHandle h);
void engine_set_beat(ChimeraHandle h, uint32_t has_steps, size_t count, double bpm, double swing, uint32_t playing);
void engine_beat_hit(ChimeraHandle h);
double engine_beat_step(ChimeraHandle h);
uint32_t engine_set_creature(ChimeraHandle h, const uint8_t *ptr, size_t len);
void engine_set_human(ChimeraHandle h);
void engine_creature_param(ChimeraHandle h, size_t index, double value);
void engine_play_call(ChimeraHandle h, size_t index, double pitch, double amp);
void engine_stop_call(ChimeraHandle h);
const double *engine_creature_telemetry(ChimeraHandle h);

#endif
