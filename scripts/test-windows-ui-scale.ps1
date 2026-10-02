[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\validation\glh2.exe')
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$runDir = Split-Path -Parent $exe
$config = Join-Path $runDir 'data1\config.cfg'
if (!(Test-Path -LiteralPath (Join-Path $runDir 'data1\pak0.pak'))) {
    throw 'Use an isolated copy of the game data beside the executable. This test changes its video settings.'
}
$cfgName = '__ui_test_' + [Guid]::NewGuid().ToString('N') + '.cfg'
$cfgPath = Join-Path $runDir "data1\$cfgName"
function Run-Test([string[]]$gameArgs, [string[]]$commands, [int]$requested, [string]$name) {
    Set-Content -LiteralPath $cfgPath -Value $commands -Encoding ascii
    $p = Start-Process -FilePath $exe -WorkingDirectory $runDir -WindowStyle Hidden -PassThru `
        -ArgumentList ($gameArgs + @('-profile-startup', '+exec', $cfgName))
    try {
        if (!$p.WaitForExit(30000)) { throw "UI scaling test timed out: $name" }
        if ($p.ExitCode -ne 0) { throw "Game exited with status $($p.ExitCode): $name" }
    } finally {
        if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
        $p.Dispose()
    }
    $log = Get-Content -LiteralPath (Join-Path $runDir 'debug_h2.log') -Raw
    Copy-Item -LiteralPath (Join-Path $runDir 'debug_h2.log') -Destination (Join-Path $runDir "ui-$name.log")
    if ((Get-Content -LiteralPath $config -Raw) -notmatch ('(?m)^vid_config_consize "' + $requested + '"\r?$')) {
        throw "UI width $requested was overwritten during $name."
    }
    $states = @([regex]::Matches($log, 'UI layout: (\d+)x(\d+) in (\d+)x(\d+), requested width (\d+)'))
    $expectedStates = 1 + @($commands | Where-Object { $_ -eq 'vid_togglefullscreen' }).Count
    if ($states.Count -ne $expectedStates) { throw "Missing UI layout diagnostics: $name" }
    foreach ($state in $states) {
        $width = [int]$state.Groups[3].Value
        $height = [int]$state.Groups[4].Value
        $actual = [int]$state.Groups[1].Value
        $logicalHeight = [int]$state.Groups[2].Value
        if ([int]$state.Groups[5].Value -ne $requested) { throw "Requested scale changed: $name" }
        if ($actual -gt $width -or $logicalHeight -gt $height -or $logicalHeight -lt 200) {
            throw "The scaled UI does not fit the window: $name"
        }
        # A preference that fits must be used, rather than silently becoming unscaled.
        if ($requested -le $width -and [math]::Floor($requested * $height / $width) -ge 200 -and $actual -ne $requested) {
            throw "The requested UI width was not applied: $name"
        }
    }
    "PASS: $name (requested UI width $requested)"
}
try {
    foreach ($requested in @(1280, 640, 320)) {
        Run-Test @('-borderless', '-conwidth', "$requested") `
            @('wait', 'vid_togglefullscreen', 'wait', 'vid_togglefullscreen', 'wait', 'quit') `
            $requested "roundtrip-$requested"
        Run-Test @('-borderless', '-conwidth', "$requested") `
            @('wait', 'vid_togglefullscreen', 'wait', 'quit') `
            $requested "save-windowed-$requested"
        # No -conwidth override: read the preference saved while windowed.
        Run-Test @('-window') @('wait', 'vid_togglefullscreen', 'wait', 'quit') `
            $requested "restore-$requested"
    }
} finally {
    if (Test-Path -LiteralPath $cfgPath) { Remove-Item -LiteralPath $cfgPath }
}
