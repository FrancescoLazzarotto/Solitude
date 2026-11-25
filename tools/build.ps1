# Compila l'estensione nativa (Rust) e copia la DLL in bin/.
#   .\tools\build.ps1            -> profilo "fast" (iterazione veloce)
#   .\tools\build.ps1 -Profile release  -> LTO, per benchmark e distribuzione
param([ValidateSet('fast', 'release')][string]$Profile = 'fast')
. "$PSScriptRoot\common.ps1"

Push-Location $script:Native
try {
    $env:CARGO_TARGET_DIR = $script:TargetDir
    cargo build --profile $Profile -p carto_gd
    if ($LASTEXITCODE -ne 0) { throw "cargo build fallito" }
} finally { Pop-Location }

$srcDir = if ($Profile -eq 'release') { 'release' } else { $Profile }
$dll = Join-Path $script:TargetDir "$srcDir\carto_gd.dll"
if (-not (Test-Path $dll)) { throw "DLL non trovata: $dll" }
New-Item -ItemType Directory -Force $script:Bin | Out-Null
$dest = Join-Path $script:Bin 'carto.dll'
try {
    Copy-Item $dll $dest -Force
} catch {
    throw "Impossibile sovrascrivere bin\carto.dll: un Godot aperto la sta usando. Chiudi il gioco/editor e riprova."
}
Write-Host ("OK: {0} ({1:N0} KB, profilo {2})" -f $dest, ((Get-Item $dest).Length / 1KB), $Profile)
