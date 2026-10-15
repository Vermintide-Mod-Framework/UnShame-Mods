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

# The game's output goes to files of its own. Without that it holds the output of this script, and whatever reads that (a pipe to tail)
# waits until the game is closed.
Start-Process -FilePath (Join-Path $GameFolder "binaries_dx12\vermintide2_dx12.exe") -ArgumentList @("-eac-untrusted", "--bundle-dir", "../bundle", "--ini", "settings", "--silent-mode") -WorkingDirectory (Join-Path $GameFolder "launcher") -RedirectStandardOutput (Join-Path $env:TEMP "vermintide2_stdout.txt") -RedirectStandardError (Join-Path $env:TEMP "vermintide2_stderr.txt")

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
$lastMenuTry = [datetime]::MinValue

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
        } elseif ($text -match "StateTitleScreenInitNetwork" -and ((Get-Date) - $lastMenuTry).TotalSeconds -ge 12 -and $text -notmatch "Enter state StateLoading") {
            # The main menu is up. Start Game is chosen, and then Adventure, which starts loading the Keep. The menu does not take
            # input until the game has signed in, which takes a while and is not in the log, so this is tried again until the game is
            # loading.
            $lastMenuTry = Get-Date
            Start-Sleep -Seconds 3
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

# The Keep always opens the hero selection after the game starts. Confirm closes it. The log is written too late to say whether it is
# open yet, so the click is always made (in the Keep it is only a swing of the weapon). The button only takes a click once it has seen
# the mouse move onto it, so the mouse is moved next to it, then onto it, and pressed a moment later where it is. The screen can come up
# some seconds after the Keep has loaded, so this is done three times, 5 s apart.
Write-Host "Closing the hero selection..."

for ($try = 1; $try -le 3; $try++) {
    & (Join-Path $PSScriptRoot "game_input.ps1") -Move "950,1010"
    Start-Sleep -Milliseconds 500
    & (Join-Path $PSScriptRoot "game_input.ps1") -Move "960,1018"
    Start-Sleep -Seconds 1
    & (Join-Path $PSScriptRoot "game_input.ps1") -Press -Hold 120
    Start-Sleep -Seconds 5
}

Write-Host "The game is in the Keep."
exit 0
