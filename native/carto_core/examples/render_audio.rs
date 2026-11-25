//! Scrive tutti i suoni come file .wav per ascolto e analisi (spettrogrammi).
//! Uso: cargo run --profile fast -p carto_core --example render_audio -- <cartella> [secondi_musica]

use carto_core::{dsp::SAMPLE_RATE, synth, wav};
use std::{env, fs, path::PathBuf, time::Instant};

fn main() {
    let dir = PathBuf::from(env::args().nth(1).expect("serve la cartella di output"));
    let music_secs: f32 = env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(64.0);
    fs::create_dir_all(&dir).unwrap();

    let t0 = Instant::now();
    let mut total = 0usize;
    for name in synth::SFX_NAMES {
        let t = Instant::now();
        let buf = synth::render_sfx(name, 2024).unwrap();
        let pcm = wav::pcm16_mono(&buf);
        total += buf.len();
        fs::write(dir.join(format!("{name}.wav")), wav::wav_file(&pcm, 1, SAMPLE_RATE)).unwrap();
        println!("{name:<14} {:>6.2} s  render {:>6.1} ms", buf.len() as f32 / SAMPLE_RATE as f32, t.elapsed().as_secs_f32() * 1000.0);
    }
    println!("TOTALE effetti: {:.1} s di audio in {:.0} ms", total as f32 / SAMPLE_RATE as f32, t0.elapsed().as_secs_f32() * 1000.0);

    let t = Instant::now();
    let m = synth::render_ambient(1, music_secs);
    let pcm = wav::pcm16_stereo(&m.l, &m.r);
    fs::write(dir.join("music_ambient.wav"), wav::wav_file(&pcm, 2, SAMPLE_RATE)).unwrap();
    println!("music_ambient  {music_secs:.0} s  render {:.0} ms", t.elapsed().as_secs_f32() * 1000.0);
}
