#!/usr/bin/env bash
# =============================================================================
#  Ryan's Linux Setup Script
#  Target:  Ubuntu 22.04+ / Debian-based
#  Usage:   ./ryans-linux-setup.sh [--headless|--desktop] [OPTIONS]
# =============================================================================
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';   BOLD='\033[1m'
DIM='\033[2m';     NC='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────────
MODE="desktop"          # desktop | headless
OPT_XRDP=false
OPT_OPENVPN=false
OPT_GITLAB_RUNNER=false
OPT_PLEX=false
OPT_YES=false
GIT_NAME=""
GIT_EMAIL=""
PASSED=()
FAILED=()
SKIPPED=()  # sections skipped because they were already installed

# ─────────────────────────────────────────────────────────────────────────────
#  Art & UI helpers
# ─────────────────────────────────────────────────────────────────────────────

print_banner() {
  [[ -t 1 ]] && clear
  echo -e "${CYAN}${BOLD}"
  cat <<'EOF'
  ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗
  ██╔══██╗╚██╗ ██╔╝██╔══██╗████╗  ██║
  ██████╔╝ ╚████╔╝ ███████║██╔██╗ ██║
  ██╔══██╗  ╚██╔╝  ██╔══██║██║╚██╗██║
  ██║  ██║   ██║   ██║  ██║██║ ╚████║
  ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝
EOF
  echo -e "${NC}${BOLD}${BLUE}"
  cat <<'EOF'
  ┌─────────────────────────────────────────────────────┐
  │         L I N U X   S E T U P   S C R I P T        │
  │              Ubuntu / Debian  •  v1.0               │
  └─────────────────────────────────────────────────────┘
EOF
  echo -e "${NC}"
}

print_summary() {
  section "RESULTS"
  echo
  for s in "${PASSED[@]+"${PASSED[@]}"}"; do
    echo -e "    ${GREEN}✓${NC}  $s"
  done
  for s in "${SKIPPED[@]+"${SKIPPED[@]}"}"; do
    echo -e "    ${DIM}–  $s (already installed)${NC}"
  done
  if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo
    for s in "${FAILED[@]}"; do
      echo -e "    ${RED}✗${NC}  $s"
    done
    echo
    warn "${#FAILED[@]} section(s) failed. Scroll up to see the errors, then re-run those steps manually."
  else
    echo
    ok "All sections completed successfully."
  fi
}

print_done() {
  echo
  if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}"
    cat <<'EOF'
         .---.
        |o_o |
        |:_/ |         ╔═══════════════════════════════╗
       //   \ \        ║                               ║
      (|     | )       ║   ✓  All done!                ║
     /'\_   _/`\       ║      Happy hacking, Ryan.     ║
     \___)=(___/       ╚═══════════════════════════════╝
EOF
  else
    echo -e "${YELLOW}${BOLD}"
    cat <<'EOF'
         .---.
        |o_o |
        |:_/ |         ╔═══════════════════════════════╗
       //   \ \        ║                               ║
      (|     | )       ║   ⚠  Finished with errors.   ║
     /'\_   _/`\       ║      Check the summary above. ║
     \___)=(___/       ╚═══════════════════════════════╝
EOF
  fi
  echo -e "${NC}"
}

section() {
  echo
  echo -e "${CYAN}${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}    ▸  $1${NC}"
  echo -e "${CYAN}${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

step()  { echo -e "    ${GREEN}▶${NC}  $*"; }
ok()    { echo -e "    ${GREEN}✓${NC}  $*"; }
info()  { echo -e "    ${BLUE}●${NC}  $*"; }
warn()  { echo -e "    ${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "    ${RED}✗${NC}  $*" >&2; }
skip()  { echo -e "    ${DIM}–  $* (already installed)${NC}"; }

bool_str() {
  [[ "$1" == true ]] && echo -e "${GREEN}yes${NC}" || echo -e "${DIM}no${NC}"
}

confirm() {
  [[ "$OPT_YES" == true ]] && return 0
  echo -en "    ${YELLOW}?${NC}  $1 [y/N] "
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

need_apt() {
  # Refresh only once per run
  if [[ "${_APT_UPDATED:-false}" != true ]]; then
    step "Updating apt package lists..."
    sudo apt-get update -qq
    _APT_UPDATED=true
  fi
}

apt_install() {
  need_apt
  sudo apt-get install -y "$@"
}

snap_install() {
  local name="$1"; shift
  if snap list "$name" &>/dev/null 2>&1; then
    skip "snap: $name"
  else
    step "Installing snap: $name..."
    sudo snap install "$name" "$@"
    ok "$name installed"
  fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# Run an install function, catch failures, and keep going.
# With set -e, calling a function inside `if` suppresses errexit for that call,
# so a failure returns non-zero instead of killing the script.
run_section() {
  local label="$1"; shift
  if "$@"; then
    PASSED+=("$label")
  else
    echo
    err "$label failed — skipping, see output above"
    FAILED+=("$label")
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Arg parsing
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF

Usage: $(basename "$0") [MODE] [OPTIONS]

Modes (default: --desktop):
  --desktop         Full desktop install with GUI apps and snaps
  --headless        Server/headless install — no GUI apps or snaps

Options:
  --xrdp            Install xRDP remote desktop server
  --openvpn         Install OpenVPN + NetworkManager plugin
  --gitlab-runner   Install GitLab Runner binary (does NOT register it)
  --plex            Install Plex Desktop snap (desktop mode only)
  -y, --yes         Skip all confirmation prompts

  -h, --help        Show this message

Examples:
  ./$(basename "$0") --desktop --plex
  ./$(basename "$0") --headless --xrdp --gitlab-runner -y

EOF
}

_ARGC=$#   # capture before the loop — used in main to decide wizard vs. args

for arg in "$@"; do
  case "$arg" in
    --desktop)       MODE="desktop" ;;
    --headless)      MODE="headless" ;;
    --xrdp)          OPT_XRDP=true ;;
    --openvpn)       OPT_OPENVPN=true ;;
    --gitlab-runner) OPT_GITLAB_RUNNER=true ;;
    --plex)          OPT_PLEX=true ;;
    -y|--yes)        OPT_YES=true ;;
    -h|--help)       print_banner; usage; exit 0 ;;
    *) echo -e "\n  ${RED}Unknown option: $arg${NC}"; usage; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
#  Preflight checks
# ─────────────────────────────────────────────────────────────────────────────

preflight() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    err "This script only runs on Linux. Exiting."
    exit 1
  fi

  if ! cmd_exists apt-get; then
    err "apt-get not found. This script requires an Ubuntu/Debian-based system."
    exit 1
  fi

  if [[ "$EUID" -eq 0 ]]; then
    warn "Running as root. Docker group membership won't apply until you re-login as a regular user."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Base packages  (headless + desktop)
# ─────────────────────────────────────────────────────────────────────────────

install_base() {
  section "BASE PACKAGES"

  step "Installing core tools..."
  apt_install \
    build-essential gcc g++ gdb make \
    git curl wget rsync pv \
    jq htop zip unzip \
    ffmpeg \
    golang-go \
    nodejs npm \
    openssh-server \
    ufw \
    bpfcc-tools bpftrace strace tcpdump \
    lm-sensors sysstat lshw \
    netcat-openbsd

  ok "Base packages installed"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Docker
# ─────────────────────────────────────────────────────────────────────────────

install_docker() {
  section "DOCKER"

  if cmd_exists docker; then
    skip "Docker ($(docker --version | awk '{print $3}' | tr -d ','))"
    return
  fi

  # Detect distro — Docker hosts separate repos for ubuntu vs debian
  local distro codename
  distro=$(. /etc/os-release && echo "$ID")
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")

  if [[ "$distro" != "ubuntu" && "$distro" != "debian" ]]; then
    err "Docker auto-install only supports Ubuntu and Debian (detected: $distro)."
    err "Install Docker manually: https://docs.docker.com/engine/install/"
    return 1
  fi

  step "Adding Docker GPG key ($distro/$codename)..."
  apt_install ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  step "Adding Docker apt repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/${distro} ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq

  step "Installing Docker CE..."
  sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  step "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"

  ok "Docker installed — re-login to use docker without sudo"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Tailscale
# ─────────────────────────────────────────────────────────────────────────────

install_tailscale() {
  section "TAILSCALE"

  if cmd_exists tailscale; then
    skip "Tailscale"
    return
  fi

  step "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale installed"
  info "Run: sudo tailscale up    to authenticate this machine"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Desktop apps  (skipped in --headless)
# ─────────────────────────────────────────────────────────────────────────────

install_desktop() {
  section "DESKTOP APPS"

  step "Installing apt desktop packages..."
  apt_install gufw obs-studio vlc

  if ! dpkg -l discord &>/dev/null 2>&1; then
    step "Installing Discord (snap)..."
    snap_install discord
  else
    skip "Discord"
  fi

  snap_install brave
  snap_install code --classic
  snap_install spotify

  if [[ "$OPT_PLEX" == true ]]; then
    snap_install plex-desktop
  fi

  ok "Desktop apps installed"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Claude Code
# ─────────────────────────────────────────────────────────────────────────────

install_claude_code() {
  section "CLAUDE CODE"

  if cmd_exists claude; then
    skip "Claude Code"
    return
  fi

  step "Installing Claude Code via npm..."
  sudo npm install -g @anthropic-ai/claude-code
  ok "Claude Code installed — run 'claude' to get started"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Optional: xRDP
# ─────────────────────────────────────────────────────────────────────────────

install_xrdp() {
  section "XRDP  (Remote Desktop)"

  if cmd_exists xrdp; then
    skip "xRDP"
    return
  fi

  step "Installing xRDP..."
  apt_install xrdp xorgxrdp
  sudo systemctl enable xrdp
  sudo ufw allow 3389/tcp comment "xRDP"
  ok "xRDP installed and enabled on port 3389"
  warn "Configure /etc/xrdp/xrdp.ini for security hardening if exposed externally"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Optional: OpenVPN
# ─────────────────────────────────────────────────────────────────────────────

install_openvpn() {
  section "OPENVPN"

  if cmd_exists openvpn; then
    skip "OpenVPN"
    return
  fi

  step "Installing OpenVPN and NetworkManager plugin..."
  apt_install openvpn network-manager-openvpn network-manager-openvpn-gnome
  ok "OpenVPN installed"
  info "Import your .ovpn config via NetworkManager or: sudo openvpn --config <file>"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Optional: GitLab Runner  (install only — does NOT register)
# ─────────────────────────────────────────────────────────────────────────────

install_gitlab_runner() {
  section "GITLAB RUNNER"

  if cmd_exists gitlab-runner; then
    skip "GitLab Runner"
    return
  fi

  step "Adding GitLab Runner apt repository..."
  curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
    | sudo bash

  step "Installing GitLab Runner..."
  apt_install gitlab-runner

  ok "GitLab Runner installed"
  warn "Runner is NOT registered. Run the following to register it:"
  info "  sudo gitlab-runner register"
}

# ─────────────────────────────────────────────────────────────────────────────
#  System configuration  (git, PATH, UFW rules)
# ─────────────────────────────────────────────────────────────────────────────

configure_system() {
  section "SYSTEM CONFIGURATION"

  # ── Git ──────────────────────────────────────────────────────────────────
  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    if [[ "$OPT_YES" == true ]]; then
      warn "Skipping git config — rerun without -y or set manually:"
      info "  git config --global user.name  \"Your Name\""
      info "  git config --global user.email \"you@example.com\""
    else
      section "GIT CONFIGURATION"
      echo
      echo -en "    ${BLUE}?${NC}  Git name:   "
      read -r GIT_NAME
      echo -en "    ${BLUE}?${NC}  Git email:  "
      read -r GIT_EMAIL
      echo
    fi
  fi

  if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
    step "Configuring git globals..."
    git config --global user.name          "$GIT_NAME"
    git config --global user.email         "$GIT_EMAIL"
    git config --global core.editor        "code --wait"
    git config --global init.defaultBranch main
    git config --global pull.rebase        false
    ok "Git configured for ${BOLD}${GIT_NAME}${NC} <${GIT_EMAIL}>"
  fi

  # ── PATH entries ─────────────────────────────────────────────────────────
  step "Adding PATH entries to ~/.bashrc..."
  local bashrc="$HOME/.bashrc"
  grep -qF '/usr/local/go/bin'  "$bashrc" || \
    echo 'export PATH=$PATH:/usr/local/go/bin'    >> "$bashrc"
  grep -qF '$HOME/.local/bin'   "$bashrc" || \
    echo 'export PATH="$HOME/.local/bin:$PATH"'   >> "$bashrc"
  ok "PATH entries added"

  # ── UFW ──────────────────────────────────────────────────────────────────
  step "Configuring UFW firewall..."
  sudo ufw default deny incoming  > /dev/null
  sudo ufw default allow outgoing > /dev/null
  sudo ufw allow ssh comment "SSH" > /dev/null
  sudo ufw --force enable          > /dev/null
  ok "UFW enabled — SSH allowed, all inbound denied by default"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Interactive wizard  (runs when no args are passed)
# ─────────────────────────────────────────────────────────────────────────────

ask_yn() {
  # Usage: ask_yn "Question text?" && VAR=true || true
  echo -en "    ${BLUE}?${NC}  $1  ${DIM}[y/N]${NC} "
  read -r _reply
  [[ "${_reply:-n}" =~ ^[Yy]$ ]]
}

run_wizard() {
  section "SETUP WIZARD"
  echo
  echo -e "    What kind of machine is this?\n"
  echo -e "    ${CYAN}1)${NC}  Desktop  — GUI apps, browsers, media tools"
  echo -e "    ${CYAN}2)${NC}  Headless — Server / no monitor"
  echo
  echo -en "    ${YELLOW}?${NC}  Choice [1]: "
  read -r _choice
  case "${_choice:-1}" in
    2) MODE="headless" ;;
    *) MODE="desktop" ;;
  esac
  ok "Mode set to: ${BOLD}${MODE}${NC}"

  echo
  section "OPTIONAL COMPONENTS"
  echo

  if ask_yn "Install xRDP remote desktop server?";    then OPT_XRDP=true;          fi
  if ask_yn "Install OpenVPN + NetworkManager plugin?"; then OPT_OPENVPN=true;      fi
  if ask_yn "Install GitLab Runner (binary only)?";   then OPT_GITLAB_RUNNER=true;  fi

  if [[ "$MODE" == "desktop" ]]; then
    if ask_yn "Install Plex Desktop?";                then OPT_PLEX=true;           fi
  fi

  echo
  section "GIT CONFIGURATION"
  echo
  echo -en "    ${BLUE}?${NC}  Git name:   "
  read -r GIT_NAME
  echo -en "    ${BLUE}?${NC}  Git email:  "
  read -r GIT_EMAIL
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  print_banner
  preflight

  [[ "$_ARGC" -eq 0 ]] && run_wizard

  # ── Summary ────────────────────────────────────────────────────────────────
  section "INSTALL PLAN"
  info  "Mode:             ${BOLD}${MODE}${NC}"
  echo
  info  "Always installed:"
  echo  "              base packages, docker, tailscale,"
  echo  "              git config, PATH, UFW, claude code"
  echo
  if [[ "$MODE" == "desktop" ]]; then
    info "Desktop extras:   brave, VS Code, obs-studio, vlc, spotify, discord"
    [[ "$OPT_PLEX" == true ]] && \
    info "                  plex-desktop"
  fi
  info  "xRDP:             $(bool_str $OPT_XRDP)"
  info  "OpenVPN:          $(bool_str $OPT_OPENVPN)"
  info  "GitLab Runner:    $(bool_str $OPT_GITLAB_RUNNER)"

  echo
  confirm "Proceed?" || { echo -e "\n  ${DIM}Aborted.${NC}\n"; exit 0; }

  # ── Run ────────────────────────────────────────────────────────────────────
  run_section "Base packages"   install_base
  run_section "Docker"          install_docker
  run_section "Tailscale"       install_tailscale

  if [[ "$MODE" == "desktop" ]];         then run_section "Desktop apps"   install_desktop;        fi
  if [[ "$OPT_XRDP"          == true ]]; then run_section "xRDP"           install_xrdp;           fi
  if [[ "$OPT_OPENVPN"       == true ]]; then run_section "OpenVPN"        install_openvpn;        fi
  if [[ "$OPT_GITLAB_RUNNER" == true ]]; then run_section "GitLab Runner"  install_gitlab_runner;  fi

  run_section "System config"   configure_system
  run_section "Claude Code"     install_claude_code

  print_summary
  print_done
}

main
