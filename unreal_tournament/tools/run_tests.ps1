# Runs a suite of the mod's in-game tests (scripts/mods/unreal_tournament/tests) in the running game, from the command line, and prints
# the results. The game has to be running with the mod, and its window gets the keyboard focus while this runs.
#
#   run_tests.ps1 -Suite flak [-Career es_mercenary] [-Build] [-Reload] [-TimeoutSeconds 600]
#
#   -Build   builds the mod first (vmb build, from the mods folder)
#   -Reload  reloads the mods in the game (Ctrl+Shift+R, the framework's hotkey) and waits for the mod to say it has loaded. That
#            message is only shown with the framework's developer mode on.
#
# It types "/ut_test <suite>" into the game's chat. The results are the lines with [ut_test] in the game's console log.

param(
    [Parameter(Mandatory = $true)][string]$Suite,
    [string]$Career = "",
    [switch]$Build,
    [switch]$Reload,
    [int]$TimeoutSeconds = 600,
    [int]$ReloadWaitSeconds = 20
)

$ErrorActionPreference = "Stop"

$ModsFolder = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogFolder = Join-Path $env:APPDATA "Fatshark\Vermintide 2\console_logs"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class GameKeys {
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    const uint KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004, KEYEVENTF_SCANCODE = 0x0008;

    static void Send(ushort scan, ushort vk, uint flags) {
        INPUT[] input = new INPUT[1];
        input[0].type = 1;
        input[0].u.ki.wScan = scan;
        input[0].u.ki.wVk = vk;
        input[0].u.ki.dwFlags = flags;
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    // A key by its scan code, which is what a game that reads the keyboard directly sees
    public static void Key(ushort scan, bool down) { Send(scan, 0, KEYEVENTF_SCANCODE | (down ? 0u : KEYEVENTF_KEYUP)); }

    // A character of text, which is what a text field sees
    public static void Char(char c) {
        Send((ushort)c, 0, KEYEVENTF_UNICODE);
        Send((ushort)c, 0, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP);
    }

    public static void Focus(IntPtr window) {
        ShowWindow(window, 9);
        uint ignored;
        uint foreground = GetWindowThreadProcessId(GetForegroundWindow(), out ignored);
        uint mine = GetCurrentThreadId();
        AttachThreadInput(mine, foreground, true);
        SetForegroundWindow(window);
        AttachThreadInput(mine, foreground, false);
    }
}
"@

$SCAN = @{ Ctrl = 0x1D; Shift = 0x2A; R = 0x13; Enter = 0x1C }

function Get-Game {
    $game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1

    if (-not $game) {
        throw "Vermintide 2 is not running."
    }

    return $game
}

function Focus-Game {
    $game = Get-Game
    [GameKeys]::Focus($game.MainWindowHandle)
    Start-Sleep -Milliseconds 500

    if ([GameKeys]::GetForegroundWindow() -ne $game.MainWindowHandle) {
        throw "Could not bring the game window to the front."
    }
}

function Press-Keys([int[]]$scans) {
    foreach ($scan in $scans) { [GameKeys]::Key($scan, $true); Start-Sleep -Milliseconds 40 }
    Start-Sleep -Milliseconds 80
    [array]::Reverse($scans)
    foreach ($scan in $scans) { [GameKeys]::Key($scan, $false); Start-Sleep -Milliseconds 40 }
}

function Type-Text([string]$text) {
    foreach ($c in $text.ToCharArray()) { [GameKeys]::Char($c); Start-Sleep -Milliseconds 30 }
}

function Latest-Log {
    return Get-ChildItem $LogFolder -Filter "console-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# The game keeps its log open, so it is read with sharing
function Get-LogLines {
    $stream = [System.IO.File]::Open((Latest-Log).FullName, "Open", "Read", "ReadWrite")
    $reader = New-Object System.IO.StreamReader $stream

    try {
        $lines = New-Object System.Collections.Generic.List[string]

        while (($line = $reader.ReadLine()) -ne $null) { $lines.Add($line) }

        return ,$lines.ToArray()
    } finally {
        $reader.Dispose()
    }
}

function Log-Length {
    return (Get-LogLines).Length
}

if ($Build) {
    Write-Host "Building..."
    Push-Location $ModsFolder
    & "..\vmb.exe" build unreal_tournament -f . --rc ../vmb-rc | Out-Host
    Pop-Location
}

Focus-Game

if ($Reload) {
    $before = Log-Length
    Write-Host "Reloading the mods (Ctrl+Shift+R)..."
    Press-Keys @($SCAN.Ctrl, $SCAN.Shift, $SCAN.R)

    $deadline = (Get-Date).AddSeconds($ReloadWaitSeconds)
    $loaded = $false

    while ((Get-Date) -lt $deadline -and -not $loaded) {
        Start-Sleep -Milliseconds 500
        $loaded = [bool]((Get-LogLines) | Select-Object -Skip $before | Select-String "Unreal Tournament loaded \(build")
    }

    if ($loaded) {
        Write-Host "The mod has reloaded."
    } else {
        Write-Host "No 'Unreal Tournament loaded' line after $ReloadWaitSeconds seconds. Going on anyway."
    }

    Start-Sleep -Seconds 2
}

$start = Log-Length
$command = "/ut_test $Suite $Career".Trim()

Write-Host "Running $command"
Focus-Game
Press-Keys @($SCAN.Enter)
Start-Sleep -Milliseconds 400
Type-Text $command
Start-Sleep -Milliseconds 300
Press-Keys @($SCAN.Enter)

# The results, until the suite says it is done
function Show-New([ref]$shown, [ref]$failed) {
    $lines = Get-LogLines

    for ($i = $shown.Value; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match "\[ut_test\]") {
            Write-Host $lines[$i]

            if ($lines[$i] -match "FAIL") { $failed.Value = $true }
        }
    }

    $shown.Value = $lines.Length

    return ($lines | Select-Object -Skip $start | Select-String "\[ut_test\] (\S+: \d+ passed, \d+ failed, \d+ skipped|the suite broke|there is no suite|a suite is running|the level did not load|there is no player)")
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$shown = $start
$failed = $false
$done = $false

while ((Get-Date) -lt $deadline -and -not $done) {
    Start-Sleep -Seconds 1
    $done = [bool](Show-New ([ref]$shown) ([ref]$failed))
}

if (-not $done) {
    Write-Host "Timed out after $TimeoutSeconds seconds without a summary."
    exit 2
}

# The lines that come with the end
Start-Sleep -Seconds 3
Show-New ([ref]$shown) ([ref]$failed) | Out-Null

if ($failed) { exit 1 }
exit 0
