# Sends a key or a mouse click to the running game, for getting through its menus from the command line.
#
#   game_input.ps1 -Key Enter          one key: Enter, Space, Escape, Tab, Up, Down, Left, Right, or a letter or a number
#   game_input.ps1 -Click 1200,600     a left click at a place in the game window's picture (pixels, as in the pictures of screenshot.ps1)
#   game_input.ps1 -Move 1200,600      moves the mouse there without a click
#   -Target launcher sends it to the game's launcher window instead of the game
#
# The game's window is brought to the front first, and the input goes to it.

param(
    [ValidateSet("game", "launcher")][string]$Target = "game",
    [string]$Key = "",
    [string]$Click = "",
    [string]$Move = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class GameInput {
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    const uint KEYEVENTF_EXTENDEDKEY = 0x0001, KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_SCANCODE = 0x0008;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;

    public static void Key(ushort scan, bool extended, bool down) {
        INPUT[] input = new INPUT[1];
        input[0].type = 1;
        input[0].u.ki.wScan = scan;
        input[0].u.ki.dwFlags = KEYEVENTF_SCANCODE | (extended ? KEYEVENTF_EXTENDEDKEY : 0u) | (down ? 0u : KEYEVENTF_KEYUP);
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void Button(bool down) {
        INPUT[] input = new INPUT[1];
        input[0].type = 0;
        input[0].u.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
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

[void][GameInput]::SetProcessDPIAware()

# The game's window, or the game's launcher, which is a program in the game's folder
if ($Target -eq "launcher") {
    $game = Get-Process | Where-Object { $_.ProcessName -eq "Launcher" -and $_.Path -like "*\Warhammer Vermintide 2\*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
} else {
    $game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $game) {
    throw "Vermintide 2 is not running."
}

$window = $game.MainWindowHandle

[GameInput]::Focus($window)
Start-Sleep -Milliseconds 300

# The picture of screenshot.ps1 starts where the game's picture starts inside the screen's work area, so a place in it is a place on the screen
function Get-Origin {
    $point = New-Object GameInput+POINT
    [void][GameInput]::ClientToScreen($window, [ref]$point)
    $work = [System.Windows.Forms.Screen]::FromHandle($window).WorkingArea

    return @([Math]::Max($point.X, $work.Left), [Math]::Max($point.Y, $work.Top))
}

function Parse-Place([string]$text) {
    $parts = $text.Split(",")
    $origin = Get-Origin

    return @(($origin[0] + [int]$parts[0]), ($origin[1] + [int]$parts[1]))
}

# Scan codes of the keys, and whether the key is an extended one
$KEYS = @{
    Enter = @(0x1C, $false); Space = @(0x39, $false); Escape = @(0x01, $false); Tab = @(0x0F, $false)
    Up = @(0x48, $true); Down = @(0x50, $true); Left = @(0x4B, $true); Right = @(0x4D, $true)
    "1" = @(0x02, $false); "2" = @(0x03, $false); "3" = @(0x04, $false); "4" = @(0x05, $false); "5" = @(0x06, $false)
    Q = @(0x10, $false); W = @(0x11, $false); E = @(0x12, $false); R = @(0x13, $false); A = @(0x1E, $false); S = @(0x1F, $false); D = @(0x20, $false)
}

if ($Move -ne "") {
    $place = Parse-Place $Move
    [void][GameInput]::SetCursorPos($place[0], $place[1])
}

if ($Click -ne "") {
    $place = Parse-Place $Click
    [void][GameInput]::SetCursorPos($place[0], $place[1])
    Start-Sleep -Milliseconds 150
    [GameInput]::Button($true)
    Start-Sleep -Milliseconds 80
    [GameInput]::Button($false)
}

if ($Key -ne "") {
    if (-not $KEYS.ContainsKey($Key)) {
        throw "Unknown key $Key. Known: $($KEYS.Keys -join ', ')"
    }

    $entry = $KEYS[$Key]

    [GameInput]::Key($entry[0], $entry[1], $true)
    Start-Sleep -Milliseconds 80
    [GameInput]::Key($entry[0], $entry[1], $false)
}
