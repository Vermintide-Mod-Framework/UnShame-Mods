# Saves a picture of the running game's window as a PNG, so that what the game shows can be looked at from the command line. It never takes
# a picture of anything else on the screen.
#
#   screenshot.ps1 -Path out.png [-Target launcher]
#
# -Target launcher takes the picture of the game's launcher window (the program in the game's folder) instead.
#
# It copies the window's area of the screen, so the window has to be visible and not covered (it is brought to the front first). A game
# in exclusive full screen may give a black picture. Borderless or windowed gives the real one.

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet("game", "launcher")][string]$Target = "game"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class GameWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

[void][GameWindow]::SetProcessDPIAware()

# The game's window, or the game's launcher, which is a program in the game's folder
if ($Target -eq "launcher") {
    $game = Get-Process | Where-Object { $_.ProcessName -eq "Launcher" -and $_.Path -like "*\Warhammer Vermintide 2\*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
} else {
    $game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $game) {
    throw "Vermintide 2 ($Target) is not running. This only takes pictures of the game's window or its launcher, never of the rest of the screen."
}

$window = $game.MainWindowHandle

[void][GameWindow]::ShowWindow($window, 9)
[void][GameWindow]::SetForegroundWindow($window)
Start-Sleep -Milliseconds 400

$rect = New-Object GameWindow+RECT
[void][GameWindow]::GetClientRect($window, [ref]$rect)

$origin = New-Object GameWindow+POINT
[void][GameWindow]::ClientToScreen($window, [ref]$origin)

# The taskbar and anything else outside the screen's work area is left out
Add-Type -AssemblyName System.Windows.Forms
$work = [System.Windows.Forms.Screen]::FromHandle($window).WorkingArea
$left = [Math]::Max($origin.X, $work.Left)
$top = [Math]::Max($origin.Y, $work.Top)
$right = [Math]::Min($origin.X + $rect.Right - $rect.Left, $work.Right)
$bottom = [Math]::Min($origin.Y + $rect.Bottom - $rect.Top, $work.Bottom)

# Never more than the window itself
$outer = New-Object GameWindow+RECT
[void][GameWindow]::GetWindowRect($window, [ref]$outer)
$left = [Math]::Max($left, $outer.Left)
$top = [Math]::Max($top, $outer.Top)
$right = [Math]::Min($right, $outer.Right)
$bottom = [Math]::Min($bottom, $outer.Bottom)
$origin.X = $left
$origin.Y = $top
$width = $right - $left
$height = $bottom - $top
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

$graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size $width, $height))
$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Saved $Path ($width x $height)"
