# Starts Vermintide 2 through Steam, from the command line, and waits until the player is in the Keep. It clicks Play in the game's
# launcher (the modded realm has to be the one that is chosen there), and presses Enter on Start Game and on Adventure in the main
# menu. A mod skips the game's intro.
#
#   start_game.ps1 [-Restart] [-TimeoutSeconds 300]
#
#   -Restart  closes the game first if it is running
#
# It looks for the game's state in the game's console log. Pictures of the game's window can be taken with screenshot.ps1 if it stalls.

param(
    [switch]$Restart,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$LogFolder = Join-Path $env:APPDATA "Fatshark\Vermintide 2\console_logs"
$SteamAppId = 552500

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class LauncherWindows {
    delegate bool EnumProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    // Closes the visible windows of these processes whose title is not the one to keep. Returns their titles.
    public static List<string> CloseOthers(HashSet<uint> processIds, string keepTitle) {
        List<string> closed = new List<string>();
        EnumWindows(delegate (IntPtr window, IntPtr parameter) {
            uint pid;
            GetWindowThreadProcessId(window, out pid);
            if (processIds.Contains(pid) && IsWindowVisible(window)) {
                StringBuilder text = new StringBuilder(256);
                GetWindowText(window, text, 256);
                if (text.ToString() != keepTitle) {
                    PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
                    closed.Add(text.ToString());
                }
            }
            return true;
        }, IntPtr.Zero);
        return closed;
    }
}
"@

# After a crash the launcher and its crash reporter put up windows ("Crash Upload Failed", "Enter Crash Details") that stop it from
# going on. This closes every window of the game's launcher programs but the launcher itself.
function Close-LauncherDialogs {
    $ids = New-Object "System.Collections.Generic.HashSet[uint32]"

    Get-Process | Where-Object { $_.ProcessName -in @("Launcher", "CrashReporter", "CrashifyUploader") -and $_.Path -like "*\Warhammer Vermintide 2\*" } | ForEach-Object { [void]$ids.Add([uint32]$_.Id) }

    foreach ($title in [LauncherWindows]::CloseOthers($ids, "Launcher")) {
        Write-Host "Closed the window '$title'."
    }
}

function Get-Game {
    return Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" } | Select-Object -First 1
}

if (Get-Game) {
    if (-not $Restart) {
        Write-Host "The game is already running."
        exit 0
    }

    Write-Host "Closing the game..."
    Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" } | Stop-Process -Force
    Start-Sleep -Seconds 6
}

# A game that crashed leaves its crash report window and its launcher running, and the next launcher then does not start: it fails on the
# log that the old one holds. They are programs in the game's folder.
Get-Process | Where-Object { $_.ProcessName -in @("Launcher", "CrashReporter", "CrashifyUploader") -and $_.Path -like "*\Warhammer Vermintide 2\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startedAt = Get-Date

# The launcher writes its own log, and says in it when its buttons can be used
$LauncherLog = Join-Path (Join-Path $env:APPDATA "Fatshark\Vermintide 2") "vermintide2_launcher.log"

function Read-Shared([string]$path) {
    $stream = [System.IO.File]::Open($path, "Open", "Read", "ReadWrite")
    $reader = New-Object System.IO.StreamReader $stream

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

$launcherLogLength = if (Test-Path $LauncherLog) { (Read-Shared $LauncherLog).Length } else { 0 }

Write-Host "Starting the game through Steam..."
Start-Process "steam://rungameid/$SteamAppId"

# The launcher's Play button, as a place in the picture of the launcher's window (see screenshot.ps1 -Target launcher)
$launcherDeadline = (Get-Date).AddSeconds(90)

while ((Get-Date) -lt $launcherDeadline) {
    Close-LauncherDialogs

    $launcher = Get-Process | Where-Object { $_.ProcessName -eq "Launcher" -and $_.Path -like "*\Warhammer Vermintide 2\*" -and $_.MainWindowTitle -eq "Launcher" } | Select-Object -First 1

    if ($launcher) { break }

    Start-Sleep -Seconds 2
}

if ($launcher) {
    # The Play button works once the launcher says its interface is enabled
    $readyDeadline = (Get-Date).AddSeconds(90)
    $ready = $false

    while ((Get-Date) -lt $readyDeadline -and -not $ready) {
        Close-LauncherDialogs
        Start-Sleep -Seconds 1

        $text = Read-Shared $LauncherLog
        # The launcher may have started its log again
        $from = if ($text.Length -ge $launcherLogLength) { $launcherLogLength } else { 0 }
        $ready = $text.Substring($from).Contains("UI Enabled")
    }

    if (-not $ready) {
        Write-Host "The launcher did not say it was ready. Clicking Play anyway."
    }

    # The button needs a moment to draw, and a click that does not start the game is made again
    Start-Sleep -Seconds 4

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Host "Clicking Play in the launcher (try $attempt)..."
        & (Join-Path $PSScriptRoot "game_input.ps1") -Target launcher -Click "240,685"

        $waitUntil = (Get-Date).AddSeconds(25)

        while ((Get-Date) -lt $waitUntil -and -not (Get-Game)) {
            Close-LauncherDialogs
            Start-Sleep -Seconds 1
        }

        if (Get-Game) { break }
    }
}

# The log of this run is the first one that is newer than the start
function Get-NewLog {
    return Get-ChildItem $LogFolder -Filter "console-*.log" | Where-Object { $_.CreationTime -gt $startedAt } | Sort-Object CreationTime | Select-Object -First 1
}

# The log is read with sharing, because the game keeps it open
function Read-Lines([string]$path) {
    $stream = [System.IO.File]::Open($path, "Open", "Read", "ReadWrite")
    $reader = New-Object System.IO.StreamReader $stream

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $false
$menuStep = 0

while ((Get-Date) -lt $deadline -and -not $ready) {
    Start-Sleep -Seconds 2

    $log = Get-NewLog

    if ($log) {
        $text = Read-Lines $log.FullName

        if ($text -match "\[Gamestate\] Enter StateIngame") {
            $ready = $true
        } elseif ($menuStep -eq 0 -and $text -match "StateTitleScreenInitNetwork") {
            # The main menu is up. Start Game is chosen, and then Adventure, which loads the Keep.
            $menuStep = 1
            Start-Sleep -Seconds 5
            Write-Host "Choosing Start Game..."
            & (Join-Path $PSScriptRoot "game_input.ps1") -Key Enter
            Start-Sleep -Seconds 4
            Write-Host "Choosing Adventure..."
            & (Join-Path $PSScriptRoot "game_input.ps1") -Key Enter
        }
    }
}

if (-not $ready) {
    Write-Host "The game did not reach the Keep in $TimeoutSeconds seconds."
    exit 2
}

# The Keep has to finish loading
Start-Sleep -Seconds 15
Write-Host "The game is in the Keep."
