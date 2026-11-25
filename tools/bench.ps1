# Benchmark: N giri (default 3) di tests/bench.gd, riporta la MEDIANA (il PC e' rumoroso).
param([int]$Runs = 3)
. "$PSScriptRoot\common.ps1"

$godot = Get-GodotExe -Console
$avg = @(); $low = @(); $dc = @(); $worst = @()
for ($i = 1; $i -le $Runs; $i++) {
    $out = & $godot --path $script:Root --resolution 1280x720 --script (Join-Path $script:Root 'tests\bench.gd') -- --carto-test 2>&1 | ForEach-Object { "$_" }
    $l = $out | Where-Object { $_ -match '^BENCH frames' } | Select-Object -First 1
    $d = $out | Where-Object { $_ -match '^BENCH draw_calls' } | Select-Object -First 1
    if (-not $l) { Write-Host "giro $i fallito:"; $out | Select-Object -Last 8; continue }
    $avg += [double]([regex]::Match($l, 'avg_fps=([\d.]+)').Groups[1].Value)
    $low += [double]([regex]::Match($l, 'low1pct_fps=([\d.]+)').Groups[1].Value)
    $worst += [double]([regex]::Match($l, 'worst_ms=([\d.]+)').Groups[1].Value)
    $dc += [double]([regex]::Match($d, 'avg=([\d.]+)').Groups[1].Value)
    Write-Host ("giro {0}: {1}" -f $i, $l)
}
function Median($a) { $s = $a | Sort-Object; if ($s.Count -eq 0) { return 0 }; $s[[int][math]::Floor(($s.Count - 1) / 2)] }
Write-Host ("MEDIANA su {0} giri: avg_fps={1}  low1pct_fps={2}  worst_ms={3}  draw_calls={4}" -f $avg.Count, (Median $avg), (Median $low), (Median $worst), (Median $dc)) -ForegroundColor Green
