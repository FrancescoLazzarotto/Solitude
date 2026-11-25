# Stato del lavoro

Questo file e' la memoria del progetto: cosa esiste, cosa e' verificato, quali numeri abbiamo, cosa manca.

## Hardware di riferimento (e vincoli)
AMD Ryzen 5 3500U (4C/8T), Radeon Vega 8 (integrata), 5.9 GB RAM, ~10 GB di disco libero.
- Un `rustc` e' gia' crashato per memoria esaurita compilando `godot-core` con altro in esecuzione: build con `jobs = 2` e Godot chiuso.
- La cartella di build Cargo sta fuori da OneDrive (`%LOCALAPPDATA%\cartografo-build\target`, impostata dagli script).

## Baseline prestazioni (M0, 1280x720, vsync OFF, mediana di 5 giri)
| Metrica | Valore |
|---|---|
| FPS medi | 167 |
| 1% low | 73.5 fps |
| Draw call | 99 |
| Frame peggiore | ~470 ms (si ripete in ogni giro: probabile compilazione shader al primo uso di un effetto - DA INDAGARE) |

Rumore tra giri alto (116-176 fps): sempre confrontare mediane (`tools/bench.ps1`).

## Milestone
- [x] **Prototipo giocabile**: robot (movimento, rotolo con i-frames, spada, stamina), nemico con attacco telegrafato, santuario/checkpoint, due forzieri, lanterna + ponte nascosto, leva + cancello-scorciatoia, caduta nel vuoto, taccuino (pausa del gioco).
- [x] **M0 infrastruttura**: test headless in `tests/` (salvataggi isolati in `user://test`), benchmark, script di build/test.
- [ ] **M1 audio procedurale (Rust)**: sintesi in `carto_core` completa e testata (26 effetti + musica ambientale a loop senza giunture, deterministici). *Mancano*: involucro `carto_gd` (AudioStreamWAV), player audio in GDScript, aggancio agli eventi di gioco, verifica in-game.
- [ ] **M2 livello come dati + compilatore Rust**: unire la geometria statica per materiale (meno draw call), validatore di raggiungibilita' con oggetti.
- [ ] **M3 feeling**: particelle d'impatto, screen shake, pathfinding nemici (NavigationServer3D), fiaschetta di cura, altri due tipi di nemico.
- [ ] **M4 mondo**: piu' zone, segreti, pagine di lore nel taccuino, boss.

## Note tecniche
- gdext (`godot` crate) `=0.5.6` carica correttamente in Godot 4.7.2 (API 4.6, runtime 4.7.2).
- File `.gdextension` e config: scrivere SENZA BOM (PowerShell 5.1 `Set-Content -Encoding utf8` aggiunge il BOM e Godot lo rifiuta).
- C++ (godot-cpp) non e' usato: il motore e' gia' C++ e Rust copre i casi d'uso; evita una seconda toolchain su un disco ridotto.

## Non ancora verificato
Gamepad, controlli touch/mobile, console, prestazioni su altro hardware.
