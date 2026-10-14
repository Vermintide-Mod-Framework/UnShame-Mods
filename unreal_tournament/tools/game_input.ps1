# Sends a key or a mouse click to the running game, for getting through its menus from the command line.
#
#   game_input.ps1 -Key Enter          one key: Enter, Space, Escape, Tab, Up, Down, Left, Right, or a letter or a number
#   game_input.ps1 -Click 1200,600     a left click at a place in the game window's picture (pixels, as in the pictures of screenshot.ps1)
#   game_input.ps1 -Move 1200,600      moves the mouse there without a click
#   game_input.ps1 -Key Ctrl -Hold 5000  holds the key that many milliseconds (80 if it is not given)
#   game_input.ps1 -Type "loaded"      types letters, digits and spaces as keys
#   game_input.ps1 -Chat "/ut_equip lightning"   opens the chat of Vermintide 2, types the text, and sends it
#   game_input.ps1 -Press [-Right] [-Hold 900]   a click where the mouse is (the right button with -Right), held that many milliseconds
#   -Target launcher sends it to Vermintide 2's launcher window instead of the game
#   -Target ut2004 sends it to Unreal Tournament 2004
#
# The game's window is brought to the front first, and the input goes to it.

param(
    [ValidateSet("game", "launcher", "ut2004")][string]$Target = "game",
    [string]$Key = "",
    [string]$Click = "",
    [string]$Move = "",
    [string]$Type = "",
    [string]$Chat = "",
    [int]$Hold = 80,
    [switch]$Press,
    [switch]$Right
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
    const uint MOUSEEVENTF_MOVE = 0x0001, MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004, MOUSEEVENTF_ABSOLUTE = 0x8000, MOUSEEVENTF_VIRTUALDESK = 0x4000;

    public static void Key(ushort scan, bool extended, bool down) {
        INPUT[] input = new INPUT[1];
        input[0].type = 1;
        input[0].u.ki.wScan = scan;
        input[0].u.ki.dwFlags = KEYEVENTF_SCANCODE | (extended ? KEYEVENTF_EXTENDEDKEY : 0u) | (down ? 0u : KEYEVENTF_KEYUP);
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    // A character of text, which is what a text field sees
    public static void Char(char c) {
        INPUT[] input = new INPUT[2];
        input[0].type = 1;
        input[0].u.ki.wScan = (ushort)c;
        input[0].u.ki.dwFlags = 0x0004;
        input[1].type = 1;
        input[1].u.ki.wScan = (ushort)c;
        input[1].u.ki.dwFlags = 0x0004 | KEYEVENTF_KEYUP;
        SendInput(2, input, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void Button(bool down, bool right) {
        INPUT[] input = new INPUT[1];
        input[0].type = 0;
        input[0].u.mi.dwFlags = right ? (down ? 0x0008u : 0x0010u) : (down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    // A mouse move that comes as input, which is what a game that reads the mouse directly (Unreal Tournament's menus) sees. The place is on
    // the whole screen, in pixels, and the screen's area is where it starts and how large it is.
    public static void MoveTo(int x, int y, int left, int top, int width, int height) {
        INPUT[] input = new INPUT[1];
        input[0].type = 0;
        input[0].u.mi.dx = (int)((x - left) * 65535L / (width - 1));
        input[0].u.mi.dy = (int)((y - top) * 65535L / (height - 1));
        input[0].u.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
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
} elseif ($Target -eq "ut2004") {
    $game = Get-Process | Where-Object { $_.ProcessName -like "ut2004*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
} else {
    $game = Get-Process | Where-Object { $_.ProcessName -like "vermintide2*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $game) {
    throw "The game ($Target) is not running."
}

$window = $game.MainWindowHandle

# The two games are not both on the screen: the other one is minimized, so that it does not cover this one
foreach ($other in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowHandle -ne $window -and ($_.ProcessName -like "ut2004*" -or $_.ProcessName -like "vermintide2*") })) {
    [void][GameInput]::ShowWindow($other.MainWindowHandle, 6)
}

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
    Tilde = @(0x29, $false); Ctrl = @(0x1D, $false); Alt = @(0x38, $false); "." = @(0x34, $false)
}

# Digits and letters, by their scan codes
$digits = "1234567890"
for ($i = 0; $i -lt $digits.Length; $i++) { $KEYS[[string]$digits[$i]] = @((0x02 + $i), $false) }

$rows = @{ 0x10 = "QWERTYUIOP"; 0x1E = "ASDFGHJKL"; 0x2C = "ZXCVBNM" }
foreach ($start in $rows.Keys) {
    for ($i = 0; $i -lt $rows[$start].Length; $i++) { $KEYS[[string]$rows[$start][$i]] = @(($start + $i), $false) }
}

function Send-Key([string]$name, [int]$hold = 80) {
    if (-not $KEYS.ContainsKey($name)) {
        throw "Unknown key $name. Known: $($KEYS.Keys -join ', ')"
    }

    $entry = $KEYS[$name]

    [GameInput]::Key($entry[0], $entry[1], $true)
    Start-Sleep -Milliseconds $hold
    [GameInput]::Key($entry[0], $entry[1], $false)
}

# Unreal Tournament's menus read the mouse as input, not from the cursor's place, so the mouse is moved with input there. Two moves are
# sent, because the cursor of its menus moves by how far the mouse has gone.
function Move-Mouse($place) {
    if ($Target -eq "ut2004") {
        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen

        foreach ($step in 1..2) {
            [GameInput]::MoveTo($place[0], $place[1], $screen.Left, $screen.Top, $screen.Width, $screen.Height)
            Start-Sleep -Milliseconds 100
        }
    } else {
        [void][GameInput]::SetCursorPos($place[0], $place[1])
    }
}

if ($Move -ne "") {
    Move-Mouse (Parse-Place $Move)
}

if ($Click -ne "") {
    Move-Mouse (Parse-Place $Click)
    Start-Sleep -Milliseconds 150
    [GameInput]::Button($true, $false)
    Start-Sleep -Milliseconds 80
    [GameInput]::Button($false, $false)
}

if ($Press) {
    [GameInput]::Button($true, [bool]$Right)
    Start-Sleep -Milliseconds $Hold
    [GameInput]::Button($false, [bool]$Right)
}

if ($Key -ne "") {
    Send-Key $Key $Hold
}

if ($Chat -ne "") {
    # Enter opens the chat, the text is typed as characters, and Enter sends it
    Send-Key "Enter"
    Start-Sleep -Milliseconds 400

    foreach ($c in $Chat.ToCharArray()) { [GameInput]::Char($c); Start-Sleep -Milliseconds 30 }

    Start-Sleep -Milliseconds 300
    Send-Key "Enter"
}

foreach ($c in $Type.ToUpper().ToCharArray()) {
    Send-Key $(if ($c -eq " ") { "Space" } else { [string]$c })
    Start-Sleep -Milliseconds 60
}
