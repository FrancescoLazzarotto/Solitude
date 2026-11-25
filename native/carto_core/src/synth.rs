//! Suoni del gioco, sintetizzati da zero (nessun file audio): effetti mono e musica stereo.
//! Tutto e' deterministico rispetto al seme.

use crate::dsp::*;
use crate::rng::Rng;
use std::f32::consts::TAU;
use std::sync::atomic::{AtomicBool, Ordering};

/// Nomi di tutti gli effetti disponibili.
pub const SFX_NAMES: &[&str] = &[
    "swing", "swing2", "hit_enemy", "hit_player", "roll", "step", "step2", "step3", "step4", "blip",
    "chest_open", "item_get", "shrine_rest", "lever", "gate_open", "bridge_reveal", "enemy_windup",
    "enemy_lunge", "enemy_hurt", "enemy_die", "fall", "death", "page_open", "page_close", "lantern_on",
    "heal", "drink", "shot",
];

/// Ritorna l'audio mono dell'effetto (campioni f32 in [-1, 1]), o None se il nome non esiste.
pub fn render_sfx(name: &str, seed: u64) -> Option<Vec<f32>> {
    let (mut buf, level, fade_out) = match name {
        "swing" => (swing(seed, false), 0.55, 0.03),
        "swing2" => (swing(seed ^ 0xA5, true), 0.55, 0.03),
        "hit_enemy" => (hit_enemy(seed), 0.9, 0.04),
        "hit_player" => (hit_player(seed), 0.9, 0.05),
        "roll" => (roll(seed), 0.5, 0.05),
        "step" => (step(seed, 0), 0.32, 0.01),
        "step2" => (step(seed, 1), 0.32, 0.01),
        "step3" => (step(seed, 2), 0.32, 0.01),
        "step4" => (step(seed, 3), 0.32, 0.01),
        "blip" => (blip(), 0.4, 0.01),
        "chest_open" => (chest_open(seed), 0.75, 0.1),
        "item_get" => (item_get(), 0.8, 0.2),
        "shrine_rest" => (shrine_rest(), 0.7, 0.3),
        "lever" => (lever(seed), 0.8, 0.05),
        "gate_open" => (gate_open(seed), 0.7, 0.2),
        "bridge_reveal" => (bridge_reveal(), 0.65, 0.2),
        "enemy_windup" => (enemy_windup(seed), 0.5, 0.03),
        "enemy_lunge" => (enemy_lunge(seed), 0.6, 0.03),
        "enemy_hurt" => (enemy_hurt(seed), 0.6, 0.02),
        "enemy_die" => (enemy_die(seed), 0.85, 0.1),
        "fall" => (fall(), 0.55, 0.15),
        "death" => (death(), 0.7, 0.3),
        "page_open" => (page(seed, false), 0.4, 0.03),
        "page_close" => (page(seed, true), 0.4, 0.03),
        "lantern_on" => (lantern_on(), 0.7, 0.2),
        "heal" => (heal(), 0.6, 0.2),
        "drink" => (drink(seed), 0.45, 0.05),
        "shot" => (shot(seed), 0.55, 0.03),
        _ => return None,
    };
    remove_dc(&mut buf);
    fade_edges(&mut buf, 0.002, fade_out);
    normalize(&mut buf, level);
    Some(buf)
}

fn make(len: usize) -> Vec<f32> {
    vec![0.0; len]
}

// ---------------------------------------------------------------------------
// Combattimento
// ---------------------------------------------------------------------------

fn swing(seed: u64, up: bool) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x5173);
    let n = secs(0.30);
    let mut out = make(n);
    let mut f = Svf::new(1000.0, 1.6);
    let mut o = Osc::new(0.0);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / n as f32;
        let sweep = if up { exp_lerp(500.0, 2600.0, t) } else { exp_lerp(2600.0, 500.0, t) };
        f.set(sweep, 1.6);
        let env = smooth(t / 0.25) * (1.0 - smooth((t - 0.35) / 0.65));
        let bp = f.process(rng.signed()).band;
        *s = (bp * 2.5 + o.sine(sweep * 0.5) * 0.15) * env;
    }
    out
}

fn hit_enemy(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x417);
    let n = secs(0.38);
    let mut out = make(n);
    let partials = [
        820.0 * rng.range(0.92, 1.08),
        1370.0 * rng.range(0.92, 1.08),
        2210.0 * rng.range(0.92, 1.08),
    ];
    let mut phase = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let f = 55.0 + 140.0 * decay(t, 0.035);
        phase += f / SR;
        let thump = (phase * TAU).sin() * decay(t, 0.10);
        let click = rng.signed() * decay(t, 0.004);
        let mut ring = 0.0;
        for (k, p) in partials.iter().enumerate() {
            ring += (TAU * p * t).sin() * decay(t, 0.06 + 0.04 * k as f32) * (0.35 / (k as f32 + 1.0));
        }
        *s = thump * 0.9 + click * 0.5 + ring * 0.35;
    }
    out
}

fn hit_player(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x77);
    let n = secs(0.42);
    let mut out = make(n);
    let mut o1 = Osc::new(0.0);
    let mut o2 = Osc::new(0.3);
    let mut lp = Svf::new(700.0, 0.8);
    let mut nlp = Svf::new(900.0, 0.7);
    let mut phase = 0.0f32;
    let mut held = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        phase += (40.0 + 120.0 * decay(t, 0.05)) / SR;
        let thump = (phase * TAU).sin() * decay(t, 0.12);
        let buzz = lp.process(o1.square(196.0) + o2.square(207.0)).low * decay(t, 0.12) * 0.5;
        let noise = nlp.process(rng.signed()).low * decay(t, 0.05);
        let mut v = thump * 0.9 + buzz + noise * 0.6;
        // Effetto "glitch" digitale: campiona e mantieni, sempre piu' grezzo
        if t > 0.1 {
            if i % 5 == 0 {
                held = v;
            }
            v = held;
        }
        *s = v;
    }
    out
}

fn roll(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x501);
    let n = secs(0.45);
    let mut out = make(n);
    let mut f = Svf::new(400.0, 0.9);
    let mut o = Osc::new(0.0);
    let mut crackle = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / n as f32;
        let hump = (t * std::f32::consts::PI).sin();
        f.set(300.0 + 1100.0 * hump, 0.9);
        let noise = f.process(rng.signed()).low;
        if rng.chance(0.004) {
            crackle = rng.range(0.4, 1.0);
        }
        crackle *= 0.97;
        *s = (noise * 1.4 + o.sine(78.0) * 0.25 + crackle * rng.signed() * 0.35) * hump.powf(0.7);
    }
    out
}

fn step(seed: u64, variant: u32) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ (0x9000 + variant as u64 * 7919));
    let n = secs(0.14);
    let mut out = make(n);
    let fc = rng.range(900.0, 1800.0);
    let mut f = Svf::new(fc, 1.2);
    let pitch = rng.range(0.9, 1.15);
    let mut phase = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let tap = f.process(rng.signed()).band * decay(t, 0.018);
        phase += (75.0 + 60.0 * decay(t, 0.012)) * pitch / SR;
        let thump = (phase * TAU).sin() * decay(t, 0.05) * 0.8;
        let tick = (TAU * 3200.0 * t).sin() * decay(t, 0.003) * 0.15;
        *s = tap + thump + tick;
    }
    out
}

fn blip() -> Vec<f32> {
    let n = secs(0.12);
    let mut out = make(n);
    let mut o = Osc::new(0.0);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let f = if t < 0.05 { 880.0 } else { 1320.0 };
        *s = o.sine(f) * smooth((0.12 - t) / 0.06).min(1.0);
    }
    out
}

fn enemy_windup(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0xBEEF);
    let n = secs(0.65);
    let mut out = make(n);
    let mut o = Osc::new(rng.f32());
    let mut o2 = Osc::new(0.0);
    let mut f = Svf::new(600.0, 1.5);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / n as f32;
        let freq = exp_lerp(160.0, 900.0, t * t);
        f.set(freq * 3.0, 1.5);
        let ticks = 0.65 + 0.35 * (TAU * 28.0 * t * 0.65).sin();
        let env = smooth(t / 0.3) * (0.4 + 0.6 * t);
        *s = (f.process(o.saw(freq)).low * ticks + o2.sine(freq * 2.0) * 0.15) * env;
    }
    out
}

fn enemy_lunge(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x1234);
    let n = secs(0.3);
    let mut out = make(n);
    let mut f = Svf::new(3200.0, 0.9);
    let mut phase = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / n as f32;
        f.set(exp_lerp(3200.0, 400.0, t), 0.9);
        let whoosh = f.process(rng.signed()).low * smooth(t / 0.15) * (1.0 - smooth((t - 0.5) / 0.5));
        phase += (110.0 - 40.0 * t) / SR;
        *s = whoosh * 1.6 + (phase * TAU).sin() * 0.3 * decay(t, 0.4);
    }
    out
}

fn enemy_hurt(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x4242);
    let n = secs(0.25);
    let mut out = make(n);
    let mut o = Osc::new(0.0);
    let mut f = Svf::new(1500.0, 1.0);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let freq = exp_lerp(320.0, 140.0, (t / 0.25).min(1.0));
        let buzz = f.process(o.saw(freq)).low * decay(t, 0.09);
        let click = rng.signed() * decay(t, 0.006) * 0.5;
        *s = buzz + click;
    }
    out
}

fn enemy_die(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0xDEAD);
    let n = secs(1.0);
    let mut out = make(n);
    let mut phase = 0.0f32;
    let mut held = 0.0f32;
    let mut crackle = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        phase += exp_lerp(500.0, 50.0, (t / 0.8).min(1.0)) / SR;
        let sine = (phase * TAU).sin() * decay(t, 0.35);
        if rng.chance(0.006) {
            crackle = rng.range(0.3, 1.0);
        }
        crackle *= 0.96;
        let metal = ((TAU * 610.0 * t).sin() + (TAU * 953.0 * t).sin() * 0.7) * decay(t, 0.12) * 0.25;
        let mut v = sine * 0.7 + crackle * rng.signed() * 0.4 + metal;
        let crush = 1 + (t * 14.0) as usize;
        if i % crush == 0 {
            held = v;
        }
        v = held;
        *s = v * (1.0 - smooth((t - 0.5) / 0.5));
    }
    out
}

fn fall() -> Vec<f32> {
    let n = secs(1.3);
    let mut out = make(n);
    let mut phase = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let f = exp_lerp(1300.0, 180.0, (t / 1.2).min(1.0)) + 20.0 * (TAU * 6.0 * t).sin();
        phase += f / SR;
        *s = (phase * TAU).sin() * (1.0 - smooth(t / 1.3)) * smooth(t / 0.03);
    }
    out
}

fn death() -> Vec<f32> {
    let n = secs(2.4);
    let mut out = make(n);
    let mut o1 = Osc::new(0.0);
    let mut o2 = Osc::new(0.5);
    let mut o3 = Osc::new(0.0);
    let mut f = Svf::new(600.0, 0.9);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        f.set(exp_lerp(600.0, 90.0, (t / 2.2).min(1.0)), 0.9);
        let drone = f.process(o1.saw(55.0 * (1.0 - 0.15 * t / 2.4)) + o2.saw(82.4 * (1.0 - 0.15 * t / 2.4))).low;
        let sub = o3.sine(41.0);
        let env = smooth(t / 0.15) * (1.0 - smooth((t - 1.2) / 1.2));
        *s = (drone * 0.5 + sub * 0.5) * env;
    }
    reverb_mono(&out, 0.85, 0.6, 0.5, 1.0)
}

// ---------------------------------------------------------------------------
// Mondo e oggetti
// ---------------------------------------------------------------------------

fn chest_open(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0xC0FF);
    let n = secs(1.7);
    let mut out = make(n);
    let mut o = Osc::new(0.0);
    let mut f = Svf::new(700.0, 3.5);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        if t > 0.6 {
            break;
        }
        let freq = 85.0 + 55.0 * smooth(t / 0.5) + 4.0 * (TAU * 9.0 * t).sin();
        f.set(700.0 + 500.0 * (TAU * 1.7 * t).sin() + rng.signed() * 20.0, 3.5);
        let env = smooth(t / 0.08) * (1.0 - smooth((t - 0.4) / 0.2));
        *s = f.process(o.saw(freq)).band * env * 1.6;
    }
    for (k, midi) in [76.0f32, 79.0, 83.0, 88.0].iter().enumerate() {
        let bell = fm_bell(midi_hz(*midi), 0.9, 0.4 - 0.04 * k as f32, 3.5, 1.2);
        mix_into(&mut out, &bell, secs(0.5 + 0.12 * k as f32), 1.0);
    }
    reverb_mono(&out, 0.6, 0.5, 0.35, 1.0)
}

fn pad(notes: &[f32], dur: f32, attack: f32, release: f32, cutoff: f32) -> Vec<f32> {
    let n = secs(dur + release);
    let mut out = make(n);
    let mut oscs: Vec<(Osc, Osc, f32)> = notes
        .iter()
        .enumerate()
        .map(|(i, m)| (Osc::new(i as f32 * 0.13), Osc::new(i as f32 * 0.29 + 0.5), midi_hz(*m)))
        .collect();
    let mut f = Svf::new(cutoff, 0.8);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let mut v = 0.0;
        for (a, b, hz) in oscs.iter_mut() {
            v += a.saw(*hz * 1.003) + b.saw(*hz * 0.997);
        }
        f.set(cutoff * (0.7 + 0.3 * smooth(t / (attack * 1.5))), 0.8);
        let env = smooth(t / attack) * if t > dur { (-(t - dur) / (release * 0.35)).exp() } else { 1.0 };
        *s = f.process(v / (notes.len() as f32 * 2.0)).low * env;
    }
    out
}

fn item_get() -> Vec<f32> {
    let mut out = pad(&[60.0, 64.0, 67.0, 71.0], 0.9, 0.35, 1.3, 1800.0);
    for (k, midi) in [72.0f32, 76.0, 79.0, 84.0, 88.0].iter().enumerate() {
        let bell = fm_bell(midi_hz(*midi), 1.3, 0.55, 3.5, 1.4);
        mix_into(&mut out, &bell, secs(0.13 * k as f32), 0.9);
    }
    reverb_mono(&out, 0.8, 0.45, 0.45, 1.4)
}

fn shrine_rest() -> Vec<f32> {
    let mut out = pad(&[45.0, 57.0, 60.0, 64.0, 67.0, 71.0], 2.0, 0.9, 1.6, 1400.0);
    for (midi, when) in [(81.0f32, 0.5f32), (76.0, 1.1), (88.0, 1.7)] {
        let bell = fm_bell(midi_hz(midi), 2.0, 0.28, 3.5, 1.0);
        mix_into(&mut out, &bell, secs(when), 1.0);
    }
    reverb_mono(&out, 0.9, 0.5, 0.55, 1.5)
}

fn lever(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x1E7E);
    let n = secs(0.7);
    let mut out = make(n);
    let partials = [410.0, 980.0, 1630.0, 2290.0];
    let mut phase = 0.0f32;
    let mut hp = Svf::new(3000.0, 0.8);
    let mut rattles: Vec<f32> = (0..9).map(|_| rng.range(0.05, 0.45)).collect();
    rattles.sort_by(|a, b| a.partial_cmp(b).unwrap());
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        phase += (50.0 + 40.0 * decay(t, 0.03)) / SR;
        let thump = (phase * TAU).sin() * decay(t, 0.1);
        let mut clank = 0.0;
        for (k, p) in partials.iter().enumerate() {
            clank += (TAU * p * t).sin() * decay(t, 0.12 + 0.07 * k as f32) * 0.22;
        }
        let mut chain = 0.0;
        for r in &rattles {
            if t > *r {
                chain += decay(t - r, 0.012);
            }
        }
        let chain = hp.process(rng.signed()).high * chain * 0.4;
        *s = thump * 0.9 + clank + chain;
    }
    out
}

fn gate_open(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x6A7E);
    let n = secs(3.2);
    let mut out = make(n);
    let mut o1 = Osc::new(0.0);
    let mut o2 = Osc::new(0.0);
    let mut o3 = Osc::new(0.0);
    let mut lp_noise = Svf::new(280.0, 0.8);
    let mut lp_saw = Svf::new(280.0, 0.8);
    let mut bp = Svf::new(1200.0, 2.0);
    let mut crack = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let env = smooth(t / 0.3) * (1.0 - smooth((t - 2.5) / 0.7));
        let rumble = o1.sine(36.0) + o2.sine(54.0) * 0.6;
        let grind = lp_noise.process(rng.signed()).low * (0.6 + 0.4 * (TAU * 6.5 * t + rng.signed() * 0.3).sin());
        let scrape = lp_saw.process(o3.saw(55.0)).low * 0.3;
        if rng.chance(0.0003) {
            crack = 1.0;
        }
        crack *= 0.985;
        let stone = bp.process(rng.signed()).band * crack * 0.6;
        *s = (rumble * 0.45 + grind * 1.8 + scrape + stone) * env;
    }
    out
}

fn bridge_reveal() -> Vec<f32> {
    let n = secs(2.0);
    let mut out = make(n);
    let mut phases = [0.0f32; 7];
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let mut v = 0.0;
        for (k, ph) in phases.iter_mut().enumerate() {
            let start = k as f32 * 0.12;
            if t < start {
                continue;
            }
            let lt = t - start;
            let base = midi_hz(60.0 + k as f32 * 4.0);
            let f = base * (1.0 + 0.5 * smooth(lt / 0.6));
            *ph += f / SR;
            let trem = 0.6 + 0.4 * (TAU * (5.0 + k as f32) * t).sin();
            v += (*ph * TAU).sin() * smooth(lt / 0.2) * decay(lt, 0.9) * trem * 0.2;
        }
        *s = v;
    }
    // Le voci suonano ancora alla fine: senza dissolvenza il riverbero riceverebbe un taglio (click).
    fade_edges(&mut out, 0.0, 0.5);
    reverb_mono(&out, 0.85, 0.4, 0.5, 1.5)
}

fn page(seed: u64, closing: bool) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x9A6E);
    let n = secs(0.28);
    let mut out = make(n);
    let mut f = Svf::new(4500.0, 0.8);
    let mut burst = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / n as f32;
        if rng.chance(0.01) {
            burst = rng.range(0.5, 1.0);
        }
        burst *= 0.995;
        let env = if closing { smooth((1.0 - t) / 0.6) } else { smooth(t / 0.15) * (1.0 - smooth((t - 0.4) / 0.6)) };
        *s = f.process(rng.signed()).band * (0.25 + burst) * env * 2.0;
    }
    out
}

fn lantern_on() -> Vec<f32> {
    let n = secs(1.2);
    let mut out = make(n);
    let mut o = [Osc::new(0.0), Osc::new(0.2), Osc::new(0.4)];
    let hz = [midi_hz(62.0), midi_hz(69.0), midi_hz(74.0)];
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let mut v = 0.0;
        for k in 0..3 {
            v += o[k].sine(hz[k]) * 0.5 + o[k].tri(hz[k] * 2.0) * 0.1;
        }
        *s = v * smooth(t / 0.4) * (1.0 - smooth((t - 0.6) / 0.6)) * 0.4;
    }
    for (k, midi) in [86.0f32, 91.0, 98.0].iter().enumerate() {
        let bell = fm_bell(midi_hz(*midi), 0.9, 0.3, 3.5, 0.8);
        mix_into(&mut out, &bell, secs(0.15 + 0.1 * k as f32), 1.0);
    }
    reverb_mono(&out, 0.75, 0.4, 0.4, 1.0)
}

fn heal() -> Vec<f32> {
    let n = secs(0.9);
    let mut out = make(n);
    for (k, midi) in [67.0f32, 71.0, 74.0, 79.0].iter().enumerate() {
        let bell = fm_bell(midi_hz(*midi), 0.7, 0.45, 2.0, 0.5);
        mix_into(&mut out, &bell, secs(0.09 * k as f32), 1.0);
    }
    reverb_mono(&out, 0.7, 0.4, 0.4, 0.8)
}

/// Tre sorsi: gorgoglii che salgono di tono, con un soffio d'aria.
fn drink(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0xD21);
    let n = secs(0.7);
    let mut out = make(n);
    let mut f = Svf::new(900.0, 1.2);
    let mut phase = 0.0f32;
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let mut gulp = 0.0;
        for k in 0..3 {
            let start = 0.08 + 0.2 * k as f32;
            if t >= start {
                let lt = t - start;
                let hz = exp_lerp(240.0 + 30.0 * k as f32, 560.0 + 60.0 * k as f32, (lt / 0.09).min(1.0));
                phase += hz / SR;
                gulp += (phase * TAU).sin() * decay(lt, 0.05) * smooth(lt / 0.005);
            }
        }
        let air = f.process(rng.signed()).band * 0.12 * smooth(t / 0.2) * (1.0 - smooth((t - 0.5) / 0.2));
        *s = gulp * 0.7 + air;
    }
    reverb_mono(&out, 0.4, 0.6, 0.15, 0.2)
}

/// Sparo di una sentinella: zap discendente con uno scatto di rumore.
fn shot(seed: u64) -> Vec<f32> {
    let mut rng = Rng::new(seed ^ 0x5407);
    let n = secs(0.25);
    let mut out = make(n);
    let mut o = Osc::new(0.0);
    let mut f = Svf::new(3000.0, 1.4);
    for (i, s) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let hz = exp_lerp(1500.0, 260.0, (t / 0.2).min(1.0));
        f.set(hz * 3.0, 1.4);
        let zap = f.process(o.saw(hz)).low * decay(t, 0.09);
        let click = rng.signed() * decay(t, 0.004) * 0.6;
        *s = zap + click;
    }
    out
}

// ---------------------------------------------------------------------------
// Musica ambientale generativa (loop senza giunture)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct Stereo {
    pub l: Vec<f32>,
    pub r: Vec<f32>,
}

/// Progressione in Re dorico: Dm9 - Bbmaj7 - Gm9 - Asus4.
const CHORDS: [[f32; 6]; 4] = [
    [38.0, 50.0, 53.0, 57.0, 60.0, 64.0],
    [34.0, 46.0, 53.0, 57.0, 62.0, 65.0],
    [43.0, 55.0, 58.0, 62.0, 65.0, 69.0],
    [33.0, 45.0, 52.0, 57.0, 62.0, 64.0],
];

#[allow(clippy::too_many_arguments)]
fn pad_voice(freq: f32, dur: f32, attack: f32, release: f32, phase: f32, cutoff: f32, lfo_hz: f32, cancel: &AtomicBool) -> Vec<f32> {
    let n = secs(dur + release);
    let mut out = make(n);
    let mut a = Osc::new(phase);
    let mut b = Osc::new(phase + 0.37);
    let mut f = Svf::new(cutoff, 0.7);
    for (i, s) in out.iter_mut().enumerate() {
        if i & 0x3FFF == 0 && cancel.load(Ordering::Relaxed) {
            return out;
        }
        let t = i as f32 / SR;
        let v = a.saw(freq * 1.002) + b.saw(freq * 0.998);
        let lfo = 0.75 + 0.25 * (TAU * lfo_hz * t + phase * 6.0).sin();
        // I filtri costosi si aggiornano ogni 16 campioni: il cutoff cambia lentamente.
        if i % 16 == 0 {
            f.set(cutoff * lfo, 0.7);
        }
        let env = smooth(t / attack) * if t > dur { (-(t - dur) / (release * 0.3)).exp() } else { 1.0 };
        *s = f.process(v * 0.5).low * env;
    }
    out
}

/// Un accordo del pad: tre buffer (sinistra, destra, mandata al riverbero) che iniziano a `section * ci`.
/// Il seme dipende solo da (seed, ci): il risultato e' identico anche se i thread finiscono in ordine diverso.
fn render_chord(seed: u64, ci: usize, section: f32, cancel: &AtomicBool) -> (usize, Vec<f32>, Vec<f32>, Vec<f32>) {
    let mut rng = Rng::new(seed ^ (0xC40D + ci as u64 * 0x9E37_79B9));
    let start = secs(section * ci as f32);
    let (mut l, mut r, mut send) = (Vec::new(), Vec::new(), Vec::new());
    for (ni, midi) in CHORDS[ci].iter().enumerate() {
        let hz = midi_hz(*midi);
        let low = *midi < 45.0;
        let cutoff = if low { 380.0 } else { (hz * 2.6).clamp(500.0, 2400.0) };
        let gain = if low { 0.34 } else { 0.17 };
        let dur = section + 3.0;
        let seed_phase = rng.f32();
        let lfo = rng.range(0.05, 0.13);
        let vl = pad_voice(hz, dur, 3.5, 5.5, seed_phase, cutoff, lfo, cancel);
        let vr = pad_voice(hz, dur, 3.5, 5.5, seed_phase + 0.41 + ni as f32 * 0.07, cutoff, lfo * 1.1, cancel);
        mix_into(&mut l, &vl, 0, gain);
        mix_into(&mut r, &vr, 0, gain);
        if !low {
            mix_into(&mut send, &vl, 0, gain * 0.5);
            mix_into(&mut send, &vr, 0, gain * 0.5);
        }
    }
    (start, l, r, send)
}

/// Musica ambientale a loop. `loop_secs` e' la durata del ciclo (ogni accordo ne occupa un quarto).
pub fn render_ambient(seed: u64, loop_secs: f32) -> Stereo {
    render_ambient_cancellable(seed, loop_secs, &AtomicBool::new(false)).expect("mai annullato")
}

/// Come `render_ambient`, ma si interrompe (ritornando `None`) appena `cancel` diventa vero.
/// Serve a chiudere il gioco subito, senza aspettare un rendering di un secondo.
pub fn render_ambient_cancellable(seed: u64, loop_secs: f32, cancel: &AtomicBool) -> Option<Stereo> {
    let mut rng = Rng::new(seed ^ 0xA3B1_E27);
    let loop_n = secs(loop_secs);
    let tail_secs = 10.0;
    let total = loop_n + secs(tail_secs);
    let section = loop_secs / CHORDS.len() as f32;

    let mut dry_l = vec![0.0f32; total];
    let mut dry_r = vec![0.0f32; total];
    let mut send = vec![0.0f32; total];

    // Gli accordi sono indipendenti: un thread ciascuno.
    let chords: Vec<(usize, Vec<f32>, Vec<f32>, Vec<f32>)> = std::thread::scope(|s| {
        let handles: Vec<_> = (0..CHORDS.len())
            .map(|ci| {
                s.spawn(move || {
                    crate::sys::background_priority();
                    render_chord(seed, ci, section, cancel)
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().expect("thread del pad")).collect()
    });
    if cancel.load(Ordering::Relaxed) {
        return None;
    }
    for (start, l, r, sd) in &chords {
        mix_into(&mut dry_l, l, *start, 1.0);
        mix_into(&mut dry_r, r, *start, 1.0);
        mix_into(&mut send, sd, *start, 1.0);
    }

    // Campane rade: note del modo dorico scelte tra i toni dell'accordo corrente e la nona.
    let mut t = 1.5f32;
    while t < loop_secs - 1.0 {
        let ci = ((t / section) as usize).min(CHORDS.len() - 1);
        let chord = &CHORDS[ci];
        let base = chord[1 + rng.below(5) as usize];
        let midi = base + 12.0 * (1 + rng.below(2)) as f32 + if rng.chance(0.2) { 2.0 } else { 0.0 };
        let vel = rng.range(0.12, 0.34);
        let dur = rng.range(2.5, 4.0);
        let bell = fm_bell(midi_hz(midi), dur, vel, 3.5, rng.range(0.6, 1.2));
        let pan = rng.range(-0.7, 0.7);
        let (gl, gr) = ((1.0 - pan) * 0.5, (1.0 + pan) * 0.5);
        let off = secs(t);
        mix_into(&mut dry_l, &bell, off, gl.sqrt() * 0.3);
        mix_into(&mut dry_r, &bell, off, gr.sqrt() * 0.3);
        mix_into(&mut send, &bell, off, 0.8);
        t += rng.range(1.4, 4.2);
    }

    // Vento: rumore rosa filtrato che respira lentamente.
    let mut pink = Pink::default();
    let mut wf = Svf::new(500.0, 0.6);
    for i in 0..total {
        if i & 0x3FFF == 0 && cancel.load(Ordering::Relaxed) {
            return None;
        }
        let ts = i as f32 / SR;
        if i % 32 == 0 {
            wf.set(450.0 + 300.0 * (TAU * 0.043 * ts).sin(), 0.6);
        }
        let w = wf.process(pink.next(&mut rng)).band * (0.55 + 0.45 * (TAU * 0.071 * ts + 1.0).sin()) * 0.5;
        dry_l[i] += w * 0.5;
        dry_r[i] += w * 0.5;
    }

    // Riverbero lungo sul segnale di mandata.
    let mut rv = Reverb::new(0.93, 0.55);
    for i in 0..total {
        if i & 0x3FFF == 0 && cancel.load(Ordering::Relaxed) {
            return None;
        }
        let (rl, rr) = rv.process(send[i]);
        dry_l[i] += rl * 0.9;
        dry_r[i] += rr * 0.9;
    }

    // Chiusura del loop: la coda oltre la fine si somma all'inizio => nessuna giuntura.
    let mut l = vec![0.0f32; loop_n];
    let mut r = vec![0.0f32; loop_n];
    for i in 0..total {
        l[i % loop_n] += dry_l[i];
        r[i % loop_n] += dry_r[i];
    }

    let mut st = Stereo { l, r };
    finalize_stereo(&mut st, 0.7);
    Some(st)
}

fn finalize_stereo(st: &mut Stereo, target_peak: f32) {
    remove_dc(&mut st.l);
    remove_dc(&mut st.r);
    let p = peak(&st.l).max(peak(&st.r));
    if p > 1e-9 {
        let g = target_peak / p;
        for v in st.l.iter_mut().chain(st.r.iter_mut()) {
            *v *= g;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_sfx_is_clean() {
        for name in SFX_NAMES {
            let a = render_sfx(name, 1234).unwrap_or_else(|| panic!("manca {name}"));
            assert!(a.len() > secs(0.05), "{name}: troppo corto");
            assert!(a.len() < secs(6.0), "{name}: troppo lungo ({})", a.len());
            assert!(a.iter().all(|v| v.is_finite()), "{name}: valori non finiti");
            let p = peak(&a);
            assert!(p > 0.25 && p <= 1.0, "{name}: picco {p}");
            let mean = a.iter().sum::<f32>() / a.len() as f32;
            assert!(mean.abs() < 0.02, "{name}: DC {mean}");
            assert!(a[0].abs() < 0.05, "{name}: parte con un click ({})", a[0]);
            assert!(a[a.len() - 1].abs() < 0.02, "{name}: finisce con un click ({})", a[a.len() - 1]);
            assert!(rms(&a) > 0.01, "{name}: quasi silenzioso");
        }
    }

    #[test]
    fn unknown_sfx_is_none() {
        assert!(render_sfx("non_esiste", 1).is_none());
    }

    #[test]
    fn sfx_are_deterministic() {
        for name in SFX_NAMES {
            assert_eq!(render_sfx(name, 99), render_sfx(name, 99), "{name} non deterministico");
        }
    }

    #[test]
    fn variants_differ_by_seed() {
        for name in ["step", "hit_enemy", "swing", "lever"] {
            assert_ne!(render_sfx(name, 1), render_sfx(name, 2), "{name} uguale con semi diversi");
        }
        // le quattro varianti dei passi sono davvero diverse
        assert_ne!(render_sfx("step", 5), render_sfx("step2", 5));
    }

    #[test]
    fn hits_are_louder_than_footsteps_in_character() {
        // il colpo ha piu' energia nei bassi di un passo: l'RMS grezzo dopo la normalizzazione
        // e' simile, ma la durata e' molto diversa.
        let hit = render_sfx("hit_enemy", 1).unwrap();
        let st = render_sfx("step", 1).unwrap();
        assert!(hit.len() > st.len() * 2);
    }

    #[test]
    fn ambient_loops_seamlessly_and_is_quiet() {
        let m = render_ambient(7, 24.0);
        assert_eq!(m.l.len(), m.r.len());
        assert_eq!(m.l.len(), secs(24.0));
        assert!(m.l.iter().chain(m.r.iter()).all(|v| v.is_finite()));
        let p = peak(&m.l).max(peak(&m.r));
        assert!(p > 0.6 && p <= 0.71, "picco {p}");
        // giuntura: salto tra ultimo e primo campione paragonabile a un salto normale
        let max_step = m.l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
        let seam = (m.l[0] - m.l[m.l.len() - 1]).abs();
        assert!(seam <= max_step * 1.5 + 1e-4, "giuntura {seam} > passo massimo {max_step}");
        // e' musica d'ambiente: tranquilla, ma non silenziosa
        let r = rms(&m.l);
        assert!(r > 0.02 && r < 0.3, "rms {r}");
        // stereo vero: i due canali non sono identici
        let diff = m.l.iter().zip(m.r.iter()).map(|(a, b)| (a - b).abs()).sum::<f32>() / m.l.len() as f32;
        assert!(diff > 0.002, "canali troppo simili ({diff})");
    }

    #[test]
    fn ambient_render_can_be_cancelled_quickly() {
        let cancel = AtomicBool::new(true);
        let t = std::time::Instant::now();
        assert!(render_ambient_cancellable(1, 64.0, &cancel).is_none());
        assert!(t.elapsed().as_millis() < 300, "l'annullamento deve essere quasi immediato: {:?}", t.elapsed());
        // Non annullato: stesso risultato di render_ambient.
        let a = render_ambient_cancellable(3, 8.0, &AtomicBool::new(false)).unwrap();
        assert_eq!(a.l, render_ambient(3, 8.0).l);
    }

    #[test]
    fn ambient_is_deterministic() {
        let a = render_ambient(5, 8.0);
        let b = render_ambient(5, 8.0);
        assert_eq!(a.l, b.l);
        let c = render_ambient(6, 8.0);
        assert_ne!(a.l, c.l);
    }
}
