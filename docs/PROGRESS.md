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
4. *Crash all'uscita (0xC0000005)* se il gioco veniva chiuso mentre il thread audio in Rust lavorava ancora: Godot scaricava la DLL con un thread in esecuzione al suo interno. Scoperto da `level_test` (breve, esce prima della fine del rendering). Ora il rendering e' annullabile (`AtomicBool` controllato nei cicli) e `Drop` di `CartoAudio` ferma E attende il thread. Test di regressione: "shutdown stress" in `tools/test.ps1` (uscita a 50/200/500/1200 ms, exit code 0).
5. *Il panning audio era ruotato di 45 gradi* (microfono con base identita', camera con yaw 45): i test "play() e' stato chiamato" non potevano accorgersene. Ora `Audio.set_listener(pos, yaw)` + test geometrico sui versori schermo-destra/schermo-alto.

## Milestone
- [x] **Prototipo giocabile**: robot (movimento, rotolo con i-frames, spada, stamina), nemico con attacco telegrafato, santuario/checkpoint, due forzieri, lanterna + ponte nascosto, leva + cancello-scorciatoia, caduta nel vuoto, taccuino (pausa del gioco).
- [x] **M0 infrastruttura**: test headless in `tests/` (salvataggi isolati in `user://test`), benchmark, script di build/test.
- [x] **M1 audio procedurale (Rust)**: 26 effetti + musica ambientale a loop senza giunture (Re dorico, 64 s), tutto sintetizzato da zero e deterministico. Rendering in un thread DENTRO Rust (gdext vieta chiamate da Thread di Godot: il processo si interrompe), 3D posizionale con ascoltatore che segue il robot, bus SFX/Music con limitatore sul master. Tutti gli eventi di gioco sono agganciati e testati.
  - Tempi (release): 26 effetti in ~120-240 ms, musica da 64 s in ~780 ms (accordi in parallelo), in background.
  - Verifica: 19 test unitari (`cargo test`) + 36 controlli d'integrazione + analisi con spettrogrammi. **Non ascoltato da un orecchio umano**: bilanciamento e gusto vanno giudicati giocando.
- [x] **M2 livello come dati + validatore Rust**. Confine delle dipendenze deciso cosi':
  - i dati del livello stanno in `levels/slice.json` (geometria, prop, nemici, chiavi); `scripts/level_data.gd` li legge e `main.gd` costruisce il mondo da li';
  - il **validatore di raggiungibilita'** e' Rust puro (`native/carto_core/src/level.rs`): mappa di altezze 2.5D a celle da 25 cm, salita max 0.45 m, cadute libere, vuoti mai, progressione a chiavi (`lantern`, `lever`) fino al punto fisso. Testato da `cargo test` (33 test) e anche esposto a Godot (`CartoLevel`: `validate`, `analyze`, `heights`);
  - la geometria si costruisce in GDScript al caricamento: una DLL mancante o bloccata non impedisce di avviare il gioco;
  - **porting a comportamento invariato**: tutti i 46 controlli di `game_test` passano con coordinate identiche al decimale;
  - **il modello coincide con la fisica**: `tests/level_test.gd` confronta le quote del modello con i raycast del motore su 1400 punti (stato iniziale e dopo lanterna+leva): 0 differenze;
  - dimostrato dal validatore: cuore e leva irraggiungibili senza lanterna; corridoio sigillato dal cortile finche' la leva non e' tirata; la scorciatoia riporta al santuario anche senza ponte; nessun oggetto orfano. **Test di mutazione**: senza staccionata vede l'aggiramento, con ponte sempre attivo vede il cuore raggiungibile;
  - **fusione delle mesh NON fatta, di proposito**: 93 draw call a 183 fps non la giustificano. Se servira' (livelli molto piu' grandi), con benchmark di stress prima/dopo.
- [x] **M3 feeling e nemici** (tranne il pathfinding, vedi sotto):
  - **Fx** (autoload): scintille d'impatto con 8 `CPUParticles3D` riusate a rotazione + scuotimento camera (ampiezza = trauma^2, decade in ~1 s);
  - **fiaschetta di cura** (Q / RB): 3 scorte, +2 cuori dopo 0.7 s vulnerabili (si cammina piano), un colpo la interrompe senza consumarla, il santuario la ricarica;
  - **bruto**: 6 PV, lento, carica di 1.0 s, colpo da 2 cuori in raggio 2.4, si stordisce poco; **sentinella**: torretta immobile con linea di tiro, 0.85 s di mira, proiettile schivabile (spostandosi o con le i-frames del rotolo), bloccata dai muri (linea di vista);
  - i nemici hanno un `kind` nei dati del livello (`guardian`/`brute`/`sentinel`), validato da Rust; la sentinella sta sull'altopiano, il bruto sulla terrazza del cuore;
  - dissolvenza dal nero all'avvio; suoni `drink` e `shot` (28 effetti);
  - **pathfinding NON fatto, di proposito**: i nemici vanno dritti e scivolano lungo i muri (`move_and_slide`); si incastrano solo in concavita' profonde, che il livello attuale non ha. Se i livelli futuri ne avranno: `AStarGrid2D` del motore alimentato dalla griglia del validatore Rust.
  - test: `feel_test` (scintille, trauma, fiaschetta in 6 scenari), `enemy_kinds_test` (carica, danno, schivata, sentinella: mira/sparo/schivata/i-frames/muro in mezzo).
- [ ] **M4 mondo**: piu' zone, segreti, pagine di lore nel taccuino, boss.
  - **Prossimi passi esatti**: (1) estendere `levels/slice.json` (o nuovo `levels/world.json`) con una seconda area collegata alla prima da una scorciatoia e un oggetto-chiave nuovo (es. rampino/lanterna 2); (2) estendere `analyze` in `level.rs` con nuove chiavi e aggiungere il test di progressione corrispondente PRIMA di costruire l'area; (3) pagine di lore: oggetti raccoglibili che si aggiungono al taccuino (`notebook.gd`), salvati in `user://`; (4) salvataggio dei progressi (chiavi, forzieri aperti, checkpoint) in `Paths.user_file("save.json")` con test di round-trip; (5) boss (stessa macchina a stati di `enemy.gd`, tipo `boss` con fasi).

## Note tecniche
- gdext (`godot` crate) `=0.5.6` carica correttamente in Godot 4.7.2 (API 4.6, runtime 4.7.2).
- **Da un `Thread` di Godot non si puo' chiamare l'estensione** (panic "different thread than main thread" e abort). Il lavoro in background va fatto con `std::thread` dentro Rust, senza toccare Godot, e ritirato dal thread principale (`start_render` / `is_render_done` / `take_render`).
- File `.gdextension` e config: scrivere SENZA BOM (PowerShell 5.1 `Set-Content -Encoding utf8` aggiunge il BOM e Godot lo rifiuta).
- PowerShell 5.1: con `$ErrorActionPreference='Stop'`, qualunque riga su stderr di un comando nativo (anche "Finished") diventa errore. Negli script che lanciano cargo/godot usare `Continue`.
- C++ (godot-cpp) non e' usato: il motore e' gia' C++ e Rust copre i casi d'uso; evita una seconda toolchain su un disco ridotto.
- `bin/carto.dll` non e' versionata: si rigenera con `tools/build.ps1`.

## Non ancora verificato
Gamepad, controlli touch/mobile, console, prestazioni su altro hardware, qualita' percepita dell'audio, export (ricordare di includere `levels/*.json` nel filtro di esportazione).
