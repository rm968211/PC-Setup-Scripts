# Linux Setup Script

Ubuntu / Debian setup script for Ryan's machines. Supports both desktop and headless (server) installs, with optional components selectable via flags or an interactive wizard.

## Usage

```bash
chmod +x ryans-linux-setup.sh

# Interactive wizard (no args)
./ryans-linux-setup.sh

# Desktop machine
./ryans-linux-setup.sh --desktop

# Headless / server
./ryans-linux-setup.sh --headless

# With optional components
./ryans-linux-setup.sh --desktop --xrdp --plex

# Fully automated (no prompts)
./ryans-linux-setup.sh --headless --gitlab-runner -y
```

## Modes

| Flag | Description |
|---|---|
| `--desktop` | Full install including GUI apps and snaps (default) |
| `--headless` | Base tools only — no GUI apps, no snaps |

## Optional Flags

| Flag | What it installs |
|---|---|
| `--xrdp` | xRDP remote desktop server (port 3389) |
| `--openvpn` | OpenVPN + NetworkManager plugin |
| `--gitlab-runner` | GitLab Runner binary (not registered — do that manually) |
| `--plex` | Plex Desktop snap (desktop mode only) |
| `-y` / `--yes` | Skip all confirmation prompts |

---

## What Gets Installed

### Base — both modes

**apt packages**
- `build-essential`, `gcc`, `g++`, `gdb`, `make`
- `git`, `curl`, `wget`, `rsync`, `pv`
- `jq`, `htop`, `zip`, `unzip`
- `ffmpeg`
- `golang-go`
- `nodejs`, `npm`
- `openssh-server`
- `ufw`
- `bpfcc-tools`, `bpftrace`, `strace`, `tcpdump`
- `lm-sensors`, `sysstat`, `lshw`
- `netcat-openbsd`

**Other**
- Docker CE (via official Docker apt repo) + `docker-compose-plugin`, `docker-buildx-plugin`
- Tailscale (via official install script)
- Claude Code (via npm)

---

### Desktop — additional

**apt packages**
- `obs-studio`
- `vlc`
- `gufw`

**snaps**
- `brave` (browser)
- `code` (VS Code, classic)
- `spotify`
- `discord`
- `plex-desktop` _(if `--plex` passed)_

---

### Optional components

**xRDP** (`--xrdp`)
- Installs `xrdp`, `xorgxrdp`
- Enables the service
- Opens UFW port 3389

**OpenVPN** (`--openvpn`)
- Installs `openvpn`, `network-manager-openvpn`, `network-manager-openvpn-gnome`
- `.ovpn` configs imported manually via NetworkManager

**GitLab Runner** (`--gitlab-runner`)
- Installs the `gitlab-runner` binary via GitLab's apt repo
- Does **not** register it — run `sudo gitlab-runner register` per-machine

---

## What Gets Configured

| Setting | Value |
|---|---|
| `git user.name` | `rm968211` |
| `git user.email` | `rdmiers@gmail.com` |
| `git core.editor` | `code --wait` |
| `git init.defaultBranch` | `main` |
| `git pull.rebase` | `false` |
| `~/.bashrc` PATH | Adds `/usr/local/go/bin` and `~/.local/bin` |
| UFW | Enabled — deny inbound, allow outbound, SSH open |

## What Is NOT Configured (machine-specific)

These are intentionally left out and must be done per-machine:

- **Tailscale auth** — run `sudo tailscale up` after install
- **SSH keys** — generate or copy manually
- **Drive mounts** (`/etc/fstab`) — UUIDs are per-machine
- **Docker DNS** — configure `/etc/docker/daemon.json` if needed
- **GitLab Runner registration** — run `sudo gitlab-runner register` with the repo token
- **xRDP security hardening** — edit `/etc/xrdp/xrdp.ini` based on network exposure
