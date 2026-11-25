# Il Cartografo

Gioco d'azione e avventura in **3D** (camera prospettica ad angolo fisso) con un piccolo robot esploratore:
combattimento leale con rotolo e stamina, mondo connesso con scorciatoie e segreti, santuari-checkpoint,
oggetti che aprono nuove strade e un taccuino per annotare indizi. Atmosfera rilassata e misteriosa.

Motore: **Godot 4.7** (renderer Mobile). Logica pesante in **Rust** (GDExtension).

## Requisiti
- Godot 4.7.x (`winget install GodotEngine.GodotEngine`)
- Rust stable + Visual Studio Build Tools (Windows)
- PowerShell 5.1+

## Comandi
```powershell
.\tools\build.ps1                 # compila l'estensione nativa (profilo "fast") e copia la DLL in bin/
.\tools\build.ps1 -Profile release  # con LTO
.\tools\test.ps1                  # cargo test + suite headless di Godot + controllo salvataggi
.\tools\bench.ps1                 # benchmark (mediana su 3 giri)
godot --path .                    # avvia il gioco
```
La cartella di build di Cargo sta fuori dal progetto (`%LOCALAPPDATA%\cartografo-build`): niente migliaia di file
da sincronizzare su OneDrive. Chiudi Godot prima di ricompilare: Windows blocca la DLL caricata.

## Struttura
| Cartella | Contenuto |
|---|---|
| `scripts/` | GDScript del gioco (robot, nemici, livello, HUD, taccuino) |
| `native/carto_core` | Logica nativa pura Rust (audio procedurale, ...), testabile con `cargo test` |
| `native/carto_gd` | Involucro GDExtension che espone `carto_core` a Godot |
| `tests/` | Suite headless (`*_test.gd`) e benchmark (`bench.gd`) |
| `tools/` | Script di build, test e benchmark |
| `docs/PROGRESS.md` | Stato del lavoro, numeri di performance, prossimi passi |

## Controlli
WASD / frecce: muovi - J o click: attacca - Spazio/Shift: rotola - E: interagisci - Tab: taccuino. Gamepad mappato (non ancora provato).
