//! Conversione in PCM 16 bit e scrittura WAV (per ascolto/analisi fuori dal gioco).

#[inline]
fn to_i16(v: f32) -> i16 {
    (v.clamp(-1.0, 1.0) * 32767.0).round() as i16
}

/// PCM 16 bit little-endian, mono.
pub fn pcm16_mono(samples: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(samples.len() * 2);
    for &s in samples {
        out.extend_from_slice(&to_i16(s).to_le_bytes());
    }
    out
}

/// PCM 16 bit little-endian, stereo interlacciato (L, R, L, R...).
pub fn pcm16_stereo(l: &[f32], r: &[f32]) -> Vec<u8> {
    let n = l.len().min(r.len());
    let mut out = Vec::with_capacity(n * 4);
    for i in 0..n {
        out.extend_from_slice(&to_i16(l[i]).to_le_bytes());
        out.extend_from_slice(&to_i16(r[i]).to_le_bytes());
    }
    out
}

/// File WAV completo (header RIFF + dati PCM 16 bit).
pub fn wav_file(pcm: &[u8], channels: u16, sample_rate: u32) -> Vec<u8> {
    let byte_rate = sample_rate * channels as u32 * 2;
    let mut out = Vec::with_capacity(44 + pcm.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&channels.to_le_bytes());
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&byte_rate.to_le_bytes());
    out.extend_from_slice(&(channels * 2).to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    out.extend_from_slice(pcm);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pcm_conversion() {
        let b = pcm16_mono(&[0.0, 1.0, -1.0, 2.0]);
        assert_eq!(b.len(), 8);
        assert_eq!(i16::from_le_bytes([b[2], b[3]]), 32767);
        assert_eq!(i16::from_le_bytes([b[4], b[5]]), -32767);
        assert_eq!(i16::from_le_bytes([b[6], b[7]]), 32767, "deve saturare, non andare in overflow");
    }

    #[test]
    fn stereo_interleaves() {
        let b = pcm16_stereo(&[0.5, 0.0], &[-0.5, 0.0]);
        assert_eq!(b.len(), 8);
        assert_eq!(i16::from_le_bytes([b[0], b[1]]), -i16::from_le_bytes([b[2], b[3]]));
    }

    #[test]
    fn wav_header_is_valid() {
        let w = wav_file(&[0u8; 100], 2, 44_100);
        assert_eq!(&w[0..4], b"RIFF");
        assert_eq!(&w[8..12], b"WAVE");
        assert_eq!(w.len(), 144);
        assert_eq!(u32::from_le_bytes([w[4], w[5], w[6], w[7]]), 136);
    }
}
