//! Mattoni di elaborazione del segnale: oscillatori, filtri, riverbero, inviluppi.

use crate::rng::Rng;
use std::f32::consts::{PI, TAU};

pub const SAMPLE_RATE: u32 = 44_100;
pub const SR: f32 = SAMPLE_RATE as f32;

/// Secondi -> numero di campioni.
#[inline]
pub fn secs(s: f32) -> usize {
    (s * SR).round().max(0.0) as usize
}

#[inline]
pub fn midi_hz(note: f32) -> f32 {
    440.0 * 2f32.powf((note - 69.0) / 12.0)
}

/// Interpolazione esponenziale tra a e b (entrambi > 0), t in [0, 1].
#[inline]
pub fn exp_lerp(a: f32, b: f32, t: f32) -> f32 {
    a * (b / a).powf(t)
}

#[inline]
pub fn smooth(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Decadimento esponenziale: 1 a t=0, e^-1 a t=tau.
#[inline]
pub fn decay(t: f32, tau: f32) -> f32 {
    (-t / tau).exp()
}

// ---------------------------------------------------------------------------
// Oscillatori
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct Osc {
    phase: f32,
}

#[inline]
fn poly_blep(t: f32, dt: f32) -> f32 {
    if t < dt {
        let t = t / dt;
        t + t - t * t - 1.0
    } else if t > 1.0 - dt {
        let t = (t - 1.0) / dt;
        t * t + t + t + 1.0
    } else {
        0.0
    }
}

impl Osc {
    pub fn new(phase: f32) -> Self {
        Osc { phase: phase.fract().abs() }
    }

    #[inline]
    fn advance(&mut self, freq: f32) {
        self.phase += freq / SR;
        if self.phase >= 1.0 {
            self.phase -= 1.0;
        }
    }

    #[inline]
    pub fn sine(&mut self, freq: f32) -> f32 {
        let v = (self.phase * TAU).sin();
        self.advance(freq);
        v
    }

    /// Dente di sega senza aliasing (PolyBLEP).
    #[inline]
    pub fn saw(&mut self, freq: f32) -> f32 {
        let dt = (freq / SR).min(0.49);
        let v = 2.0 * self.phase - 1.0 - poly_blep(self.phase, dt);
        self.advance(freq);
        v
    }

    #[inline]
    pub fn square(&mut self, freq: f32) -> f32 {
        let dt = (freq / SR).min(0.49);
        let mut v = if self.phase < 0.5 { 1.0 } else { -1.0 };
        v += poly_blep(self.phase, dt);
        v -= poly_blep((self.phase + 0.5).fract(), dt);
        self.advance(freq);
        v
    }

    #[inline]
    pub fn tri(&mut self, freq: f32) -> f32 {
        let v = 4.0 * (self.phase - 0.5).abs() - 1.0;
        self.advance(freq);
        v
    }
}

// ---------------------------------------------------------------------------
// Filtri
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Default)]
pub struct SvfOut {
    pub low: f32,
    pub band: f32,
    pub high: f32,
}

/// Filtro a variabile di stato (trapezoidale, Simper): stabile anche con cutoff modulato.
#[derive(Clone, Debug)]
pub struct Svf {
    ic1: f32,
    ic2: f32,
    k: f32,
    a1: f32,
    a2: f32,
    a3: f32,
}

impl Svf {
    pub fn new(cutoff: f32, q: f32) -> Self {
        let mut s = Svf { ic1: 0.0, ic2: 0.0, k: 1.0, a1: 0.0, a2: 0.0, a3: 0.0 };
        s.set(cutoff, q);
        s
    }

    #[inline]
    pub fn set(&mut self, cutoff: f32, q: f32) {
        let cutoff = cutoff.clamp(10.0, SR * 0.45);
        let g = (PI * cutoff / SR).tan();
        self.k = 1.0 / q.max(0.05);
        self.a1 = 1.0 / (1.0 + g * (g + self.k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
    }

    #[inline]
    pub fn process(&mut self, v0: f32) -> SvfOut {
        let v3 = v0 - self.ic2;
        let v1 = self.a1 * self.ic1 + self.a2 * v3;
        let v2 = self.ic2 + self.a2 * self.ic1 + self.a3 * v3;
        self.ic1 = 2.0 * v1 - self.ic1;
        self.ic2 = 2.0 * v2 - self.ic2;
        SvfOut { low: v2, band: v1, high: v0 - self.k * v1 - v2 }
    }
}

/// Rumore rosa (filtro di Paul Kellet).
#[derive(Clone, Debug, Default)]
pub struct Pink {
    b0: f32,
    b1: f32,
    b2: f32,
}

impl Pink {
    #[inline]
    pub fn next(&mut self, rng: &mut Rng) -> f32 {
        let w = rng.signed();
        self.b0 = 0.99765 * self.b0 + w * 0.099_046;
        self.b1 = 0.963 * self.b1 + w * 0.296_516_4;
        self.b2 = 0.57 * self.b2 + w * 1.052_691_3;
        (self.b0 + self.b1 + self.b2 + w * 0.1848) * 0.25
    }
}

// ---------------------------------------------------------------------------
// Riverbero (Freeverb)
// ---------------------------------------------------------------------------

struct Comb {
    buf: Vec<f32>,
    idx: usize,
    feedback: f32,
    damp1: f32,
    damp2: f32,
    store: f32,
}

impl Comb {
    fn new(len: usize, feedback: f32, damp: f32) -> Self {
        Comb { buf: vec![0.0; len], idx: 0, feedback, damp1: damp, damp2: 1.0 - damp, store: 0.0 }
    }

    #[inline]
    fn process(&mut self, input: f32) -> f32 {
        let out = self.buf[self.idx];
        self.store = out * self.damp2 + self.store * self.damp1;
        self.buf[self.idx] = input + self.store * self.feedback;
        self.idx += 1;
        if self.idx == self.buf.len() {
            self.idx = 0;
        }
        out
    }
}

struct Allpass {
    buf: Vec<f32>,
    idx: usize,
}

impl Allpass {
    fn new(len: usize) -> Self {
        Allpass { buf: vec![0.0; len], idx: 0 }
    }

    #[inline]
    fn process(&mut self, input: f32) -> f32 {
        let b = self.buf[self.idx];
        let out = -input + b;
        self.buf[self.idx] = input + b * 0.5;
        self.idx += 1;
        if self.idx == self.buf.len() {
            self.idx = 0;
        }
        out
    }
}

const COMB_TUNING: [usize; 8] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const ALLPASS_TUNING: [usize; 4] = [556, 441, 341, 225];
const STEREO_SPREAD: usize = 23;

pub struct Reverb {
    combs_l: Vec<Comb>,
    combs_r: Vec<Comb>,
    ap_l: Vec<Allpass>,
    ap_r: Vec<Allpass>,
}

impl Reverb {
    /// `room` e `damp` in [0, 1]. Stanza grande = room alto; damp alto = coda piu' scura.
    pub fn new(room: f32, damp: f32) -> Self {
        let feedback = room.clamp(0.0, 1.0) * 0.28 + 0.7;
        let damp = damp.clamp(0.0, 1.0) * 0.4;
        let combs_l = COMB_TUNING.iter().map(|&l| Comb::new(l, feedback, damp)).collect();
        let combs_r = COMB_TUNING.iter().map(|&l| Comb::new(l + STEREO_SPREAD, feedback, damp)).collect();
        let ap_l = ALLPASS_TUNING.iter().map(|&l| Allpass::new(l)).collect();
        let ap_r = ALLPASS_TUNING.iter().map(|&l| Allpass::new(l + STEREO_SPREAD)).collect();
        Reverb { combs_l, combs_r, ap_l, ap_r }
    }

    /// Elabora un campione mono; restituisce (sinistra, destra) del solo segnale riverberato.
    #[inline]
    pub fn process(&mut self, input: f32) -> (f32, f32) {
        let x = input * 0.015;
        let mut l = 0.0;
        let mut r = 0.0;
        for c in self.combs_l.iter_mut() {
            l += c.process(x);
        }
        for c in self.combs_r.iter_mut() {
            r += c.process(x);
        }
        for a in self.ap_l.iter_mut() {
            l = a.process(l);
        }
        for a in self.ap_r.iter_mut() {
            r = a.process(r);
        }
        (l * 3.0, r * 3.0)
    }
}

/// Aggiunge riverbero a un segnale mono, allungandolo di `tail_secs`. Ritorna mono (somma L+R).
pub fn reverb_mono(input: &[f32], room: f32, damp: f32, wet: f32, tail_secs: f32) -> Vec<f32> {
    let total = input.len() + secs(tail_secs);
    let mut rv = Reverb::new(room, damp);
    let mut out = vec![0.0f32; total];
    // Rete di sicurezza: gli ultimi 10 ms in dissolvenza, cosi' un taglio non diventa un click.
    let guard = secs(0.01).min(input.len());
    for i in 0..total {
        let mut x = if i < input.len() { input[i] } else { 0.0 };
        if i < input.len() && i >= input.len() - guard {
            x *= (input.len() - 1 - i) as f32 / guard as f32;
        }
        let (l, r) = rv.process(x);
        out[i] = x + (l + r) * 0.5 * wet;
    }
    out
}

// ---------------------------------------------------------------------------
// Voci e utilita' di buffer
// ---------------------------------------------------------------------------

/// Campana FM: portante + modulante inarmonica che decade piu' in fretta.
pub fn fm_bell(freq: f32, dur: f32, vel: f32, ratio: f32, index: f32) -> Vec<f32> {
    let n = secs(dur);
    let tau = dur * 0.28;
    let mut out = vec![0.0f32; n];
    for (i, o) in out.iter_mut().enumerate() {
        let t = i as f32 / SR;
        let attack = (t / 0.002).min(1.0);
        let m = (TAU * freq * ratio * t).sin() * index * decay(t, tau * 0.55);
        *o = (TAU * freq * t + m).sin() * decay(t, tau) * attack * vel;
    }
    fade_edges(&mut out, 0.0, 0.01);
    out
}

/// Somma `src` dentro `dst` a partire da `offset`, estendendo `dst` se serve.
pub fn mix_into(dst: &mut Vec<f32>, src: &[f32], offset: usize, gain: f32) {
    if dst.len() < offset + src.len() {
        dst.resize(offset + src.len(), 0.0);
    }
    for (d, s) in dst[offset..].iter_mut().zip(src.iter()) {
        *d += s * gain;
    }
}

pub fn peak(buf: &[f32]) -> f32 {
    buf.iter().fold(0.0f32, |m, v| m.max(v.abs()))
}

pub fn rms(buf: &[f32]) -> f32 {
    if buf.is_empty() {
        return 0.0;
    }
    (buf.iter().map(|v| (*v as f64) * (*v as f64)).sum::<f64>() / buf.len() as f64).sqrt() as f32
}

pub fn normalize(buf: &mut [f32], target_peak: f32) {
    let p = peak(buf);
    if p > 1e-9 {
        let g = target_peak / p;
        for v in buf.iter_mut() {
            *v *= g;
        }
    }
}

pub fn remove_dc(buf: &mut [f32]) {
    if buf.is_empty() {
        return;
    }
    let mean = buf.iter().map(|v| *v as f64).sum::<f64>() / buf.len() as f64;
    for v in buf.iter_mut() {
        *v -= mean as f32;
    }
}

/// Dissolvenze brevissime agli estremi: niente "click" all'inizio e alla fine.
pub fn fade_edges(buf: &mut [f32], fade_in_secs: f32, fade_out_secs: f32) {
    let n = buf.len();
    let fi = secs(fade_in_secs).min(n);
    let fo = secs(fade_out_secs).min(n);
    for i in 0..fi {
        buf[i] *= i as f32 / fi as f32;
    }
    for i in 0..fo {
        buf[n - 1 - i] *= i as f32 / fo as f32;
    }
}

/// Saturazione morbida (tanh).
#[inline]
pub fn soft_clip(x: f32) -> f32 {
    x.tanh()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sine_has_right_frequency() {
        let mut o = Osc::new(0.0);
        let n = SAMPLE_RATE as usize; // 1 secondo
        let buf: Vec<f32> = (0..n).map(|_| o.sine(440.0)).collect();
        let crossings = buf.windows(2).filter(|w| w[0] <= 0.0 && w[1] > 0.0).count();
        assert!((crossings as i32 - 440).abs() <= 1, "attraversamenti = {crossings}");
    }

    #[test]
    fn saw_is_bounded() {
        let mut o = Osc::new(0.0);
        for _ in 0..50_000 {
            let v = o.saw(1234.5);
            assert!(v.abs() < 1.2);
        }
    }

    #[test]
    fn svf_lowpass_attenuates_highs() {
        let mut rng = Rng::new(3);
        let noise: Vec<f32> = (0..20_000).map(|_| rng.signed()).collect();
        let mut f = Svf::new(500.0, 0.707);
        let lp: Vec<f32> = noise.iter().map(|&x| f.process(x).low).collect();
        assert!(rms(&lp[2000..]) < rms(&noise) * 0.35);
    }

    #[test]
    fn svf_is_stable_with_fast_modulation() {
        let mut rng = Rng::new(4);
        let mut f = Svf::new(100.0, 4.0);
        for i in 0..100_000 {
            f.set(100.0 + 8000.0 * ((i as f32 * 0.01).sin() * 0.5 + 0.5), 4.0);
            let o = f.process(rng.signed());
            assert!(o.low.is_finite() && o.band.is_finite() && o.high.is_finite());
            assert!(o.low.abs() < 50.0);
        }
    }

    #[test]
    fn reverb_produces_a_decaying_tail() {
        let mut impulse = vec![0.0f32; 100];
        impulse[0] = 1.0;
        let out = reverb_mono(&impulse, 0.8, 0.5, 1.0, 3.0);
        let early = rms(&out[1000..9000]);
        let late = rms(&out[out.len() - 9000..]);
        assert!(early > 1e-4, "niente coda");
        assert!(late < early, "la coda non decade: {early} -> {late}");
        assert!(out.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn helpers() {
        assert!((midi_hz(69.0) - 440.0).abs() < 1e-3);
        assert!((midi_hz(81.0) - 880.0).abs() < 1e-2);
        assert!((exp_lerp(100.0, 400.0, 0.5) - 200.0).abs() < 1e-3);
        let mut b = vec![0.5, -2.0, 1.0];
        normalize(&mut b, 0.8);
        assert!((peak(&b) - 0.8).abs() < 1e-6);
    }
}
