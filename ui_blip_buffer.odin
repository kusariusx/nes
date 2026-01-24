package main

import "core:mem"
import "core:math"

BLIP_BUFFER_LOW_PASS  :: 0.996
BLIP_BUFFER_HIGH_PASS :: 0.999

BLIP_BUFFER_PHASE_COUNT :: 32
BLIP_BUFFER_STEP_WIDTH  :: 16
BLIP_BUFFER_MASTER_SIZE :: BLIP_BUFFER_PHASE_COUNT * BLIP_BUFFER_STEP_WIDTH

Blip_Buffer_Steps: [BLIP_BUFFER_PHASE_COUNT][BLIP_BUFFER_STEP_WIDTH]f32

Blip_Buffer :: struct {
    buffer: [AUDIO_SAMPLE_BUFFER_SIZE + BLIP_BUFFER_STEP_WIDTH]f32,
    integrator_sum: f32,
}

blip_buffer_init_steps :: proc() {
    master: [BLIP_BUFFER_MASTER_SIZE]f64 = ---
    for i in 0 ..< BLIP_BUFFER_MASTER_SIZE {
        master[i] = 0.5
    }

    gain := 0.5 / 0.777
    sine_size := 256 * BLIP_BUFFER_PHASE_COUNT + 2
    max_harmonic := sine_size / 2 / BLIP_BUFFER_PHASE_COUNT

    for h := 1; h <= max_harmonic; h += 2 {
        amplitude := gain / f64(h)
        to_angle := math.PI * 2 / f64(sine_size) * f64(h)
        for i in 0 ..< BLIP_BUFFER_MASTER_SIZE {
            master[i] += math.sin(f64(i - BLIP_BUFFER_MASTER_SIZE / 2) * to_angle) * amplitude
        }

        gain *= BLIP_BUFFER_LOW_PASS
    }

    blip_buffer := Blip_Buffer{}

    for phase in 0 ..< BLIP_BUFFER_PHASE_COUNT {
        error := 1.0
        prev := 0.0

        for i in 0 ..< BLIP_BUFFER_STEP_WIDTH {
            cur := master[i * BLIP_BUFFER_PHASE_COUNT + (BLIP_BUFFER_PHASE_COUNT - 1 - phase)]
            delta := cur - prev

            error -= delta
            prev = cur

            Blip_Buffer_Steps[phase][i] = f32(delta)
        }

        Blip_Buffer_Steps[phase][BLIP_BUFFER_STEP_WIDTH / 2 - 1] += f32(error * 0.5)
        Blip_Buffer_Steps[phase][BLIP_BUFFER_STEP_WIDTH / 2] += f32(error * 0.5)
    }
}

blip_buffer_add_delta :: proc(b: ^Blip_Buffer, time: f32, delta: f32) {
    whole := math.floor(time)
    phase := (time - whole) * BLIP_BUFFER_PHASE_COUNT
    for i in 0 ..< BLIP_BUFFER_STEP_WIDTH {
        b.buffer[int(whole) + i] += Blip_Buffer_Steps[int(phase)][i] * delta
    }
}

blip_buffer_prepare :: proc(b: ^Blip_Buffer) {
    sum := b.integrator_sum
    for i in 0 ..< AUDIO_SAMPLE_BUFFER_SIZE {
        sum += b.buffer[i]
        b.buffer[i] = sum
        sum *= BLIP_BUFFER_HIGH_PASS
    }

    b.integrator_sum = sum
}

blip_buffer_clear :: proc(b: ^Blip_Buffer) {
    copy(b.buffer[:BLIP_BUFFER_STEP_WIDTH], b.buffer[AUDIO_SAMPLE_BUFFER_SIZE:])
    mem.zero_slice(b.buffer[BLIP_BUFFER_STEP_WIDTH:])
}
