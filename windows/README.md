# Windows Setup Script

Windows 10 / 11 setup script for Ryan's machines. Behaves like Ninite — a selection
window pops up listing every app and config tweak (everything checked by default), you
uncheck whatever you don't want, and the script installs/configures the rest.

## Requirements

- Windows 10 or 11
- [winget](https://aka.ms/getwinget) (ships with modern Windows; install "App Installer"
  from the Microsoft Store if it's missing)
- Run from an elevated PowerShell prompt for the smoothest experience — some installs
  (Docker Desktop, WSL) and the Explorer/context-menu tweaks may otherwise prompt for
  elevation mid-run

## Usage

```powershell
# Interactive — opens the selection grid, asks for confirmation
.\ryans-windows-setup.ps1

# Preview exactly what would happen without changing anything
.\ryans-windows-setup.ps1 -DryRun

# Skip the grid and prompts — install/configure everything
.\ryans-windows-setup.ps1 -Yes -GitName "Your Name" -GitEmail "you@example.com"

# Revert the classic-context-menu tweak (back to the Windows 11 menu)
.\ryans-windows-setup.ps1 -Undo
```

If `Out-GridView` isn't available (e.g. Server Core), the script falls back to a
numbered console checklist (`go` to continue, `all`/`none` to bulk-select, a number to
toggle a single item).

## Flags

| Flag | Description |
|---|---|
| `-DryRun` | Print what would happen — no installs, no registry/file changes |
| `-Yes` | Skip the selection grid and confirmation prompt; everything gets installed/configured |
| `-Undo` | Revert reversible config changes (currently just the classic context menu) |
| `-GitName <name>` | Pre-fill the git `user.name` prompt |
| `-GitEmail <email>` | Pre-fill the git `user.email` prompt |
| `-Help` | Show usage |

---

## What's Offered

Everything below appears as a row in the selection grid (all checked by default).
Apps are installed via `winget`; already-installed apps are detected and skipped.

### Core
Git, VS Code, Windows Terminal, PowerShell 7, 7-Zip, Notepad++

### Apps
Brave (default browser), Steam, Discord, Slack, Telegram, Plex, Spotify

### Creative / peripherals
Adobe Creative Cloud, Corsair iCUE, Logitech G HUB, Focusrite Control, SignalRGB

### Media
VLC, OBS Studio, paint.net

### Networking
Surfshark, Tailscale, PuTTY, WinSCP, Wireshark, Nmap

### Dev Tools
Docker Desktop, Go, Node.js LTS, Python 3, Eclipse Temurin JDK 17,
DB Browser for SQLite, Postman, Windows Subsystem for Linux

### Configuration
- **Git global config** — prompts for name/email, sets `core.autocrlf=input`,
  `init.defaultBranch=main`, `pull.rebase=false`, `core.editor="code --wait"`
- **PowerShell profile** — creates `$PROFILE` with a few starter aliases
  (`ll`, `..`, `...`) and PSReadLine prediction tweaks, only if one doesn't exist yet
- **Explorer tweaks** — show hidden files, show file extensions, launch File Explorer
  to "This PC"
- **Classic right-click context menu** — restores the full Windows 10-style context
  menu instead of the trimmed-down Windows 11 one (HKCU registry tweak, fully
  reversible with `-Undo`)
- **SSH keypair generation** — generates a new ed25519 keypair at `~/.ssh/id_ed25519`
  only if one doesn't already exist

## What Is NOT Configured (machine-specific)

These are intentionally left out and must be done per-machine:

- **Steam / Epic / EA / Ubisoft / Rockstar games** — install whatever you actually play
- **Tailscale auth** — run `tailscale up` after install to log in
- **Surfshark / VPN login** — sign in manually
- **Adobe / Creative Cloud apps** — install the specific apps you need from the CC hub
- **Drive mappings, printers, peripherals pairing** — per-machine hardware setup
- **PATH / environment variables for dev runtimes** — winget registers these tools on
  `PATH` itself; set tool-specific variables (`GOPATH`, `JAVA_HOME`, etc.) by hand if
  your workflow needs them, since the right values vary per machine
