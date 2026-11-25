//! Generatore pseudo-casuale deterministico (PCG32). Stesso seme => stessi suoni, sempre.

#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
    inc: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Self {
        let mut r = Rng { state: 0, inc: (seed << 1) | 1 };
        r.next_u32();
        r.state = r.state.wrapping_add(seed ^ 0x9E37_79B9_7F4A_7C15);
        r.next_u32();
        r
    }

    #[inline]
    pub fn next_u32(&mut self) -> u32 {
        let old = self.state;
        self.state = old.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    /// Numero in [0, 1).
    #[inline]
    pub fn f32(&mut self) -> f32 {
        (self.next_u32() >> 8) as f32 * (1.0 / 16_777_216.0)
    }

    /// Numero in [-1, 1).
    #[inline]
    pub fn signed(&mut self) -> f32 {
        self.f32() * 2.0 - 1.0
    }

    #[inline]
    pub fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f32()
    }

    /// Intero in [0, n).
    #[inline]
    pub fn below(&mut self, n: u32) -> u32 {
        ((self.next_u32() as u64 * n as u64) >> 32) as u32
    }

    #[inline]
    pub fn chance(&mut self, p: f32) -> bool {
        self.f32() < p
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic() {
        let mut a = Rng::new(42);
        let mut b = Rng::new(42);
        for _ in 0..100 {
            assert_eq!(a.next_u32(), b.next_u32());
        }
    }

    #[test]
    fn different_seeds_differ() {
        let mut a = Rng::new(1);
        let mut b = Rng::new(2);
        let same = (0..64).filter(|_| a.next_u32() == b.next_u32()).count();
        assert!(same < 4);
    }

    #[test]
    fn range_and_mean() {
        let mut r = Rng::new(7);
        let n = 100_000;
        let mut sum = 0.0f64;
        for _ in 0..n {
            let v = r.f32();
            assert!((0.0..1.0).contains(&v));
            sum += v as f64;
        }
        let mean = sum / n as f64;
        assert!((mean - 0.5).abs() < 0.01, "media = {mean}");
        for _ in 0..1000 {
            assert!(r.below(10) < 10);
        }
    }
}
