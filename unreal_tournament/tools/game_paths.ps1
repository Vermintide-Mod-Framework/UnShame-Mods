# Where the games are on this machine, for the scripts that start them (start_game.ps1, start_ut2004.ps1). The folders are in
# game_paths.json next to this file, which git ignores, as each machine has its own. game_paths.example.json shows what it holds: copy it
# to game_paths.json and put the folders in.
#
#   . (Join-Path $PSScriptRoot "game_paths.ps1")
#   $GameFolder = Get-GameFolder "vermintide2"

function Get-GameFolder([string]$Name) {
    $config = Join-Path $PSScriptRoot "game_paths.json"

    if (-not (Test-Path $config)) {
        throw "There is no $config. Copy game_paths.example.json there and put in the folders of the games."
    }

    $folder = (Get-Content -Raw $config | ConvertFrom-Json).$Name

    if (-not $folder) {
        throw "$config has no folder for $Name."
    }

    if (-not (Test-Path $folder)) {
        throw "The folder for $Name in $config is not there: $folder"
    }

    return $folder
}
