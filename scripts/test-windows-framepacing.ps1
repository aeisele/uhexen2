[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\validation\glh2.exe'),
    [ValidateRange(72, 720)][int]$Samples = 360
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$runDir = Split-Path -Parent $exe
if (!(Test-Path -LiteralPath (Join-Path $runDir 'data1\pak0.pak'))) {
    throw 'This test requires an isolated copy of the game data beside the executable. It updates that copy''s config.cfg.'
}
$cfgName = '__frame_test_' + [Guid]::NewGuid().ToString('N') + '.cfg'
$cfgPath = Join-Path $runDir "data1\$cfgName"
$culture = [Globalization.CultureInfo]::InvariantCulture
try {
    foreach ($mode in @(0, 1)) {
        $commands = @("sys_framepacing $mode", 'map demo1') +
            (@('wait') * 120) + @('echo FRAME_SAMPLE_BEGIN') +
            (@('wait') * $Samples) + @('echo FRAME_SAMPLE_END', 'disconnect', 'quit')
        Set-Content -LiteralPath $cfgPath -Value $commands -Encoding ascii
        $p = Start-Process -FilePath $exe -WorkingDirectory $runDir -WindowStyle Hidden -PassThru `
            -ArgumentList @('-window', '-width', '960', '-height', '600', '-profile-frames', '+exec', $cfgName)
        try {
            if (!$p.WaitForExit(45000)) { throw "Frame pacing test $mode timed out." }
            if ($p.ExitCode -ne 0) { throw "Game exited with status $($p.ExitCode)." }
        } finally {
            if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
            $p.Dispose()
        }
        $log = Get-Content -LiteralPath (Join-Path $runDir 'debug_h2.log') -Raw
        Copy-Item -LiteralPath (Join-Path $runDir 'debug_h2.log') -Destination (Join-Path $runDir "frame-pacing-$mode.log")
        $block = [regex]::Match($log, '(?s)FRAME_SAMPLE_BEGIN[ \t]*\r?\n(.*?)FRAME_SAMPLE_END')
        if (!$block.Success) { throw 'Frame sampling did not complete.' }
        $frames = @([regex]::Matches($block.Groups[1].Value, '(?m)^Frame: \d+ ([\d.]+) ([\d.]+)') |
            ForEach-Object { [double]::Parse($_.Groups[1].Value, $culture) })
        if ($frames.Count -ne $Samples) { throw "Expected $Samples frames, found $($frames.Count)." }
        $intervals = @(for ($i = 1; $i -lt $frames.Count; $i++) { ($frames[$i] - $frames[$i - 1]) * 1000 })
        $sorted = @($intervals | Sort-Object)
        $average = ($intervals | Measure-Object -Average).Average
        [pscustomobject]@{
            Pacing = $(if ($mode) { 'Precise' } else { 'Legacy' })
            Frames = $frames.Count
            MeanMs = [math]::Round($average, 3)
            MedianMs = [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)], 3)
            P95Ms = [math]::Round($sorted[[int][math]::Floor(($sorted.Count - 1) * 0.95)], 3)
            MaxMs = [math]::Round($sorted[-1], 3)
            FPS = [math]::Round(1000 / $average, 2)
        }
    }
} finally {
    if (Test-Path -LiteralPath $cfgPath) { Remove-Item -LiteralPath $cfgPath }
}
