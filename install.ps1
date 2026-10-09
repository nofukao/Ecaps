<#
.SYNOPSIS
    Install or update Ecaps (Emacs-like key bindings for Windows, AutoHotkey v2).

.DESCRIPTION
    Idempotent: running it again changes nothing if everything is already in place,
    and running it after a new release updates to that release.

      0. On a PC that accepts Remote Desktop, check the two settings that keep new RDP
         sessions in the Japanese layout, and only report them if missing (no change).
      1. (admin, one UAC prompt) Install AutoHotkey v2 via winget if missing, and write
         the standard CapsLock -> F13 / ScrollLock -> CapsLock "Scancode Map" if unset.
      2. Download the latest GitHub release of nofukao/Ecaps (or -Version / -Source)
         into %LOCALAPPDATA%\Programs\Ecaps and record it in VERSION.txt.
      3. Create the startup shortcut "Ecaps.lnk" (UI Access build of AutoHotkey) and
         remove other startup shortcuts that point to an Ecaps.ahk (duplicates).
      4. Stop Ecaps instances running from other paths and (re)start the installed one.
      5. Optionally (-PowerShellEmacs) set PSReadLine to Emacs edit mode.

    This file is kept ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less
    files as the ANSI code page.
    See README.md ("Install") for the human/AI-agent instructions.

    Download it to a file and run it with -File. Do NOT pass the download URL on a
    PowerShell command line ("powershell -c ... irm <url>") or pipe it to iex:
    Microsoft Defender blocks such command lines as Trojan:Win32/Commando.

.EXAMPLE
    curl.exe -fsSL -o "$env:TEMP\ecaps-install.ps1" https://raw.githubusercontent.com/nofukao/Ecaps/main/install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\ecaps-install.ps1"
#>
[CmdletBinding()]
param(
    [string]$Version,          # release tag such as v1.0.0 (default: latest release)
    [string]$Source,           # install from a local folder instead of a release (for testing)
    [switch]$NoUIA,            # start with AutoHotkey64.exe instead of the UI Access build
    [switch]$NoAdmin,          # never elevate; only report what needs admin rights
    [switch]$Force,            # overwrite a non-standard existing Scancode Map
    [switch]$PowerShellEmacs   # also set PSReadLine EditMode Emacs in the PowerShell profile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo        = 'nofukao/Ecaps'
$InstallDir  = Join-Path $env:LOCALAPPDATA 'Programs\Ecaps'
$StartupDir  = [Environment]::GetFolderPath('Startup')
$ShortcutLnk = Join-Path $StartupDir 'Ecaps.lnk'
$KbdKey      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
# CapsLock (0x3A) -> F13 (0x64), ScrollLock (0x46) -> CapsLock (0x3A)
$StdScancodeMap = [byte[]](0,0,0,0, 0,0,0,0, 3,0,0,0, 0x64,0,0x3A,0, 0x3A,0,0x46,0, 0,0,0,0)
$Files = @('Ecaps.ahk', 'install.ps1', 'README.md', 'docs')

$script:Todo = New-Object System.Collections.Generic.List[string]
function Say([string]$Status, [string]$Message) {
    $color = @{ 'OK' = 'Green'; 'CHANGED' = 'Cyan'; 'TODO' = 'Yellow'; 'ERROR' = 'Red' }[$Status]
    Write-Host ('[{0,-7}] {1}' -f $Status, $Message) -ForegroundColor $color
    if ($Status -in 'TODO', 'ERROR') { $script:Todo.Add($Message) }
}

# ---------------------------------------------------------------- AutoHotkey / Scancode Map
function Find-AhkDir {
    $dirs = @()
    try { $dirs += (Get-ItemProperty 'HKLM:\SOFTWARE\AutoHotkey' -ErrorAction Stop).InstallDir } catch { }
    $dirs += Join-Path $env:ProgramFiles 'AutoHotkey'
    foreach ($d in $dirs) {
        if ($d -and (Test-Path (Join-Path $d 'v2\AutoHotkey64.exe'))) { return (Join-Path $d 'v2') }
    }
    return $null
}

function Get-ScancodeState {
    $cur = $null
    try { $cur = (Get-ItemProperty $KbdKey -Name 'Scancode Map' -ErrorAction Stop).'Scancode Map' } catch { }
    if ($null -eq $cur) { return 'missing' }
    if ([BitConverter]::ToString($cur) -eq [BitConverter]::ToString($StdScancodeMap)) { return 'standard' }
    return 'different'
}

# ---------------------------------------------------------------- Remote Desktop keyboard layout
# A new RDP session (after a restart or sign-out) can start with the English layout: the
# client reports Japanese keyboard subtype 0, which maps to kbd101.dll, and the client's
# layout is imported as the session default. Only report it; the fix is the user's call.
$TsKey       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$TsJpn       = "$TsKey\KeyboardType Mapping\JPN"
$TsPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

function Get-RegValue([string]$Key, [string]$Name) {
    try { return (Get-ItemProperty $Key -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Test-RdpKeyboard {
    Add-Type -AssemblyName System.Windows.Forms
    $inRdp = [System.Windows.Forms.SystemInformation]::TerminalServerSession
    $deny  = Get-RegValue $TsPolicyKey 'fDenyTSConnections'
    if ($null -eq $deny) { $deny = Get-RegValue $TsKey 'fDenyTSConnections' }
    if (-not $inRdp -and $deny -ne 0) { return }    # this PC does not accept Remote Desktop

    if ((Get-RegValue $TsJpn '00000000') -eq 'kbd106.dll' -and (Get-RegValue $KbdKey 'IgnoreRemoteKeyboardLayout') -eq 1) {
        Say 'OK' 'Remote Desktop: new sessions keep the Japanese keyboard layout.'
        return
    }
    Say 'TODO' ('Remote Desktop: a new RDP session (after a restart or sign-out) may start with the English layout. ' +
        'Run these in an elevated PowerShell before you restart or sign out (README: troubleshooting):' +
        [Environment]::NewLine + "Set-ItemProperty -Path '$TsJpn' -Name '00000000' -Value 'kbd106.dll'" +
        [Environment]::NewLine + "New-ItemProperty -Path '$KbdKey' -Name 'IgnoreRemoteKeyboardLayout' -PropertyType DWord -Value 1 -Force")
}

function Invoke-AdminTasks {
    $ahk = Find-AhkDir
    $sc  = Get-ScancodeState
    $needAhk = -not $ahk
    $needSc  = ($sc -eq 'missing') -or ($sc -eq 'different' -and $Force)

    if ($sc -eq 'different' -and -not $Force) {
        Say 'TODO' 'Scancode Map already has a non-standard value; left unchanged (use -Force to replace it with CapsLock->F13, ScrollLock->CapsLock).'
    }
    if (-not ($needAhk -or $needSc)) { return }

    $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if ($needAhk -and -not $winget) {
        Say 'TODO' 'AutoHotkey v2 is not installed and winget is not available. Install it from https://www.autohotkey.com/ (for all users), then run this script again.'
        $needAhk = $false
        if (-not $needSc) { return }
    }

    $lines = @('$ErrorActionPreference = "Continue"')
    if ($needAhk) {
        $lines += "& '$winget' install --id AutoHotkey.AutoHotkey -e --silent --accept-package-agreements --accept-source-agreements"
    }
    if ($needSc) {
        $bytes = ($StdScancodeMap | ForEach-Object { '0x{0:X2}' -f $_ }) -join ','
        $lines += "Set-ItemProperty -Path '$KbdKey' -Name 'Scancode Map' -Type Binary -Value ([byte[]]($bytes))"
    }

    if ($NoAdmin) {
        Say 'TODO' ('Run these in an elevated PowerShell, then run this script again:' + [Environment]::NewLine + ($lines[1..($lines.Count - 1)] -join [Environment]::NewLine))
        return
    }

    $what = @()
    if ($needAhk) { $what += 'install AutoHotkey v2 (winget)' }
    if ($needSc)  { $what += 'set CapsLock->F13 / ScrollLock->CapsLock (registry)' }
    Write-Host ('Requesting administrator rights to: ' + ($what -join ', ') + '. Please answer the UAC prompt.') -ForegroundColor Yellow
    # Run the admin commands from a temporary .ps1 file (-File). Microsoft Defender flags
    # PowerShell command lines that carry code inline (-EncodedCommand / -Command with a
    # download) as Trojan:Win32/Commando, so never put code on the command line.
    $adminScript = Join-Path ([IO.Path]::GetTempPath()) 'ecaps-install-admin.ps1'
    Set-Content -Path $adminScript -Value $lines -Encoding UTF8   # UTF-8 with BOM: safe for non-ASCII user paths
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
                -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $adminScript + '"')
    } catch {
        Say 'TODO' 'The UAC prompt was declined; administrator tasks were skipped. Run this script again to retry (or use -NoAdmin to see the commands).'
        return
    } finally {
        Remove-Item $adminScript -ErrorAction SilentlyContinue
    }
    if ($needAhk) {
        if (Find-AhkDir) { Say 'CHANGED' 'Installed AutoHotkey v2.' }
        else { Say 'ERROR' "AutoHotkey v2 installation did not complete (exit code $($p.ExitCode))." }
    }
    if ($needSc) {
        if ((Get-ScancodeState) -eq 'standard') {
            Say 'CHANGED' 'Set CapsLock->F13 / ScrollLock->CapsLock.'
            Say 'TODO' 'Restart Windows to activate the CapsLock->F13 mapping.'
        } else { Say 'ERROR' 'Could not write the Scancode Map.' }
    }
}

# ---------------------------------------------------------------- files
function Get-InstalledVersion {
    $f = Join-Path $InstallDir 'VERSION.txt'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return $null
}

function Copy-EcapsFiles([string]$From, [string]$VersionLabel) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($name in $Files) {
        $src = Join-Path $From $name
        if (-not (Test-Path $src)) { throw "Missing '$name' in $From" }
        Copy-Item -Path $src -Destination $InstallDir -Recurse -Force
    }
    Set-Content -Path (Join-Path $InstallDir 'VERSION.txt') -Value $VersionLabel -Encoding ASCII
}

function Test-SameFiles([string]$From) {
    foreach ($name in $Files) {
        $src = Join-Path $From $name
        $dst = Join-Path $InstallDir $name
        if (-not (Test-Path $dst)) { return $false }
        $a = Get-ChildItem $src -Recurse -File | ForEach-Object { (Get-FileHash $_.FullName).Hash }
        $b = Get-ChildItem $dst -Recurse -File | ForEach-Object { (Get-FileHash $_.FullName).Hash }
        if (($a -join ',') -ne ($b -join ',')) { return $false }
    }
    return $true
}

# Returns $true when files were changed.
function Install-Files {
    $installed = Get-InstalledVersion
    if ($Source) {
        $from = (Resolve-Path $Source).Path
        if ((Test-SameFiles $from) -and $installed -eq 'local') {
            Say 'OK' "Files in $InstallDir are up to date with $from."
            return $false
        }
        Copy-EcapsFiles $from 'local'
        Say 'CHANGED' "Installed from local folder $from to $InstallDir."
        return $true
    }

    $tag = $Version
    if (-not $tag) {
        try {
            $rel = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases/latest"
            $tag = $rel.tag_name
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
                throw "No release of $Repo has been published yet (https://github.com/$Repo/releases)."
            }
            throw "Could not get the latest release of $Repo from GitHub ($($_.Exception.Message)). Check the network, or specify -Version."
        }
    }
    if ($installed -eq $tag -and (Test-Path (Join-Path $InstallDir 'Ecaps.ahk'))) {
        Say 'OK' "Ecaps $tag is already installed in $InstallDir."
        return $false
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ecaps-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'ecaps.zip'
        Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/archive/refs/tags/$tag.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x')
        $top = Get-ChildItem (Join-Path $tmp 'x') -Directory | Select-Object -First 1
        Copy-EcapsFiles $top.FullName $tag
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    if ($installed) { Say 'CHANGED' "Updated Ecaps $installed -> $tag in $InstallDir." }
    else { Say 'CHANGED' "Installed Ecaps $tag to $InstallDir." }
    return $true
}

# ---------------------------------------------------------------- startup shortcut / processes
function Get-AhkExe([string]$AhkDir) {
    $uia = Join-Path $AhkDir 'AutoHotkey64_UIA.exe'
    if (-not $NoUIA -and (Test-Path $uia)) { return $uia }
    if (-not $NoUIA) { Say 'TODO' 'AutoHotkey64_UIA.exe not found (install AutoHotkey for all users under Program Files to get it); using AutoHotkey64.exe.' }
    return (Join-Path $AhkDir 'AutoHotkey64.exe')
}

function Set-StartupShortcut([string]$Exe) {
    $shell  = New-Object -ComObject WScript.Shell
    $script = Join-Path $InstallDir 'Ecaps.ahk'
    $args_  = '"' + $script + '"'

    foreach ($lnk in Get-ChildItem $StartupDir -Filter '*.lnk') {
        if ($lnk.FullName -eq $ShortcutLnk) { continue }
        $s = $shell.CreateShortcut($lnk.FullName)
        if (($s.TargetPath + ' ' + $s.Arguments) -match '(?i)\\Ecaps\.ahk') {
            Remove-Item $lnk.FullName -Force
            Say 'CHANGED' "Removed old startup shortcut '$($lnk.Name)' ($($s.TargetPath) $($s.Arguments))."
        }
    }

    $s = $shell.CreateShortcut($ShortcutLnk)
    if ((Test-Path $ShortcutLnk) -and $s.TargetPath -eq $Exe -and $s.Arguments -eq $args_) {
        Say 'OK' "Startup shortcut $ShortcutLnk is in place."
        return
    }
    $s.TargetPath       = $Exe
    $s.Arguments        = $args_
    $s.WorkingDirectory = $InstallDir
    $s.Description      = 'Ecaps (Emacs-like key bindings)'
    $s.Save()
    Say 'CHANGED' "Created startup shortcut $ShortcutLnk -> $Exe $args_."
}

if (-not ('EcapsInstall.Win' -as [type])) {   # Add-Type fails if run twice in one session
Add-Type -Namespace EcapsInstall -Name Win -MemberDefinition @'
    public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, System.IntPtr l);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
    public static System.Collections.Generic.List<string> AhkTitles() {
        var r = new System.Collections.Generic.List<string>();
        EnumWindows((h, l) => {
            var c = new System.Text.StringBuilder(64); GetClassName(h, c, 64);
            if (c.ToString() == "AutoHotkey") { var t = new System.Text.StringBuilder(1024); GetWindowText(h, t, 1024); r.Add(t.ToString()); }
            return true;
        }, System.IntPtr.Zero);
        return r;
    }
'@
}

# Full paths of running Ecaps.ahk scripts (from the hidden AutoHotkey main window titles)
function Get-RunningEcaps {
    foreach ($t in [EcapsInstall.Win]::AhkTitles()) {
        if ($t -match '(?i)^(.*\\Ecaps\.ahk) - AutoHotkey') { $Matches[1] }
    }
}

function Restart-Ecaps([string]$Exe, [bool]$FilesChanged) {
    $script  = Join-Path $InstallDir 'Ecaps.ahk'
    $running = @(Get-RunningEcaps)
    $others  = @($running | Where-Object { $_ -ne $script })

    if ($others.Count -gt 0) {
        # A UI Access instance ignores messages from normal processes, so ask AutoHotkey
        # (UIA build when available) to post the tray "Exit" command to the other instances.
        $stopper = Join-Path ([IO.Path]::GetTempPath()) 'ecaps-stop-others.ahk'
        Set-Content -Path $stopper -Encoding UTF8 -Value @'
#Requires AutoHotkey v2.0
#NoTrayIcon
DetectHiddenWindows(true)
for hwnd in WinGetList("ahk_class AutoHotkey") {
    title := WinGetTitle(hwnd)
    if WinGetPID(hwnd) != ProcessExist() && RegExMatch(title, "i)\\Ecaps\.ahk - AutoHotkey") && !InStr(title, A_Args[1] " - ")
        PostMessage(0x111, 65307, 0, , hwnd)   ; ID_TRAY_EXIT
}
'@
        Start-Process -FilePath $Exe -ArgumentList ('"' + $stopper + '"'), ('"' + $script + '"') -Wait
        Start-Sleep -Milliseconds 800
        Remove-Item $stopper -ErrorAction SilentlyContinue
        $left = @(Get-RunningEcaps | Where-Object { $_ -ne $script })
        foreach ($o in $others) {
            if ($left -contains $o) { Say 'TODO' "Could not stop Ecaps running from $o; exit it from its tray icon." }
            else { Say 'CHANGED' "Stopped Ecaps running from $o." }
        }
    }

    if (($running -contains $script) -and -not $FilesChanged) {
        Say 'OK' "Ecaps is running from $script."
        return
    }
    # ShellExecute (Start-Process) is required for the UIA build; /restart replaces a running copy.
    Start-Process -FilePath $Exe -ArgumentList '/restart', ('"' + $script + '"')
    for ($i = 0; $i -lt 20 -and -not ((Get-RunningEcaps) -contains $script); $i++) { Start-Sleep -Milliseconds 250 }
    if ((Get-RunningEcaps) -contains $script) { Say 'CHANGED' "Started Ecaps from $script." }
    else { Say 'ERROR' "Ecaps did not start ($Exe $script)." }
}

# ---------------------------------------------------------------- PowerShell Emacs mode
function Set-PowerShellEmacs {
    $line = 'Set-PSReadLineOption -EditMode Emacs'
    if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
    if ((Get-Content $PROFILE -Raw) -match [regex]::Escape($line)) {
        Say 'OK' "PowerShell profile already uses Emacs edit mode ($PROFILE)."
    } else {
        Add-Content -Path $PROFILE -Value $line
        Say 'CHANGED' "Added '$line' to $PROFILE."
    }
    if ((Get-ExecutionPolicy -Scope CurrentUser) -notin 'RemoteSigned', 'Unrestricted', 'Bypass') {
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        Say 'CHANGED' 'Set execution policy (CurrentUser) to RemoteSigned so the profile can run.'
    }
}

# ---------------------------------------------------------------- main
Write-Host "Ecaps installer -> $InstallDir" -ForegroundColor White
try {
    Test-RdpKeyboard    # first, so that its TODO is listed before "Restart Windows"
    Invoke-AdminTasks
    $sc = Get-ScancodeState
    if ($sc -eq 'standard') { Say 'OK' 'CapsLock->F13 / ScrollLock->CapsLock (Scancode Map) is set.' }
    elseif ($sc -eq 'missing') { Say 'TODO' 'CapsLock->F13 is not set (Scancode Map missing).' }

    $ahkDir = Find-AhkDir
    if (-not $ahkDir) { throw 'AutoHotkey v2 is required but not installed.' }
    Say 'OK' "AutoHotkey v2 found in $ahkDir."

    $changed = Install-Files
    $exe = Get-AhkExe $ahkDir
    Set-StartupShortcut $exe
    Restart-Ecaps $exe $changed
    if ($PowerShellEmacs) { Set-PowerShellEmacs }
} catch {
    Say 'ERROR' $_.Exception.Message
}

Write-Host ''
Write-Host ("Installed version: {0}" -f (Get-InstalledVersion)) -ForegroundColor White
if ($script:Todo.Count -eq 0) {
    Write-Host 'Done. Ecaps is installed and running.' -ForegroundColor Green
} else {
    Write-Host 'Action needed:' -ForegroundColor Yellow
    $script:Todo | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
