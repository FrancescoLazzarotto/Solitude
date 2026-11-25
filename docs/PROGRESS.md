# Stato del lavoro

Questo file e' la memoria del progetto: cosa esiste, cosa e' verificato, quali numeri abbiamo, cosa manca.

## Hardware di riferimento (e vincoli)
AMD Ryzen 5 3500U (4C/8T), Radeon Vega 8 (integrata), 5.9 GB RAM, ~9 GB di disco libero.
- Un `rustc` e' gia' crashato per memoria esaurita compilando `godot-core` con altro in esecuzione: build con `jobs = 2` e Godot chiuso.
- Prima compilazione completa (dipendenze di gdext): ~6 minuti. Poi `tools/build.ps1` impiega ~5 secondi.
- La cartella di build Cargo sta fuori da OneDrive (`%LOCALAPPDATA%\cartografo-build\target`, impostata dagli script).

## Prestazioni (1280x720, vsync OFF, percorso scriptato di 3 giri, mediana di 5 giri)
**Baseline v2** (audio attivo, benchmark corretto):

| Metrica | Valore |
|---|---|
| FPS medi | 183 |
| 1% low | 90 fps |
| Frame peggiore | 15 ms |
| Draw call | 93 |
| Fisica | ~1.1 ms/tick |
| Memoria statica | 61 MB |

Il portatile e' termicamente rumoroso (146-197 fps tra giri): **confrontare sempre mediane, e per A/B alternare le varianti** (vedi interruttori `--carto-no-audio`, `--carto-audio-norender`, `--carto-audio-nomusic`).

### Errori di misura gia' trovati (lezioni)
1. *Il "blocco da 500 ms" del baseline v1 non esisteva.* Il benchmark metteva `max_hp = 9999`: al primo attacco l'HUD costruiva 9999 `ColorRect` (10.000 nodi), che restavano a rallentare tutto il test. Il benchmark ora rende il robot invulnerabile senza toccare la vita massima. I numeri v1 (167 fps, 1% low 73) sono **da scartare**.
2. Il rendering audio all'avvio (~1.4 s di CPU in thread) cadeva dentro la finestra di misura e sembrava costare il 47% degli FPS. Il benchmark ora aspetta la fine del caricamento. A regime audio on/off e' indistinguibile.
3. Per scoprirli: loggare i contatori del motore (`Performance`) sul frame del problema (nodi, oggetti, draw call).

## Milestone
- [x] **Prototipo giocabile**: robot (movimento, rotolo con i-frames, spada, stamina), nemico con attacco telegrafato, santuario/checkpoint, due forzieri, lanterna + ponte nascosto, leva + cancello-scorciatoia, caduta nel vuoto, taccuino (pausa del gioco).
- [x] **M0 infrastruttura**: test headless in `tests/` (salvataggi isolati in `user://test`), benchmark, script di build/test.
- [x] **M1 audio procedurale (Rust)**: 26 effetti + musica ambientale a loop senza giunture (Re dorico, 64 s), tutto sintetizzato da zero e deterministico. Rendering in un thread DENTRO Rust (gdext vieta chiamate da Thread di Godot: il processo si interrompe), 3D posizionale con ascoltatore che segue il robot, bus SFX/Music con limitatore sul master. Tutti gli eventi di gioco sono agganciati e testati.
  - Tempi (release): 26 effetti in ~120-240 ms, musica da 64 s in ~780 ms (accordi in parallelo), in background.
  - Verifica: 19 test unitari (`cargo test`) + 36 controlli d'integrazione + analisi con spettrogrammi. **Non ascoltato da un orecchio umano**: bilanciamento e gusto vanno giudicati giocando.
- [ ] **M2 livello come dati + validatore Rust** (IN CORSO). Decisione di architettura (confine delle dipendenze):
  - i dati del livello stanno in `levels/slice.json` (un solo file, letto sia da GDScript sia da Rust);
  - il **validatore di raggiungibilita'** e' Rust puro in `native/carto_core/src/level.rs` (modello a griglia 2.5D da 0.25 m, passo max 0.45 m, cadute permesse, chiavi `lantern`/`lever`), testato da `cargo test`, NESSUNA dipendenza dalla DLL a runtime;
  - la **geometria** si costruisce in GDScript al caricamento (`scripts/level_builder.gd`): cosi' una DLL mancante o bloccata non impedisce di avviare il gioco (coerente col fallback muto dell'audio);
  - **non si uniscono mesh finche' non serve**: 93 draw call a 183 fps non lo giustificano; se si fara', con benchmark di stress (fetta istanziata 4 volte, prima/dopo).
  - Porting a comportamento invariato: ogni check di `tests/game_test.gd` (anche le altezze dei raycast) deve restare verde.
  - **Prossimi passi esatti**: (1) `levels/slice.json` con tutta la geometria e i prop; (2) `level.rs` + test `cargo test -p carto_core level::`; (3) `scripts/level_builder.gd` e `main.gd` che lo usa; (4) `tools/test.ps1` verde; (5) test di raggiungibilita' che sostituiscono i controlli manuali su recinzione/cancello/forziere 2.
- [ ] **M3 feeling**: particelle d'impatto, screen shake, pathfinding nemici (NavigationServer3D), fiaschetta di cura, altri due tipi di nemico, dissolvenza d'avvio.
- [ ] **M4 mondo**: piu' zone, segreti, pagine di lore nel taccuino, boss.

## Note tecniche
- gdext (`godot` crate) `=0.5.6` carica correttamente in Godot 4.7.2 (API 4.6, runtime 4.7.2).
- **Da un `Thread` di Godot non si puo' chiamare l'estensione** (panic "different thread than main thread" e abort). Il lavoro in background va fatto con `std::thread` dentro Rust, senza toccare Godot, e ritirato dal thread principale (`start_render` / `is_render_done` / `take_render`).
- File `.gdextension` e config: scrivere SENZA BOM (PowerShell 5.1 `Set-Content -Encoding utf8` aggiunge il BOM e Godot lo rifiuta).
- PowerShell 5.1: con `$ErrorActionPreference='Stop'`, qualunque riga su stderr di un comando nativo (anche "Finished") diventa errore. Negli script che lanciano cargo/godot usare `Continue`.
- C++ (godot-cpp) non e' usato: il motore e' gia' C++ e Rust copre i casi d'uso; evita una seconda toolchain su un disco ridotto.
- `bin/carto.dll` non e' versionata: si rigenera con `tools/build.ps1`.

## Non ancora verificato
Gamepad, controlli touch/mobile, console, prestazioni su altro hardware, qualita' percepita dell'audio.
