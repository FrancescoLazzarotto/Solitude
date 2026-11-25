# Percorsi e utilita' comuni (ASCII only: PowerShell 5.1 legge male l'UTF-8 senza BOM).
$ErrorActionPreference = 'Stop'

$script:Root   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:Native = Join-Path $script:Root 'native'
$script:Bin    = Join-Path $script:Root 'bin'

function Get-GodotExe([switch]$Console) {
    $pkg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $name = if ($Console) { 'Godot_v*_win64_console.exe' } else { 'Godot_v*_win64.exe' }
    $f = Get-ChildItem $pkg -Recurse -Filter $name -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like '*GodotEngine*' } | Select-Object -First 1
    if (-not $f) { throw "Godot non trovato. Installa: winget install GodotEngine.GodotEngine" }
    return $f.FullName
}

# La cartella di build sta FUORI da OneDrive (vedi native/.cargo/config.toml).
$script:TargetDir = Join-Path $env:LOCALAPPDATA 'cartografo-build\target'
