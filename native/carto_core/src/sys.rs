//! Piccole utilita' di sistema.

/// Abbassa la priorita' del thread CORRENTE (solo Windows; altrove non fa nulla).
/// I calcoli in background (audio, livelli) non devono mai togliere CPU al thread principale e al rendering.
#[cfg(windows)]
pub fn background_priority() {
    extern "system" {
        fn GetCurrentThread() -> isize;
        fn SetThreadPriority(handle: isize, priority: i32) -> i32;
    }
    const THREAD_PRIORITY_BELOW_NORMAL: i32 = -1;
    // SAFETY: GetCurrentThread restituisce uno pseudo-handle sempre valido per il thread chiamante.
    unsafe {
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
    }
}

#[cfg(not(windows))]
pub fn background_priority() {}

/// Priorita' corrente del thread (solo Windows, per i test). 0 = normale.
#[cfg(windows)]
pub fn current_priority() -> i32 {
    extern "system" {
        fn GetCurrentThread() -> isize;
        fn GetThreadPriority(handle: isize) -> i32;
    }
    // SAFETY: vedi sopra.
    unsafe { GetThreadPriority(GetCurrentThread()) }
}

#[cfg(not(windows))]
pub fn current_priority() -> i32 {
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn background_priority_lowers_only_the_calling_thread() {
        let main_before = current_priority();
        let worker = std::thread::spawn(|| {
            let before = current_priority();
            background_priority();
            (before, current_priority())
        })
        .join()
        .unwrap();
        assert_eq!(current_priority(), main_before, "il thread chiamante originale non deve cambiare");
        if cfg!(windows) {
            assert_eq!(worker.0, 0);
            assert_eq!(worker.1, -1, "priorita' BELOW_NORMAL attesa");
        }
    }
}
