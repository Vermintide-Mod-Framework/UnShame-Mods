# Saves a picture of the running game's window as a PNG (or of the whole screen if the game is not running), so that what the game shows can be looked at from the command line.
#
#   screenshot.ps1 -Path out.png
#
# It copies the window's area of the screen, so the window has to be visible and not covered (it is brought to the front first). A game
# in exclusive full screen may give a black picture. Borderless or windowed gives the real one.

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class GameWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

[void][GameWindow]::SetProcessDPIAware()

$game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1

if (-not $game) {
    # No game window: the whole screen, to see what else is there (the launcher, a dialog)
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()

    Write-Host "The game is not running. Saved the whole screen to $Path ($($bounds.Width) x $($bounds.Height))"
    return
}

$window = $game.MainWindowHandle

[void][GameWindow]::ShowWindow($window, 9)
[void][GameWindow]::SetForegroundWindow($window)
Start-Sleep -Milliseconds 400

$rect = New-Object GameWindow+RECT
[void][GameWindow]::GetClientRect($window, [ref]$rect)

$origin = New-Object GameWindow+POINT
[void][GameWindow]::ClientToScreen($window, [ref]$origin)

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

$graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size $width, $height))
$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Saved $Path ($width x $height)"
