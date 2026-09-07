param([int]$Width = 800, [int]$Height = 450)
$ErrorActionPreference = 'Stop'
if ($Width -lt 320 -or $Height -lt 180) { throw 'Requested size is too small.' }
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GameWindowSize {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
"@
$games = @(Get-Process -Name EpicSeven -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 })
if ($games.Count -ne 1) { throw 'Expected exactly one EpicSeven game window.' }
$handle = $games[0].MainWindowHandle
$outer = New-Object GameWindowSize+RECT
$client = New-Object GameWindowSize+RECT
if (!( [GameWindowSize]::GetWindowRect($handle, [ref]$outer)) -or !([GameWindowSize]::GetClientRect($handle, [ref]$client))) { throw 'Cannot read window dimensions.' }
$oldWidth = $outer.Right - $outer.Left
$oldHeight = $outer.Bottom - $outer.Top
$oldClientWidth = $client.Right - $client.Left
$oldClientHeight = $client.Bottom - $client.Top
$targetWidth = $Width + $oldWidth - $oldClientWidth
$targetHeight = $Height + $oldHeight - $oldClientHeight
if (!([GameWindowSize]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, $targetWidth, $targetHeight, 0x0016))) { throw ('SetWindowPos failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
Start-Sleep -Milliseconds 800
[void][GameWindowSize]::GetWindowRect($handle, [ref]$outer)
[void][GameWindowSize]::GetClientRect($handle, [ref]$client)
[pscustomobject]@{BeforeClientWidth=$oldClientWidth; BeforeClientHeight=$oldClientHeight; AfterClientWidth=($client.Right-$client.Left); AfterClientHeight=($client.Bottom-$client.Top); AfterOuterWidth=($outer.Right-$outer.Left); AfterOuterHeight=($outer.Bottom-$outer.Top); RequestedClientWidth=$Width; RequestedClientHeight=$Height} | ConvertTo-Json

