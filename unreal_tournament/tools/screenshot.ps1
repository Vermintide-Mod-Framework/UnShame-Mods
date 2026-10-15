# Saves a picture of the running game's window as a PNG, so that what the game shows can be looked at from the command line. It never takes
# a picture of anything else on the screen. The game is Vermintide 2, or Unreal Tournament 2004 (the reference for the weapons).
#
#   screenshot.ps1 -Path out.png [-Target launcher | ut2004] [-Burst 20 -Interval 50] [-Click left | right] [-Key 9]
#
# -Key presses a number key just before the first picture (a weapon switch), as -Click presses a mouse button (see below).
#
# -Target launcher takes the picture of Vermintide 2's launcher window (the program in the game's folder) instead.
# -Target ut2004 takes the picture of Unreal Tournament 2004's window.
#
# It copies the window's area of the screen, so the window has to be visible and not covered (it is brought to the front first). A game
# in exclusive full screen may give a black picture. Borderless or windowed gives the real one.

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet("game", "launcher", "ut2004")][string]$Target = "game",
    [int]$Burst = 1,
    [int]$Interval = 50,
    [ValidateSet("", "left", "right")][string]$Click = "",
    [ValidatePattern("^[0-9]?$")][string]$Key = ""
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
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    // Brings the window to the front. Windows lets a program do that only while it shares the input of the window that is in front.
    public static void Focus(IntPtr window) {
        ShowWindow(window, 9);
        uint ignored;
        uint foreground = GetWindowThreadProcessId(GetForegroundWindow(), out ignored);
        uint mine = GetCurrentThreadId();
        AttachThreadInput(mine, foreground, true);
        SetForegroundWindow(window);
        AttachThreadInput(mine, foreground, false);
    }

    public static void Button(uint flags) {
        INPUT[] input = new INPUT[1];
        input[0].type = 0;
        input[0].mi.dwFlags = flags;
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    // A key, by its scan code. The input is the same size as a mouse input, with the key's fields in its place.
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct KEYINPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; [FieldOffset(8)] public MOUSEINPUT mi; }
    [DllImport("user32.dll", EntryPoint = "SendInput")] static extern uint SendKeyInput(uint count, KEYINPUT[] inputs, int size);

    public static void Key(ushort scan, bool down) {
        KEYINPUT[] input = new KEYINPUT[1];
        input[0].type = 1;
        input[0].ki.wScan = scan;
        input[0].ki.dwFlags = 0x0008u | (down ? 0u : 0x0002u);
        SendKeyInput(1, input, Marshal.SizeOf(typeof(KEYINPUT)));
    }
}
"@

[void][GameWindow]::SetProcessDPIAware()

# The game's window, or the game's launcher, which is a program in the game's folder
if ($Target -eq "launcher") {
    $game = Get-Process | Where-Object { $_.ProcessName -eq "Launcher" -and $_.Path -like "*\Warhammer Vermintide 2\*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
} elseif ($Target -eq "ut2004") {
    $game = Get-Process | Where-Object { $_.ProcessName -like "ut2004*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
} else {
    $game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $game) {
    throw "The game ($Target) is not running. This only takes pictures of the window of Vermintide 2, its launcher or Unreal Tournament 2004, never of the rest of the screen."
}

$window = $game.MainWindowHandle

# The two games are not both on the screen: the other one is minimized, so that it does not cover this one
foreach ($other in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne $window -and ($_.ProcessName -like "ut2004*" -or $_.ProcessName -like "vermintide2*") })) {
    [void][GameWindow]::ShowWindow($other.MainWindowHandle, 6)
}

[GameWindow]::Focus($window)
Start-Sleep -Milliseconds 400

# A picture is of the screen where the window is, so it is only taken while the window is in front. Otherwise it would show whatever
# covers the game.
function Assert-InFront {
    if ([GameWindow]::GetForegroundWindow() -ne $window) {
        throw "The game's window ($Target) is not in front, so no picture was taken: it would show what covers the game."
    }
}

Assert-InFront

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
# With -Burst, that many pictures are taken one after the other, Interval milliseconds apart, as <Path>_1.png, <Path>_2.png and so on. The
# window is only brought to the front once, and the pictures are all taken before any is saved, so they come fast. It is for catching
# something that lasts a moment.
# With -Click, the mouse button is pressed just before the first picture and let go after the last, so the pictures show what a shot does
# from its start. The time of each picture after the press is printed.
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$down, $up = if ($Click -eq "left") { 0x0002, 0x0004 } else { 0x0008, 0x0010 }

if ($Click -ne "") {
    # (a game takes a moment after its window comes to the front before it reads the mouse)
    Start-Sleep -Milliseconds 300
    [GameWindow]::Button($down)
    $clock.Restart()
}

if ($Key -ne "") {
    # The scan codes of the number keys: 1 is 2, up to 9, and 0 is 11
    $scan = if ($Key -eq "0") { 11 } else { [int]$Key + 1 }

    Start-Sleep -Milliseconds 300
    [GameWindow]::Key($scan, $true)
    $clock.Restart()
    Start-Sleep -Milliseconds 60
    [GameWindow]::Key($scan, $false)
}

$bitmaps = @()
$times = @()

for ($index = 1; $index -le $Burst; $index++) {
    if ([GameWindow]::GetForegroundWindow() -ne $window) {
        if ($Click -ne "") { [GameWindow]::Button($up) }
        foreach ($taken in $bitmaps) { $taken.Dispose() }
        Assert-InFront
    }

    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    $graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size $width, $height))
    $times += $clock.ElapsedMilliseconds
    $graphics.Dispose()
    $bitmaps += $bitmap

    if ($index -lt $Burst) { Start-Sleep -Milliseconds $Interval }
}

if ($Click -ne "") {
    [GameWindow]::Button($up)
}

for ($index = 1; $index -le $Burst; $index++) {
    $file = if ($Burst -gt 1) { [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), [System.IO.Path]::GetFileNameWithoutExtension($Path) + "_" + $index + ".png") } else { $Path }

    $bitmaps[$index - 1].Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmaps[$index - 1].Dispose()
}

Write-Host "Saved $Path ($width x $height, $Burst picture(s))"

if ($Burst -gt 1) {
    Write-Host ("Times (ms): " + ($times -join " "))
}
