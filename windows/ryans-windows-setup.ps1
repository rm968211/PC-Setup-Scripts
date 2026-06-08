#Requires -Version 5.1
<#
  Ryan's Windows Setup Script
  Target:  Windows 10 / 11
  Usage:   .\ryans-windows-setup.ps1 [-DryRun] [-Yes] [-Undo] [-GitName <name>] [-GitEmail <email>]
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Undo,
    [string]$GitName,
    [string]$GitEmail,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$script:Passed = @()
$script:Failed = @()

# -----------------------------------------------------------------------------
#  UI helpers
# -----------------------------------------------------------------------------

function Write-Banner {
    Write-Host ""
    Write-Host "  +-----------------------------------------------------+" -ForegroundColor Blue
    Write-Host "  |        W I N D O W S   S E T U P   S C R I P T      |" -ForegroundColor Blue
    Write-Host "  |              Windows 10 / 11  *  v1.0               |" -ForegroundColor Blue
    Write-Host "  +-----------------------------------------------------+" -ForegroundColor Blue
    Write-Host ""
    if ($DryRun) {
        Write-Host "    [DRY RUN] No changes will be made -- actions will only be printed." -ForegroundColor Yellow
        Write-Host ""
    }
    if ($Undo) {
        Write-Host "    [UNDO] Reverting reversible configuration changes." -ForegroundColor Yellow
        Write-Host ""
    }
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "  ------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "    > $Title" -ForegroundColor Cyan
    Write-Host "  ------------------------------------------------------" -ForegroundColor Cyan
}

function Write-Step  { param([string]$Message) Write-Host "    >  $Message" -ForegroundColor Green }
function Write-Ok    { param([string]$Message) Write-Host "    [ok]   $Message" -ForegroundColor Green }
function Write-Info  { param([string]$Message) Write-Host "    [info] $Message" -ForegroundColor Cyan }
function Write-Warn  { param([string]$Message) Write-Host "    [warn] $Message" -ForegroundColor Yellow }
function Write-ErrL  { param([string]$Message) Write-Host "    [err]  $Message" -ForegroundColor Red }
function Write-Skip  { param([string]$Message) Write-Host "    [skip] $Message (already present)" -ForegroundColor DarkGray }

function Write-Summary {
    Write-SectionHeader "RESULTS"
    Write-Host ""
    foreach ($s in $script:Passed)  { Write-Host "    [ok]   $s" -ForegroundColor Green }
    if ($script:Failed.Count -gt 0) {
        Write-Host ""
        foreach ($s in $script:Failed) { Write-Host "    [err]  $s" -ForegroundColor Red }
        Write-Host ""
        Write-Warn "$($script:Failed.Count) section(s) failed. Scroll up to see the errors, then re-run those steps manually."
    } else {
        Write-Host ""
        Write-Ok "All sections completed successfully."
    }
}

function Write-Done {
    Write-Host ""
    if ($script:Failed.Count -eq 0) {
        Write-Host "    All done! Restart your terminal (and possibly Explorer) for everything to take effect." -ForegroundColor Green
    } else {
        Write-Host "    Finished with errors -- check the summary above." -ForegroundColor Yellow
    }
    Write-Host ""
}

function Show-Usage {
    @"

Usage: .\ryans-windows-setup.ps1 [OPTIONS]

Options:
  -DryRun              Print what would happen without making any changes
  -Yes                 Skip the selection grid and confirmation -- install/configure everything
  -Undo                Revert reversible configuration changes (currently: classic context menu)
  -GitName <name>      Pre-fill the git user.name (skips the prompt)
  -GitEmail <email>    Pre-fill the git user.email (skips the prompt)
  -Help                Show this message

Examples:
  .\ryans-windows-setup.ps1
  .\ryans-windows-setup.ps1 -DryRun
  .\ryans-windows-setup.ps1 -Yes -GitName "Ryan" -GitEmail "ryan@example.com"
  .\ryans-windows-setup.ps1 -Undo

"@
}

# -----------------------------------------------------------------------------
#  Generic helpers
# -----------------------------------------------------------------------------

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Confirm-Action {
    param([string]$Message)
    if ($Yes) { return $true }
    $reply = Read-Host "    ? $Message [y/N]"
    return ($reply -match '^[Yy]$')
}

# Runs a unit of work, records pass/fail, and keeps going on error.
function Invoke-Section {
    param(
        [string]$Label,
        [scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )
    try {
        & $Action @ArgumentList
        $script:Passed += $Label
    } catch {
        Write-ErrL "$Label failed: $($_.Exception.Message)"
        $script:Failed += $Label
    }
}

# -----------------------------------------------------------------------------
#  Preflight
# -----------------------------------------------------------------------------

function Test-Preflight {
    Write-SectionHeader "PREFLIGHT CHECKS"

    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        Write-ErrL "This script only runs on Windows. Exiting."
        exit 1
    }

    if (-not (Test-CommandExists winget)) {
        Write-ErrL "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
        exit 1
    }

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = [Security.Principal.WindowsPrincipal]::new($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warn "Not running as Administrator -- some installs (e.g. Docker Desktop, WSL) may prompt for elevation."
    }

    Write-Ok "Preflight checks passed"
}

# -----------------------------------------------------------------------------
#  Winget app installs
# -----------------------------------------------------------------------------

function Test-WingetAppInstalled {
    param([string]$Id)
    $output = winget list --id $Id -e --accept-source-agreements 2>$null | Out-String
    return ($output -match [regex]::Escape($Id))
}

function Install-WingetApp {
    param([string]$Name, [string]$Id)

    if (Test-WingetAppInstalled -Id $Id) {
        Write-Skip $Name
        return
    }

    if ($DryRun) {
        Write-Info "[dry run] winget install --id $Id -e --accept-package-agreements --accept-source-agreements"
        return
    }

    Write-Step "Installing $Name..."
    winget install --id $Id -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $Id (exit code $LASTEXITCODE)"
    }
    Write-Ok "$Name installed"
}

# -----------------------------------------------------------------------------
#  Configuration: git
# -----------------------------------------------------------------------------

function Set-GitConfiguration {
    Write-SectionHeader "GIT CONFIGURATION"

    if (-not (Test-CommandExists git)) {
        Write-Warn "git is not installed -- skipping git configuration"
        return
    }

    $name  = $GitName
    $email = $GitEmail

    if (-not $Yes) {
        if ([string]::IsNullOrWhiteSpace($name))  { $name  = Read-Host "    Git name" }
        if ([string]::IsNullOrWhiteSpace($email)) { $email = Read-Host "    Git email" }
    }

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
        Write-Warn "No name/email provided -- skipping git config. Set it manually with:"
        Write-Info "  git config --global user.name `"Your Name`""
        Write-Info "  git config --global user.email `"you@example.com`""
        return
    }

    if ($DryRun) {
        Write-Info "[dry run] Would set git user.name='$name', user.email='$email', core.autocrlf=input,"
        Write-Info "[dry run] init.defaultBranch=main, pull.rebase=false, core.editor='code --wait'"
        return
    }

    git config --global user.name          $name
    git config --global user.email         $email
    git config --global core.autocrlf      input
    git config --global init.defaultBranch main
    git config --global pull.rebase        false
    git config --global core.editor        "code --wait"
    Write-Ok "Git configured for $name <$email>"
}

# -----------------------------------------------------------------------------
#  Configuration: PowerShell profile
# -----------------------------------------------------------------------------

function New-PowerShellProfile {
    Write-SectionHeader "POWERSHELL PROFILE"

    if (Test-Path $PROFILE) {
        Write-Skip "PowerShell profile ($PROFILE)"
        return
    }

    if ($DryRun) {
        Write-Info "[dry run] Would create $PROFILE with starter aliases and PSReadLine tweaks"
        return
    }

    $profileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    @'
# Created by ryans-windows-setup.ps1
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
}

function ll  { Get-ChildItem @args }
function ..  { Set-Location .. }
function ... { Set-Location ..\.. }
'@ | Set-Content -Path $PROFILE -Encoding utf8

    Write-Ok "PowerShell profile created at $PROFILE"
}

# -----------------------------------------------------------------------------
#  Configuration: Explorer tweaks
# -----------------------------------------------------------------------------

function Set-ExplorerTweaks {
    Write-SectionHeader "EXPLORER TWEAKS"

    $advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $tweaks = @(
        @{ Name = "Hidden";      Value = 1; Description = "Show hidden files" }
        @{ Name = "HideFileExt"; Value = 0; Description = "Show file extensions" }
        @{ Name = "LaunchTo";    Value = 1; Description = "Launch File Explorer to 'This PC'" }
    )

    foreach ($tweak in $tweaks) {
        $current = (Get-ItemProperty -Path $advanced -Name $tweak.Name -ErrorAction SilentlyContinue).$($tweak.Name)
        if ($current -eq $tweak.Value) {
            Write-Skip $tweak.Description
            continue
        }
        if ($DryRun) {
            Write-Info "[dry run] Would set $($tweak.Name) = $($tweak.Value)  ($($tweak.Description))"
            continue
        }
        Set-ItemProperty -Path $advanced -Name $tweak.Name -Value $tweak.Value -Type DWord -Force
        Write-Ok $tweak.Description
    }

    if (-not $DryRun) {
        Write-Info "Sign out, or restart explorer.exe, for changes to take full effect"
    }
}

# -----------------------------------------------------------------------------
#  Configuration: classic right-click context menu (Win10-style)
# -----------------------------------------------------------------------------

function Set-ClassicContextMenu {
    Write-SectionHeader "CLASSIC CONTEXT MENU"

    $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $keyPath   = "$clsidPath\InprocServer32"

    if ($Undo) {
        if (-not (Test-Path $clsidPath)) {
            Write-Skip "Classic context menu key (nothing to undo)"
            return
        }
        if ($DryRun) {
            Write-Info "[dry run] Would remove $clsidPath to restore the Windows 11 context menu"
            return
        }
        Remove-Item -Path $clsidPath -Recurse -Force
        Write-Ok "Windows 11 context menu restored"
        Write-Info "Run 'taskkill /f /im explorer.exe' followed by 'explorer.exe' (or sign out) to apply"
        return
    }

    if (Test-Path $keyPath) {
        Write-Skip "Classic Windows 10-style context menu"
        return
    }

    if ($DryRun) {
        Write-Info "[dry run] Would create $keyPath with an empty default value"
        Write-Info "[dry run] (this restores the full Windows 10-style right-click menu instead of the trimmed Windows 11 one)"
        return
    }

    New-Item -Path $keyPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name "(Default)" -Value "" -Force
    Write-Ok "Classic Windows 10-style context menu enabled"
    Write-Info "Run 'taskkill /f /im explorer.exe' followed by 'explorer.exe' (or sign out) to apply"
    Write-Info "Re-run this script with -Undo to revert"
}

# -----------------------------------------------------------------------------
#  Configuration: SSH keypair
# -----------------------------------------------------------------------------

function New-SshKeypair {
    Write-SectionHeader "SSH KEYPAIR"

    $sshDir  = Join-Path $HOME ".ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"

    if (Test-Path $keyPath) {
        Write-Skip "SSH keypair ($keyPath)"
        return
    }

    if (-not (Test-CommandExists ssh-keygen)) {
        Write-Warn "ssh-keygen not found -- enable the 'OpenSSH Client' optional Windows feature first"
        return
    }

    if ($DryRun) {
        Write-Info "[dry run] Would generate a new ed25519 keypair at $keyPath"
        return
    }

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $comment = $GitEmail
    if ([string]::IsNullOrWhiteSpace($comment) -and -not $Yes) {
        $comment = Read-Host "    Comment/email to label the new SSH key"
    }
    if ([string]::IsNullOrWhiteSpace($comment)) { $comment = "$env:USERNAME@$env:COMPUTERNAME" }

    ssh-keygen -t ed25519 -C $comment -f $keyPath -N '""' | Out-Null
    Write-Ok "SSH keypair generated at $keyPath"
    Write-Info "Public key:"
    Get-Content "$keyPath.pub" | ForEach-Object { Write-Info "  $_" }
}

# -----------------------------------------------------------------------------
#  Catalog  -- everything offered in the selection grid
# -----------------------------------------------------------------------------

function Get-Catalog {
    return @(
        # Core dev baseline
        [PSCustomObject]@{ Name = "Git";                          Category = "Core";          Type = "App";    Id = "Git.Git" }
        [PSCustomObject]@{ Name = "VS Code";                      Category = "Core";          Type = "App";    Id = "Microsoft.VisualStudioCode" }
        [PSCustomObject]@{ Name = "Windows Terminal";             Category = "Core";          Type = "App";    Id = "Microsoft.WindowsTerminal" }
        [PSCustomObject]@{ Name = "PowerShell 7";                 Category = "Core";          Type = "App";    Id = "Microsoft.PowerShell" }
        [PSCustomObject]@{ Name = "7-Zip";                        Category = "Core";          Type = "App";    Id = "7zip.7zip" }
        [PSCustomObject]@{ Name = "Notepad++";                    Category = "Core";          Type = "App";    Id = "Notepad++.Notepad++" }

        # Browsers / platforms / chat
        [PSCustomObject]@{ Name = "Brave";                        Category = "Apps";          Type = "App";    Id = "Brave.Brave" }
        [PSCustomObject]@{ Name = "Steam";                        Category = "Apps";          Type = "App";    Id = "Valve.Steam" }
        [PSCustomObject]@{ Name = "Discord";                      Category = "Apps";          Type = "App";    Id = "Discord.Discord" }
        [PSCustomObject]@{ Name = "Slack";                        Category = "Apps";          Type = "App";    Id = "SlackTechnologies.Slack" }
        [PSCustomObject]@{ Name = "Telegram";                     Category = "Apps";          Type = "App";    Id = "Telegram.TelegramDesktop" }
        [PSCustomObject]@{ Name = "Plex";                         Category = "Apps";          Type = "App";    Id = "Plex.Plex" }
        [PSCustomObject]@{ Name = "Spotify";                      Category = "Apps";          Type = "App";    Id = "Spotify.Spotify" }

        # Creative / peripheral software
        [PSCustomObject]@{ Name = "Adobe Creative Cloud";         Category = "Creative";      Type = "App";    Id = "Adobe.CreativeCloud" }
        [PSCustomObject]@{ Name = "Corsair iCUE";                 Category = "Creative";      Type = "App";    Id = "Corsair.iCUE.5" }
        [PSCustomObject]@{ Name = "Logitech G HUB";               Category = "Creative";      Type = "App";    Id = "Logitech.GHUB" }
        [PSCustomObject]@{ Name = "Focusrite Control";            Category = "Creative";      Type = "App";    Id = "FocusriteAudioEngineeringLtd.FocusriteControl" }
        [PSCustomObject]@{ Name = "SignalRGB";                    Category = "Creative";      Type = "App";    Id = "WhirlwindFX.SignalRgb" }

        # Media tools
        [PSCustomObject]@{ Name = "VLC";                          Category = "Media";         Type = "App";    Id = "VideoLAN.VLC" }
        [PSCustomObject]@{ Name = "OBS Studio";                   Category = "Media";         Type = "App";    Id = "OBSProject.OBSStudio" }
        [PSCustomObject]@{ Name = "paint.net";                    Category = "Media";         Type = "App";    Id = "dotPDN.PaintDotNet" }

        # Networking / remote access
        [PSCustomObject]@{ Name = "Surfshark";                    Category = "Networking";    Type = "App";    Id = "Surfshark.Surfshark" }
        [PSCustomObject]@{ Name = "Tailscale";                    Category = "Networking";    Type = "App";    Id = "Tailscale.Tailscale" }
        [PSCustomObject]@{ Name = "PuTTY";                        Category = "Networking";    Type = "App";    Id = "PuTTY.PuTTY" }
        [PSCustomObject]@{ Name = "WinSCP";                       Category = "Networking";    Type = "App";    Id = "WinSCP.WinSCP" }
        [PSCustomObject]@{ Name = "Wireshark";                    Category = "Networking";    Type = "App";    Id = "WiresharkFoundation.Wireshark" }
        [PSCustomObject]@{ Name = "Nmap";                         Category = "Networking";    Type = "App";    Id = "Insecure.Nmap" }

        # Dev runtimes & tooling
        [PSCustomObject]@{ Name = "Docker Desktop";               Category = "Dev Tools";     Type = "App";    Id = "Docker.DockerDesktop" }
        [PSCustomObject]@{ Name = "Go";                           Category = "Dev Tools";     Type = "App";    Id = "GoLang.Go" }
        [PSCustomObject]@{ Name = "Node.js LTS";                  Category = "Dev Tools";     Type = "App";    Id = "OpenJS.NodeJS.LTS" }
        [PSCustomObject]@{ Name = "Python 3";                     Category = "Dev Tools";     Type = "App";    Id = "Python.Python.3.12" }
        [PSCustomObject]@{ Name = "Eclipse Temurin JDK 17";       Category = "Dev Tools";     Type = "App";    Id = "EclipseAdoptium.Temurin.17.JDK" }
        [PSCustomObject]@{ Name = "DB Browser for SQLite";        Category = "Dev Tools";     Type = "App";    Id = "DBBrowserForSQLite.DBBrowserForSQLite" }
        [PSCustomObject]@{ Name = "Postman";                      Category = "Dev Tools";     Type = "App";    Id = "Postman.Postman" }
        [PSCustomObject]@{ Name = "Windows Subsystem for Linux";  Category = "Dev Tools";     Type = "App";    Id = "Microsoft.WSL" }

        # Configuration
        [PSCustomObject]@{ Name = "Git global config";                 Category = "Configuration"; Type = "Config"; Id = "git-config" }
        [PSCustomObject]@{ Name = "PowerShell profile";                Category = "Configuration"; Type = "Config"; Id = "ps-profile" }
        [PSCustomObject]@{ Name = "Explorer tweaks";                   Category = "Configuration"; Type = "Config"; Id = "explorer-tweaks" }
        [PSCustomObject]@{ Name = "Classic right-click context menu";  Category = "Configuration"; Type = "Config"; Id = "context-menu" }
        [PSCustomObject]@{ Name = "SSH keypair generation";            Category = "Configuration"; Type = "Config"; Id = "ssh-key" }
    )
}

function Invoke-CatalogItem {
    param($Item)

    switch ($Item.Type) {
        "App" {
            Install-WingetApp -Name $Item.Name -Id $Item.Id
        }
        "Config" {
            switch ($Item.Id) {
                "git-config"      { Set-GitConfiguration }
                "ps-profile"      { New-PowerShellProfile }
                "explorer-tweaks" { Set-ExplorerTweaks }
                "context-menu"    { Set-ClassicContextMenu }
                "ssh-key"         { New-SshKeypair }
            }
        }
    }
}

# -----------------------------------------------------------------------------
#  Selection -- Ninite-style "uncheck what you don't want"
# -----------------------------------------------------------------------------

function Show-ConsoleToggleList {
    param([array]$Items)

    $selected = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $Items.Count; $i++) { [void]$selected.Add($i) }

    while ($true) {
        Write-Host ""
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($selected.Contains($i)) { "x" } else { " " }
            Write-Host ("    {0,3}) [{1}] {2,-34} ({3})" -f ($i + 1), $mark, $Items[$i].Name, $Items[$i].Category)
        }
        Write-Host ""
        $reply = Read-Host "    Enter a number to toggle, 'all'/'none' to bulk-select, or 'go' to continue"
        switch -Regex ($reply) {
            '^go$'   { break }
            '^all$'  { for ($i = 0; $i -lt $Items.Count; $i++) { [void]$selected.Add($i) }; continue }
            '^none$' { $selected.Clear(); continue }
            '^\d+$'  {
                $num = [int]$reply
                if ($num -ge 1 -and $num -le $Items.Count) {
                    $idx = $num - 1
                    if ($selected.Contains($idx)) { [void]$selected.Remove($idx) } else { [void]$selected.Add($idx) }
                }
                continue
            }
        }
        if ($reply -eq 'go') { break }
    }

    $result = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($selected.Contains($i)) { $result += $Items[$i] }
    }
    return $result
}

function Select-CatalogItems {
    param([array]$Items)

    if ($Yes) {
        return $Items
    }

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        Write-Info "Opening selection window -- uncheck anything you don't want, then click OK."
        $rows = $Items | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Category = $_.Category } }
        $selectedRows = $rows | Out-GridView -Title "Select items to install / configure (OK = continue, Cancel = select nothing)" -PassThru
        if (-not $selectedRows) {
            return @()
        }
        $selectedNames = @($selectedRows | ForEach-Object { $_.Name })
        return @($Items | Where-Object { $selectedNames -contains $_.Name })
    }

    Write-Warn "Out-GridView is unavailable on this system -- falling back to a console checklist."
    return Show-ConsoleToggleList -Items $Items
}

# -----------------------------------------------------------------------------
#  Main
# -----------------------------------------------------------------------------

function Main {
    if ($Help) {
        Write-Banner
        Show-Usage
        return
    }

    Write-Banner
    Test-Preflight

    if ($Undo) {
        Invoke-Section -Label "Classic context menu (undo)" -Action { Set-ClassicContextMenu }
        Write-Summary
        Write-Done
        return
    }

    $catalog  = Get-Catalog
    $selected = Select-CatalogItems -Items $catalog

    if ($selected.Count -eq 0) {
        Write-Host ""
        Write-Warn "Nothing selected -- exiting."
        return
    }

    Write-SectionHeader "PLAN"
    foreach ($group in ($selected | Group-Object Category)) {
        Write-Info "$($group.Name): $(($group.Group | ForEach-Object { $_.Name }) -join ', ')"
    }

    Write-Host ""
    if (-not (Confirm-Action "Proceed with the above?")) {
        Write-Host ""
        Write-Host "    Aborted." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    foreach ($item in $selected) {
        Invoke-Section -Label $item.Name -Action { param($i) Invoke-CatalogItem -Item $i } -ArgumentList @($item)
    }

    Write-Summary
    Write-Done
}

Main
