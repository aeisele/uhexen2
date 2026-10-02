[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\validation\glh2.exe')
)
$ErrorActionPreference = 'Stop'
if (!('WindowProbe' -as [type])) { Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WindowProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr w, int index);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w, out Rect rect);
 [DllImport("user32.dll")] public static extern bool GetClipCursor(out Rect rect);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w, uint m, IntPtr a, IntPtr b);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr w, uint m, IntPtr a, IntPtr b, uint flags, uint timeout, out IntPtr result);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
'@
}
$exe = (Resolve-Path -LiteralPath $Executable).Path
$runDir = Split-Path -Parent $exe
if (!(Test-Path -LiteralPath (Join-Path $runDir 'data1\pak0.pak'))) {
    throw 'Use an isolated copy of the game data beside the executable. This test changes its config and F11/F12 bindings.'
}
$p = Start-Process -FilePath $exe -WorkingDirectory $runDir -WindowStyle Hidden -PassThru -ArgumentList @('-window','-borderless','-width','960','-height','600','-profile-frames','+in_rawinput','1','+map','demo1','+bind','F12','disconnect','+bind','F11','quit')
$clock = [Diagnostics.Stopwatch]::StartNew()
function Wait-For([scriptblock]$condition) {
    do {
        if ($p.HasExited) { throw 'Game exited early.' }
        if ($clock.Elapsed.TotalSeconds -gt 40) { throw 'Control test timeout.' }
        Start-Sleep -Milliseconds 100
    } until (& $condition)
}
function Handle { $p.Refresh(); return $p.MainWindowHandle }
function Activate([IntPtr]$w, [uint32]$message, [int]$active) {
    $result = [IntPtr]::Zero
    if ([WindowProbe]::SendMessageTimeout($w, $message, [IntPtr]$active, [IntPtr]0, 2, 3000, [ref]$result) -eq 0) {
        throw 'Game did not respond to the activation message.'
    }
}
function Fullscreen { $w = Handle; return $w -ne 0 -and ([WindowProbe]::GetWindowLong($w, -16) -band 0x00c00000) -eq 0 }
function AltEnter {
    $w = Handle
    [void][WindowProbe]::PostMessage($w, 0x104, [IntPtr]13, [IntPtr]0x201c0001)
    [void][WindowProbe]::PostMessage($w, 0x105, [IntPtr]13, [IntPtr]0xe01c0001L)
}
try {
    Wait-For { (Test-Path "$runDir\debug_h2.log") -and ((Get-Content "$runDir\debug_h2.log" -Raw) -match 'Frame: 12 ') }
    if (Fullscreen) { throw 'Expected a windowed start.' }
    AltEnter
    Wait-For { Fullscreen }
    Start-Sleep -Milliseconds 600
    $w = Handle
    if ([WindowProbe]::GetWindowLong($w,-20) -band 8) { throw 'Borderless window is topmost.' }
    $rect = New-Object WindowProbe+Rect
    [void][WindowProbe]::GetClientRect($w,[ref]$rect)
    if ($rect.Right -ne [WindowProbe]::GetSystemMetrics(0) -or $rect.Bottom -ne [WindowProbe]::GetSystemMetrics(1)) { throw 'Borderless dimensions differ from the desktop.' }
    # Exercise activation handlers with messages addressed only to this process.
    Activate $w 6 0
    Activate $w 8 0
    if ([WindowProbe]::IsIconic($w)) { throw 'Borderless minimized on focus loss.' }
    $clip = New-Object WindowProbe+Rect
    [void][WindowProbe]::GetClipCursor([ref]$clip)
    if (($clip.Right-$clip.Left) -ne [WindowProbe]::GetSystemMetrics(78)) { throw 'Mouse remained confined on focus loss.' }
    Activate $w 6 1
    [void][WindowProbe]::GetClipCursor([ref]$clip)
    if (($clip.Right-$clip.Left) -ne $rect.Right) { throw 'Mouse was not recaptured on activation.' }
    AltEnter
    Wait-For { (Handle) -ne 0 -and !(Fullscreen) }
    Start-Sleep -Milliseconds 600
    $w = Handle
    [void][WindowProbe]::GetClientRect($w,[ref]$rect)
    if ($rect.Right -ne 960 -or $rect.Bottom -ne 600) { throw 'Window dimensions were not restored.' }
    [void][WindowProbe]::PostMessage($w,0x100,[IntPtr]0x7b,[IntPtr]0x00580001)
    [void][WindowProbe]::PostMessage($w,0x101,[IntPtr]0x7b,[IntPtr]0xc0580001L)
    Start-Sleep -Milliseconds 150
    [void][WindowProbe]::PostMessage($w,0x100,[IntPtr]0x7a,[IntPtr]0x00570001)
    [void][WindowProbe]::PostMessage($w,0x101,[IntPtr]0x7a,[IntPtr]0xc0570001L)
    if (!$p.WaitForExit(5000)) { throw 'Game did not accept input after switching.' }
    if ($p.ExitCode -ne 0) { throw "Game exit: $($p.ExitCode)" }
    $log = Get-Content "$runDir\debug_h2.log" -Raw
    if ($log -match 'reinitialization failed') { throw 'Input rebinding failed.' }
    Copy-Item "$runDir\debug_h2.log" "$runDir\controls.log"
    'PASS: Alt+Enter round trip, desktop dimensions, non-topmost borderless, focus loss/reacquisition, restored window, keyboard input after switching.'
} finally {
    if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
    $p.Dispose()
}
