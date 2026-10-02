[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\win64\glh2.exe'),
    [switch]$LegacyDisplayProbe,
    [switch]$Fullscreen,
    [switch]$LoadMap,
    [ValidateRange(5, 55)][int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$runDir = Split-Path -Parent $exe
if (!(Test-Path -LiteralPath (Join-Path $runDir 'data1\pak0.pak'))) {
    throw 'Copy your game data1 directory alongside the test executable first. Use a separate copy to keep test configuration and saves isolated.'
}
$gameArgs = @('-profile-startup')
if ($Fullscreen) { $gameArgs += @('-fullscreen', '-current') }
else { $gameArgs += @('-window', '-width', '960', '-height', '600') }
if ($LegacyDisplayProbe) { $gameArgs += '-legacy-display-probe' }
if ($LoadMap) { $gameArgs += @('+map', 'demo1') }
$gameArgs += @('+wait', '+wait', '+quit')
$timer = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $exe -WorkingDirectory $runDir -ArgumentList $gameArgs -WindowStyle Hidden -PassThru
try {
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
        throw "Startup timed out after $TimeoutSeconds seconds. Inspect $runDir\debug_h2.log for the last stage entered."
    }
    if ($process.ExitCode -ne 0) { throw "Game exited with code $($process.ExitCode). Inspect $runDir\debug_h2.log." }
    $log = Get-Content -LiteralPath (Join-Path $runDir 'debug_h2.log')
    if (!($log -match 'Startup: startup scripts took')) {
        throw 'Startup did not reach the final profiling marker.'
    }
    if ($LoadMap -and !($log -match 'entered the game')) {
        throw 'The map test did not reach a connected player. Inspect debug_h2.log.'
    }
    $log | Select-String 'Startup:|GL_VENDOR:|GL_RENDERER:|Loading OpenGL'
    Write-Host ('Process lifetime: {0:F3} seconds' -f $timer.Elapsed.TotalSeconds)
} finally {
    # Only terminate the process this test started, never another game session.
    if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
