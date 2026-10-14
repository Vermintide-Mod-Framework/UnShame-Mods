# Runs a suite of the mod's in-game tests (scripts/mods/unreal_tournament/tests) in the running game, from the command line, and prints
# the results. The game has to be running with the mod, and its window gets the keyboard focus while this runs.
#
#   run_tests.ps1 -Suite flak [-Career es_mercenary] [-Build] [-Reload] [-TimeoutSeconds 600] [-RetryAfterCrash]
#                 [-ForceCrashAfterSeconds 25]
#
#   -Build   builds the mod first (vmb build, from the mods folder)
#   -Reload  reloads the mods in the game (Ctrl+Shift+R, the framework's hotkey) and waits for the reload to show in the log
#   -RetryAfterCrash  if the game crashes (its process is gone), starts it again and runs the suite once more
#   -ForceCrashAfterSeconds  kills the game's process that long after the suite starts, to try the loop with a crash
#
# If the game is not running, it is started first (start_game.ps1) and taken to the Keep, so this one script does everything.
# Exit codes: 0 all passed, 1 a test failed, 2 timed out, 3 the game crashed.
#
# It types "/ut_test <suite>" into the game's chat. The results are the lines with [ut_test] in the game's console log.

param(
    [Parameter(Mandatory = $true)][string]$Suite,
    [string]$Career = "",
    [switch]$Build,
    [switch]$Reload,
    [int]$TimeoutSeconds = 600,
    [int]$ReloadWaitSeconds = 15,
    [int]$ForceCrashAfterSeconds = 0,
    [switch]$RetryAfterCrash
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

function Game-Running {
    return [bool](Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" })
}

# Starts the game and gets it to the Keep if it is not running
function Ensure-Game {
    if (Game-Running) { return $false }

    Write-Host "The game is not running. Starting it..."
    & (Join-Path $PSScriptRoot "start_game.ps1")

    if (-not (Game-Running)) {
        throw "The game did not start."
    }

    return $true
}

function Reload-Mods {
    $before = Log-Length
    Write-Host "Reloading the mods (Ctrl+Shift+R)..."
    Press-Keys @($SCAN.Ctrl, $SCAN.Shift, $SCAN.R)

    $deadline = (Get-Date).AddSeconds($ReloadWaitSeconds)
    $loaded = $false

    while ((Get-Date) -lt $deadline -and -not $loaded) {
        Start-Sleep -Milliseconds 500
        $loaded = [bool]((Get-LogLines) | Select-Object -Skip $before | Select-String "VMF:ON_RELOAD")
    }

    if ($loaded) {
        Write-Host "The mods are reloading."
    } else {
        Write-Host "No reload in the log after $ReloadWaitSeconds seconds. Going on anyway."
    }

    # The reload takes a few seconds to put the mods back
    Start-Sleep -Seconds 8
}

# What the log says about a crash: the Lua error and the crash dump
function Show-Crash([string]$logPath) {
    Write-Host "THE GAME CRASHED."

    $stream = [System.IO.File]::Open($logPath, "Open", "Read", "ReadWrite")
    $reader = New-Object System.IO.StreamReader $stream
    $text = $reader.ReadToEnd()
    $reader.Dispose()

    $errors = [regex]::Matches($text, "<<Lua Error>>(.*?)<</Lua Error>>", "Singleline")

    if ($errors.Count -gt 0) {
        Write-Host ("Last Lua error: " + $errors[$errors.Count - 1].Groups[1].Value.Trim())
    }

    $dump = [regex]::Match($text, "<<Crash Dump>>(.*?)<</Crash Dump>>")

    if ($dump.Success) {
        Write-Host ("Crash dump: " + $dump.Groups[1].Value)
    }
}

# Sends the suite's command to the game and follows the log until the suite is over, the game is gone, or the time is up.
# Returns "done", "crash" or "timeout", and sets $script:testsFailed.
function Run-Suite([int]$forceCrashAfter) {
    $log = Latest-Log
    $start = Log-Length
    $command = "/ut_test $Suite $Career".Trim()

    Write-Host "Running $command"
    Focus-Game
    Press-Keys @($SCAN.Enter)
    Start-Sleep -Milliseconds 400
    Type-Text $command
    Start-Sleep -Milliseconds 300
    Press-Keys @($SCAN.Enter)

    $began = Get-Date
    $deadline = $began.AddSeconds($TimeoutSeconds)
    $shown = $start
    $script:testsFailed = $false
    $crashForced = $false

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1

        if ($forceCrashAfter -gt 0 -and -not $crashForced -and ((Get-Date) - $began).TotalSeconds -ge $forceCrashAfter) {
            Write-Host "Forcing a crash: the game's process is killed."
            Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" } | Stop-Process -Force
            $crashForced = $true
        }

        $lines = Get-LogLines

        for ($i = $shown; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -match "\[ut_test\]") {
                Write-Host $lines[$i]

                if ($lines[$i] -cmatch "\[ut_test\] FAIL ") { $script:testsFailed = $true }
            }
        }

        $shown = $lines.Length

        if (-not (Game-Running)) {
            Show-Crash $log.FullName
            return "crash"
        }

        if ($lines | Select-Object -Skip $start | Select-String "\[ut_test\] (\S+: \d+ passed, \d+ failed, \d+ skipped|the suite broke|there is no suite|a suite is running|the level did not load|there is no player)") {
            # The lines that come with the end
            Start-Sleep -Seconds 3

            foreach ($line in (Get-LogLines | Select-Object -Skip $shown)) {
                if ($line -match "\[ut_test\]") { Write-Host $line }
            }

            return "done"
        }
    }

    return "timeout"
}

if ($Build) {
    Write-Host "Building..."
    Push-Location $ModsFolder
    & "..\vmb.exe" build unreal_tournament -f . --rc ../vmb-rc | Out-Host
    Pop-Location
}

$started = Ensure-Game

if (-not $started) {
    Focus-Game

    if ($Reload) { Reload-Mods }
}

$forceCrash = $ForceCrashAfterSeconds
$result = Run-Suite $forceCrash

if ($result -eq "crash" -and $RetryAfterCrash) {
    Write-Host "Starting the game again and running the suite once more..."
    [void](Ensure-Game)
    $result = Run-Suite 0
}

switch ($result) {
    "done" { if ($script:testsFailed) { exit 1 } else { exit 0 } }
    "crash" { exit 3 }
    default { Write-Host "Timed out after $TimeoutSeconds seconds without a summary."; exit 2 }
}
