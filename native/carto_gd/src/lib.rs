//! Involucro GDExtension: espone `carto_core` a Godot. Qui NON c'e' logica di gioco,
//! solo conversioni di tipo e un po' di parallelismo.

use carto_core::{dsp::SAMPLE_RATE, synth, wav};
use godot::classes::audio_stream_wav::{Format, LoopMode};
use godot::classes::AudioStreamWav;
use godot::prelude::*;

struct CartoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CartoExtension {}

/// Audio procedurale: effetti sonori e musica sintetizzati da zero.
///
/// Uso da GDScript:
/// ```gdscript
/// var audio = CartoAudio.new()
/// var bank: Dictionary = audio.render_sfx_bank(1234)     # nome -> AudioStreamWAV
/// audio.start_render(1234, 64.0)        # parte in background, dentro Rust
/// # ...ogni frame: if audio.is_render_done(): var r = audio.take_render()
/// ```
///
/// NB: da un `Thread` di Godot NON si puo' chiamare l'estensione (gdext lo vieta e il processo si
/// interrompe). Per questo il thread di rendering vive dentro Rust e non tocca mai Godot.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct CartoAudio {
    base: Base<RefCounted>,
    job: Option<std::thread::JoinHandle<Rendered>>,
}

/// Risultato di un rendering in background: solo dati, nessun oggetto Godot.
struct Rendered {
    sfx: Vec<(&'static str, Vec<u8>)>,
    music: Vec<u8>,
    ms: i64,
}

#[godot_api]
impl CartoAudio {
    #[func]
    fn version(&self) -> GString {
        GString::from(concat!("carto ", env!("CARGO_PKG_VERSION")))
    }

    #[func]
    fn sample_rate(&self) -> i64 {
        SAMPLE_RATE as i64
    }

    /// Nomi di tutti gli effetti disponibili.
    #[func]
    fn sfx_names(&self) -> PackedStringArray {
        synth::SFX_NAMES.iter().map(|n| GString::from(*n)).collect()
    }

    /// Un singolo effetto (mono, 16 bit). `null` se il nome non esiste.
    #[func]
    fn render_sfx(&self, name: GString, seed: i64) -> Option<Gd<AudioStreamWav>> {
        let buf = synth::render_sfx(&name.to_string(), seed as u64)?;
        Some(make_stream(&wav::pcm16_mono(&buf), false, false))
    }

    /// Tutti gli effetti in un colpo, resi in parallelo. Ritorna `{nome: AudioStreamWAV}`.
    #[func]
    fn render_sfx_bank(&self, seed: i64) -> VarDictionary {
        let mut dict = VarDictionary::new();
        for (name, pcm) in render_bank_pcm(seed as u64) {
            dict.set(&name.to_variant(), &make_stream(&pcm, false, false).to_variant());
        }
        dict
    }

    /// Come `render_sfx_bank` ma ritorna solo i byte PCM (`{nome: PackedByteArray}`).
    #[func]
    fn render_sfx_bank_pcm(&self, seed: i64) -> VarDictionary {
        let mut dict = VarDictionary::new();
        for (name, pcm) in render_bank_pcm(seed as u64) {
            dict.set(&name.to_variant(), &PackedByteArray::from(pcm.as_slice()).to_variant());
        }
        dict
    }

    /// PCM 16 bit stereo della musica ambientale (sincrono, ~0.8 s per 64 s di musica).
    #[func]
    fn render_music_pcm(&self, seed: i64, loop_secs: f64) -> PackedByteArray {
        let m = synth::render_ambient(seed as u64, loop_secs as f32);
        PackedByteArray::from(wav::pcm16_stereo(&m.l, &m.r).as_slice())
    }

    /// Trasforma PCM 16 bit (mono o stereo) in un AudioStreamWAV, opzionalmente in loop.
    #[func]
    fn pcm_to_stream(&self, pcm: PackedByteArray, stereo: bool, looped: bool) -> Option<Gd<AudioStreamWav>> {
        if pcm.is_empty() {
            return None;
        }
        Some(make_stream(pcm.as_slice(), stereo, looped))
    }

    /// Avvia in background (thread di Rust) il rendering di tutti gli effetti e della musica.
    /// Non blocca: controlla `is_render_done()` ogni frame. Ignorato se un rendering e' gia' in corso.
    #[func]
    fn start_render(&mut self, seed: i64, music_secs: f64) {
        if self.job.is_some() {
            return;
        }
        let (seed, secs) = (seed as u64, music_secs as f32);
        self.job = Some(std::thread::spawn(move || {
            let t0 = std::time::Instant::now();
            let sfx = render_bank_pcm(seed);
            let m = synth::render_ambient(seed, secs);
            Rendered { sfx, music: wav::pcm16_stereo(&m.l, &m.r), ms: t0.elapsed().as_millis() as i64 }
        }));
    }

    /// True quando il rendering avviato con `start_render` e' finito.
    #[func]
    fn is_render_done(&self) -> bool {
        self.job.as_ref().is_some_and(|j| j.is_finished())
    }

    /// Ritira il risultato: `{sfx: {nome: PackedByteArray}, music: PackedByteArray, ms: int}`.
    /// Dizionario vuoto se non e' pronto (o gia' ritirato).
    #[func]
    fn take_render(&mut self) -> VarDictionary {
        let mut out = VarDictionary::new();
        if !self.is_render_done() {
            return out;
        }
        let Some(job) = self.job.take() else { return out };
        let Ok(r) = job.join() else {
            godot_error!("CartoAudio: il thread di rendering e' andato in panic");
            return out;
        };
        let mut sfx = VarDictionary::new();
        for (name, pcm) in &r.sfx {
            sfx.set(&name.to_variant(), &PackedByteArray::from(pcm.as_slice()).to_variant());
        }
        out.set(&"sfx".to_variant(), &sfx.to_variant());
        out.set(&"music".to_variant(), &PackedByteArray::from(r.music.as_slice()).to_variant());
        out.set(&"ms".to_variant(), &r.ms.to_variant());
        out
    }

    /// Musica pronta, in modo sincrono (blocca ~0.8 s: in gioco usa start_render).
    #[func]
    fn render_music(&self, seed: i64, loop_secs: f64) -> Option<Gd<AudioStreamWav>> {
        let m = synth::render_ambient(seed as u64, loop_secs as f32);
        Some(make_stream(&wav::pcm16_stereo(&m.l, &m.r), true, true))
    }
}

/// Rende tutti gli effetti in parallelo (fino a 4 thread). Risultato indipendente dal numero di thread.
fn render_bank_pcm(seed: u64) -> Vec<(&'static str, Vec<u8>)> {
    let names = synth::SFX_NAMES;
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2).clamp(1, 4);
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|w| {
                s.spawn(move || {
                    names
                        .iter()
                        .enumerate()
                        .filter(|(i, _)| i % workers == w)
                        .filter_map(|(_, n)| synth::render_sfx(n, seed).map(|b| (*n, wav::pcm16_mono(&b))))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles.into_iter().flat_map(|h| h.join().expect("thread audio")).collect()
    })
}

fn make_stream(pcm: &[u8], stereo: bool, looped: bool) -> Gd<AudioStreamWav> {
    let bytes_per_frame = if stereo { 4 } else { 2 };
    let frames = (pcm.len() / bytes_per_frame) as i32;
    let mut s = AudioStreamWav::new_gd();
    s.set_format(Format::FORMAT_16_BITS);
    s.set_mix_rate(SAMPLE_RATE as i32);
    s.set_stereo(stereo);
    s.set_data(&PackedByteArray::from(pcm));
    if looped {
        s.set_loop_mode(LoopMode::FORWARD);
        s.set_loop_begin(0);
        s.set_loop_end(frames);
    }
    s
}
