# Esegue TUTTI i test: cargo test (nativo) -> build -> suite headless di Godot.
# Verifica anche che i test non abbiano toccato i salvataggi veri (user://notebook.json).
param([switch]$SkipNative)
. "$PSScriptRoot\common.ps1"
# I comandi nativi (cargo, godot) scrivono su stderr anche quando va tutto bene: non trattarlo come errore.
$ErrorActionPreference = 'Continue'

$failed = $false

if (-not $SkipNative -and (Test-Path (Join-Path $script:Native 'Cargo.toml'))) {
    Write-Host "=== cargo test (carto_core) ===" -ForegroundColor Cyan
    Push-Location $script:Native
    try {
        $env:CARGO_TARGET_DIR = $script:TargetDir
        cargo test --profile fast -p carto_core 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host "cargo test: FALLITO" -ForegroundColor Red }
    } finally { Pop-Location }
    Write-Host "=== build estensione ===" -ForegroundColor Cyan
    & "$PSScriptRoot\build.ps1" -Profile fast
}

$godot = Get-GodotExe -Console
$realSave = Join-Path $env:APPDATA 'Godot\app_userdata\Il Cartografo\notebook.json'
$hashBefore = if (Test-Path $realSave) { (Get-FileHash $realSave).Hash } else { 'ASSENTE' }

Write-Host "=== import progetto ===" -ForegroundColor Cyan
& $godot --headless --path $script:Root --import 2>&1 | Out-Null

foreach ($t in (Get-ChildItem (Join-Path $script:Root 'tests') -Filter '*_test.gd')) {
    Write-Host "=== $($t.Name) ===" -ForegroundColor Cyan
    $out = & $godot --headless --path $script:Root --script $t.FullName -- --carto-test 2>&1 | ForEach-Object { "$_" }
    $out | Where-Object { $_ -match '^(PASS|FAIL|===|FALLITI|ERROR|SCRIPT)' -or $_ -match 'ERROR|SCRIPT ERROR' }
    if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host "$($t.Name): exit code $LASTEXITCODE" -ForegroundColor Red }
    if ($out -match '^FAIL') { $failed = $true }
}

$hashAfter = if (Test-Path $realSave) { (Get-FileHash $realSave).Hash } else { 'ASSENTE' }
if ($hashBefore -ne $hashAfter) { $failed = $true; Write-Host "I TEST HANNO TOCCATO IL SALVATAGGIO REALE!" -ForegroundColor Red }
else { Write-Host "Salvataggio reale intatto." -ForegroundColor Green }

$testDir = Join-Path $env:APPDATA 'Godot\app_userdata\Il Cartografo\test'
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force -Confirm:$false }

if ($failed) { Write-Host "RISULTATO: FALLITO" -ForegroundColor Red; exit 1 }
Write-Host "RISULTATO: TUTTO OK" -ForegroundColor Green
