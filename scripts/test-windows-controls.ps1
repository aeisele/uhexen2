[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\validation\glh2.exe'),
    [switch]$LegacyMouse
)
$ErrorActionPreference = 'Stop'
if (!('WindowProbe' -as [type])) { Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WindowProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
 [StructLayout(LayoutKind.Sequential)] public struct Message { public IntPtr Window; public uint Id; public IntPtr WParam, LParam; public uint Time; public Point Position; public uint Private; }
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr w, int index);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w, out Rect rect);
 [DllImport("user32.dll")] public static extern bool GetClipCursor(out Rect rect);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr w, ref Point point);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateWindowEx(uint ex, string cls, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
 [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr w, int show);
 [DllImport("user32.dll")] public static extern bool PeekMessage(out Message message, IntPtr window, uint first, uint last, uint remove);
 [DllImport("user32.dll")] public static extern bool TranslateMessage(ref Message message);
 [DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref Message message);
 public static void Pump() { Message m; while (PeekMessage(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessage(ref m); } }
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
$gameArgs = @('-window','-borderless','-width','960','-height','600','-profile-frames','+in_rawinput','1','+map','demo1','+bind','F12','disconnect','+bind','F11','quit','+bind','F10','menu_options')
if ($LegacyMouse) { $gameArgs += '-norawinput' }
$originalCursor = New-Object WindowProbe+Point
[void][WindowProbe]::GetCursorPos([ref]$originalCursor)
$otherWindow = [IntPtr]::Zero
$p = Start-Process -FilePath $exe -WorkingDirectory $runDir -WindowStyle Hidden -PassThru -ArgumentList $gameArgs
$clock = [Diagnostics.Stopwatch]::StartNew()
function Wait-For([scriptblock]$condition, [string]$stage = 'window state') {
    do {
        if ($p.HasExited) { throw 'Game exited early.' }
        if ($clock.Elapsed.TotalSeconds -gt 55) { throw "Control test timeout: $stage" }
        [WindowProbe]::Pump()
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
function Press-Key([int]$virtualKey, [int]$scanCode) {
    $w = Handle
    $keyDown = ($scanCode -shl 16) -bor 1
    [void][WindowProbe]::PostMessage($w,0x100,[IntPtr]$virtualKey,[IntPtr]$keyDown)
    [void][WindowProbe]::PostMessage($w,0x101,[IntPtr]$virtualKey,[IntPtr]($keyDown -bor 0xc0000000L))
    Start-Sleep -Milliseconds 120
}
function Test-Foreground([string]$context) {
    Write-Host "Checking foreground loss/reacquisition in $context"
    $w = Handle
    [void][WindowProbe]::ShowWindow($otherWindow,5)
    [void][WindowProbe]::SetForegroundWindow($otherWindow)
    Wait-For { [WindowProbe]::GetForegroundWindow() -eq $otherWindow } "${context}: focus test window"
    Start-Sleep -Milliseconds 100
    $point = New-Object WindowProbe+Point
    $clip = New-Object WindowProbe+Rect
    $client = New-Object WindowProbe+Rect
    $center = New-Object WindowProbe+Point
    [void][WindowProbe]::GetClientRect($w,[ref]$client)
    $center.X = [int][math]::Floor($client.Right / 2)
    $center.Y = [int][math]::Floor($client.Bottom / 2)
    [void][WindowProbe]::ClientToScreen($w,[ref]$center)
    # Use a point on the primary display, not a virtual-desktop corner that
    # may fall into an unoccupied gap between differently arranged monitors.
    $targetX = 80
    $targetY = 80
    if (![WindowProbe]::SetCursorPos($targetX,$targetY)) { throw 'Cannot position the test cursor.' }
    # Keep the background game's event/render loop running, as mouse/window
    # messages do during real desktop use. A one-shot release check misses
    # Options redrawing and capturing the cursor again on the next frame.
    for ($i = 0; $i -lt 8; $i++) {
        [WindowProbe]::Pump()
        [void][WindowProbe]::PostMessage($w,0,[IntPtr]0,[IntPtr]0)
        Start-Sleep -Milliseconds 75
        [void][WindowProbe]::GetClipCursor([ref]$clip)
        [void][WindowProbe]::GetCursorPos([ref]$point)
        if (($clip.Right-$clip.Left) -ne [WindowProbe]::GetSystemMetrics(78) -or
            ($clip.Bottom-$clip.Top) -ne [WindowProbe]::GetSystemMetrics(79)) { throw "Mouse confined in the background: $context" }
        # The physical mouse may move during this interactive test. Detect the
        # engine's forced recenter specifically; unit tests count every warp.
        if ([math]::Abs($point.X-$center.X) -le 4 -and [math]::Abs($point.Y-$center.Y) -le 4) { throw "Mouse recentered in the background: $context" }
        if ([WindowProbe]::GetForegroundWindow() -ne $otherWindow) { throw "Foreground changed during the test: $context" }
    }
    if ([WindowProbe]::IsIconic($w)) { throw "Borderless/windowed game minimized on focus loss: $context" }
    [void][WindowProbe]::SetForegroundWindow($w)
    Wait-For { [WindowProbe]::GetForegroundWindow() -eq $w } "${context}: focus game"
    Wait-For {
        $client = New-Object WindowProbe+Rect
        $capture = New-Object WindowProbe+Rect
        [void][WindowProbe]::GetClientRect($w,[ref]$client)
        [void][WindowProbe]::GetClipCursor([ref]$capture)
        ($capture.Right-$capture.Left) -eq $client.Right -and ($capture.Bottom-$capture.Top) -eq $client.Bottom
    } "${context}: recapture cursor"
    "PASS: foreground loss/reacquisition in $context"
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
    $otherWindow = [WindowProbe]::CreateWindowEx(0,'STATIC','Hexen II focus regression test',0x00cf0000,40,40,360,180,[IntPtr]0,[IntPtr]0,[IntPtr]0,[IntPtr]0)
    if ($otherWindow -eq 0) { throw 'Cannot create the focus test window.' }
    Press-Key 0x79 0x44 # F10 opens Options, whose draw routine requests capture.
    Test-Foreground 'borderless Options'
    Press-Key 27 1 # Options -> main menu
    Press-Key 27 1 # Main menu -> gameplay
    Test-Foreground 'borderless gameplay'
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
    Test-Foreground 'windowed gameplay'
    Press-Key 0x79 0x44
    Test-Foreground 'windowed Options'
    Press-Key 27 1
    Press-Key 27 1
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
    if ($otherWindow -ne 0) { [void][WindowProbe]::DestroyWindow($otherWindow) }
    [void][WindowProbe]::SetCursorPos($originalCursor.X,$originalCursor.Y)
}
