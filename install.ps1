<#
.SYNOPSIS
    Install or update Ecaps (Emacs-like key bindings for Windows, AutoHotkey v2).

.DESCRIPTION
    Idempotent: running it again changes nothing if everything is already in place,
    and running it after a new release updates to that release.
    It stops without changing anything when run inside an MSIX app package (e.g. by an
    AI agent in the Claude desktop app), because Windows would virtualize what it writes.

      0. On a PC that accepts Remote Desktop, check the two settings that keep new RDP
         sessions in the Japanese layout, and only report them if missing (no change).
      1. (admin, one UAC prompt) Install AutoHotkey v2 via winget if missing, and write
         the standard CapsLock -> F13 / ScrollLock -> CapsLock "Scancode Map" if unset.
      2. Download the latest GitHub release of nofukao/Ecaps (or -Version / -Source)
         into %LOCALAPPDATA%\Programs\Ecaps and record it in VERSION.txt.
      3. Create the startup shortcut "Ecaps.lnk" (UI Access build of AutoHotkey) and
         remove other startup shortcuts that point to an Ecaps.ahk (duplicates).
      4. Stop Ecaps instances running from other paths and (re)start the installed one.
      5. Check the two Microsoft IME settings for F13+j mixed Japanese/English input;
         set them only with -ImeMixedInput, otherwise report them if missing.
      6. Optionally (-PowerShellEmacs) set PSReadLine to Emacs edit mode.

    This file is kept ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less
    files as the ANSI code page.
    See README.md ("Install") for the human/AI-agent instructions.

    Get it from the latest release (attached as an asset), not from the main branch,
    so that an installer reaches other PCs only when it is released.
    Download it to a file and run it with -File. Do NOT pass the download URL on a
    PowerShell command line ("powershell -c ... irm <url>") or pipe it to iex:
    Microsoft Defender blocks such command lines as Trojan:Win32/Commando.

.EXAMPLE
    curl.exe -fsSL -o "$env:TEMP\ecaps-install.ps1" https://github.com/nofukao/Ecaps/releases/latest/download/install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\ecaps-install.ps1"
#>
[CmdletBinding()]
param(
    [string]$Version,          # release tag such as v1.0.0 (default: latest release)
    [string]$Source,           # install from a local folder instead of a release (for testing)
    [switch]$NoUIA,            # start with AutoHotkey64.exe instead of the UI Access build
    [switch]$NoAdmin,          # never elevate; only report what needs admin rights
    [switch]$Force,            # overwrite a non-standard existing Scancode Map
    [switch]$PowerShellEmacs,  # also set PSReadLine EditMode Emacs in the PowerShell profile
    [switch]$ImeMixedInput     # also set the Microsoft IME up for F13+j mixed Japanese/English input
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

# ---------------------------------------------------------------- MSIX app package
# An AI agent in a packaged (MSIX) desktop app, such as the Claude desktop app, runs its shell
# and this script inside the app's package (child processes inherit it). Windows then redirects
# new folders directly under %LOCALAPPDATA% (such as Programs) and writes to HKCU to a private
# place of that app: everything looks installed from inside, but Ecaps is missing after a restart.
if (-not ('EcapsInstall.Pkg' -as [type])) {
Add-Type -Namespace EcapsInstall -Name Pkg -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder name);
'@
}

# Full name of the app package this process runs in, or $null outside a package
function Get-PackageName {
    $len = 0
    if ([EcapsInstall.Pkg]::GetCurrentPackageFullName([ref]$len, $null) -eq 15700) { return $null }   # APPMODEL_ERROR_NO_PACKAGE
    $name = New-Object System.Text.StringBuilder ([Math]::Max($len, 1))
    [void][EcapsInstall.Pkg]::GetCurrentPackageFullName([ref]$len, $name)
    if ($name.Length -gt 0) { return $name.ToString() }
    return '(unknown)'
}

# A run inside such an app by an older install.ps1 left a copy in the app's private folder.
# Only that app sees it (as %LOCALAPPDATA%\Programs\Ecaps); Windows never runs it.
function Test-VirtualizedCopy {
    foreach ($d in @(Get-Item -Path (Join-Path $env:LOCALAPPDATA 'Packages\*\LocalCache\Local\Programs\Ecaps') -ErrorAction SilentlyContinue)) {
        Say 'TODO' ("Found an unused copy of Ecaps that an earlier run inside an app package left in that app's private folder. " +
            "Delete it: Remove-Item -Recurse -Force '$($d.FullName)'")
    }
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

# ---------------------------------------------------------------- IME (F13+j mixed input)
# F13+j turns the IME on in half-width alphanumeric mode. Typing Japanese and English mixed
# from there needs two settings of the previous version of Microsoft IME (README: IME):
#   - "Use previous version of Microsoft IME"   : NoTsf3Override2 = 1
#   - Advanced > mixed input tab, first item     : bit 0x400 of option1 ("convert alphabet
#     as romaji to kana-kanji, mainly English")
# Neither is a documented setting, so write them only when they look as expected.
$ImeTsfKey  = 'HKCU:\Software\Microsoft\Input\TSF\Tsf3Override\{03b5835f-f03c-411b-9ce2-aa23e1171e36}'
$ImeKey     = 'HKCU:\Software\Microsoft\IME\15.0\IMEJP\MSIME'
$ImeRomaBit = 0x400

# @{ Kind; Value } of a registry value, or $null if it does not exist
function Get-RegEntry([string]$Key, [string]$Name) {
    $k = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $k -or $k.GetValueNames() -notcontains $Name) { return $null }
    return @{ Kind = $k.GetValueKind($Name); Value = $k.GetValue($Name) }
}

function Set-ImeMixedInput {
    $tsf   = Get-RegEntry $ImeTsfKey 'NoTsf3Override2'
    $opt   = Get-RegEntry $ImeKey 'option1'
    $tsfOk = $tsf -and $tsf.Kind -eq 'DWord' -and $tsf.Value -eq 1
    $optOk = $opt -and $opt.Kind -eq 'DWord' -and ($opt.Value -band $ImeRomaBit)
    if ($tsfOk -and $optOk) {
        Say 'OK' 'IME: set up for F13+j mixed Japanese/English input.'
        return
    }
    if (-not $ImeMixedInput) {
        Say 'TODO' ('IME: not set up for F13+j mixed Japanese/English input (two Microsoft IME settings). ' +
            'Run this script again with -ImeMixedInput, or set them by hand (README: Japanese input (IME)).')
        return
    }

    $changed = $false
    if (-not $tsfOk) {
        if ($tsf -and $tsf.Kind -ne 'DWord') {
            Say 'TODO' "IME: NoTsf3Override2 in $ImeTsfKey is not a DWORD; left unchanged. Turn on 'Use previous version of Microsoft IME' by hand (README: Japanese input (IME))."
        } else {
            if (-not (Test-Path -LiteralPath $ImeTsfKey)) { New-Item -Path $ImeTsfKey -Force | Out-Null }
            New-ItemProperty -LiteralPath $ImeTsfKey -Name 'NoTsf3Override2' -PropertyType DWord -Value 1 -Force | Out-Null
            Say 'CHANGED' 'IME: turned on "Use previous version of Microsoft IME".'
            $changed = $true
        }
    }
    if (-not $optOk) {
        if (-not $opt -or $opt.Kind -ne 'DWord') {
            # The IME has not saved its settings yet (or the format changed): do not guess the other bits.
            Say 'TODO' "IME: option1 in $ImeKey is missing or not a DWORD; left unchanged. Check the first item of the mixed input tab in the IME's advanced settings by hand (README: Japanese input (IME))."
        } else {
            Set-ItemProperty -LiteralPath $ImeKey -Name 'option1' -Type DWord -Value ([int]$opt.Value -bor $ImeRomaBit)
            Say 'CHANGED' 'IME: turned on "convert alphabet as romaji to kana-kanji" (mixed input tab).'
            $changed = $true
        }
    }
    if ($changed) { Say 'TODO' 'Sign out and sign in again (or restart Windows) to apply the IME settings.' }
}

# ---------------------------------------------------------------- main
Write-Host "Ecaps installer -> $InstallDir" -ForegroundColor White
$package = Get-PackageName
try {
    if ($package) {
        throw ("This PowerShell runs inside the app package $package (for example, an AI agent in the Claude desktop app). " +
            "Windows would redirect the files and settings written here to that app's private folder, and Ecaps would be missing after a restart. " +
            'Nothing was changed. Run the two commands in your own terminal instead (Win+X > Terminal; README: Install).')
    }
    Test-RdpKeyboard    # first, so that its TODO is listed before "Restart Windows"
    Invoke-AdminTasks
    $sc = Get-ScancodeState
    if ($sc -eq 'standard') { Say 'OK' 'CapsLock->F13 / ScrollLock->CapsLock (Scancode Map) is set.' }
    elseif ($sc -eq 'missing') { Say 'TODO' 'CapsLock->F13 is not set (Scancode Map missing).' }

    $ahkDir = Find-AhkDir
    if (-not $ahkDir) { throw 'AutoHotkey v2 is required but not installed.' }
    Say 'OK' "AutoHotkey v2 found in $ahkDir."

    $changed = Install-Files
    Test-VirtualizedCopy
    $exe = Get-AhkExe $ahkDir
    Set-StartupShortcut $exe
    Restart-Ecaps $exe $changed
    Set-ImeMixedInput
    if ($PowerShellEmacs) { Set-PowerShellEmacs }
} catch {
    Say 'ERROR' $_.Exception.Message
}

Write-Host ''
# Inside a package, a copy that only the package sees could be reported as installed.
if (-not $package) { Write-Host ("Installed version: {0}" -f (Get-InstalledVersion)) -ForegroundColor White }
if ($script:Todo.Count -eq 0) {
    Write-Host 'Done. Ecaps is installed and running.' -ForegroundColor Green
} else {
    Write-Host 'Action needed:' -ForegroundColor Yellow
    $script:Todo | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
