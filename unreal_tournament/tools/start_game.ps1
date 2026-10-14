# Starts Vermintide 2 from the command line, without the launcher, and waits until the player is in the Keep. It starts the game's program
# with the arguments that the launcher gives it (read from the running game's command line: -eac-untrusted --bundle-dir ../bundle --ini
# settings --silent-mode), from the launcher's folder, and presses Enter on Start Game and on Adventure in the main menu. A mod skips the
# game's intro. The launcher and its crash windows are not used.
#
#   start_game.ps1 [-Restart] [-TimeoutSeconds 300]
#
#   -Restart  closes the game first if it is running
#
# It looks for the game's state in the game's console log, so a picture of the game's window (screenshot.ps1) is only needed if it stalls.

param(
    [switch]$Restart,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$GameFolder = "E:\SteamLibrary\steamapps\common\Warhammer Vermintide 2"
$LogFolder = Join-Path $env:APPDATA "Fatshark\Vermintide 2\console_logs"
$SteamAppId = "552500"

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

Write-Host "Starting the game..."

# The game finds Steam by these, as it does when Steam starts it
$env:SteamAppId = $SteamAppId
$env:SteamGameId = $SteamAppId

Start-Process -FilePath (Join-Path $GameFolder "binaries_dx12\vermintide2_dx12.exe") -ArgumentList @("-eac-untrusted", "--bundle-dir", "../bundle", "--ini", "settings", "--silent-mode") -WorkingDirectory (Join-Path $GameFolder "launcher")

# The log of this run is the first one that is newer than the start
function Get-NewLog {
    return Get-ChildItem $LogFolder -Filter "console-*.log" | Where-Object { $_.CreationTime -gt $startedAt } | Sort-Object CreationTime | Select-Object -First 1
}

# The log is read with sharing, because the game keeps it open
function Read-Shared([string]$path) {
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

    if (-not (Get-Game)) {
        Write-Host "The game is not running: it closed or crashed while starting."
        exit 3
    }

    $log = Get-NewLog

    if ($log) {
        $text = Read-Shared $log.FullName

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
exit 0
