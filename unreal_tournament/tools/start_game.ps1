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

$startedAt = Get-Date

Write-Host "Starting the game through Steam..."
Start-Process "steam://rungameid/$SteamAppId"

# The launcher's Play button, as a place in the picture of the launcher's window (see screenshot.ps1 -Target launcher)
$launcherDeadline = (Get-Date).AddSeconds(90)

while ((Get-Date) -lt $launcherDeadline) {
    $launcher = Get-Process | Where-Object { $_.ProcessName -eq "Launcher" -and $_.Path -like "*\Warhammer Vermintide 2\*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1

    if ($launcher) { break }

    Start-Sleep -Seconds 2
}

if ($launcher) {
    # The launcher needs a moment to draw its button
    Start-Sleep -Seconds 4
    Write-Host "Clicking Play in the launcher..."
    & (Join-Path $PSScriptRoot "game_input.ps1") -Target launcher -Click 240,685
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
