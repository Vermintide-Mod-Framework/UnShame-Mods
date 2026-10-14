# Starts Unreal Tournament 2004 in a Deathmatch level with a weapon of each kind, so that the weapons can be looked at and played from the
# command line (screenshot.ps1 and game_input.ps1 take -Target ut2004). It is the reference for how the mod's weapons look and behave.
#
#   start_ut2004.ps1 [-Map DM-IronDeity] [-Bots 0] [-Restart]
#
#   -Restart  closes the game first if it is running
#
# The game is started with the level as its argument, so it skips the menus. Then it gets through the rest: Fire to start the match, the
# countdown, and the console command "loaded" for all weapons. The game's window is moved to the top left of the screen, because its bottom
# is under the taskbar otherwise. It is left in the level, with the console closed.

param(
    [string]$Map = "DM-IronDeity",
    [int]$Bots = 0,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

$GameFolder = "E:\SteamLibrary\steamapps\common\Unreal Tournament 2004"
$InputScript = Join-Path $PSScriptRoot "game_input.ps1"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Ut2004Window {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
}
"@

function Get-Game {
    return Get-Process | Where-Object { $_.ProcessName -like "ut2004*" } | Select-Object -First 1
}

function Send-Input([string]$Key = "", [string]$Move = "", [string]$Type = "", [switch]$Press) {
    & $InputScript -Target ut2004 -Key $Key -Move $Move -Type $Type -Press:$Press
}

if (Get-Game) {
    if (-not $Restart) {
        Write-Host "The game is already running."
        exit 0
    }

    Write-Host "Closing the game..."
    Get-Process | Where-Object { $_.ProcessName -like "ut2004*" } | Stop-Process -Force
    Start-Sleep -Seconds 3
}

Write-Host "Starting the game..."
Start-Process -FilePath (Join-Path $GameFolder "System\UT2004.exe") -ArgumentList "${Map}?game=XGame.xDeathMatch?numbots=${Bots}" -WorkingDirectory (Join-Path $GameFolder "System")

$game = $null
$deadline = (Get-Date).AddSeconds(60)

while ((Get-Date) -lt $deadline -and -not $game) {
    Start-Sleep -Seconds 1
    $game = Get-Process | Where-Object { $_.ProcessName -like "ut2004*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $game) {
    Write-Host "The game's window did not come up."
    exit 2
}

# Not resized, not on top (0x0001 and 0x0004)
[void][Ut2004Window]::SetWindowPos($game.MainWindowHandle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0005)

# The level loads
Start-Sleep -Seconds 5

Write-Host "Starting the match..."
Send-Input -Move "960,540"
Send-Input -Press

# The countdown, and the player appears
Start-Sleep -Seconds 12

Write-Host "Giving all weapons..."
Send-Input -Key Tilde
Start-Sleep -Seconds 1
Send-Input -Type "loaded"
Send-Input -Key Enter
Start-Sleep -Milliseconds 500
Send-Input -Key Escape

Write-Host "The game is in the level."
exit 0
