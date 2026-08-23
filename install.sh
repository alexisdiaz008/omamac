#!/bin/zsh
set -euo pipefail

if [[ -z "${ZSH_VERSION:-}" ]]; then
  echo "Run with zsh: curl -fsSL https://omamac.org/install | zsh" >&2
  exit 1
fi

install() {
  clear
  echo
  echo " ▄██████▄    ▄▄▄▄███▄▄▄▄      ▄████████   ▄▄▄▄███▄▄▄▄      ▄████████  ▄████████
███    ███ ▄██▀▀▀███▀▀▀██▄   ███    ███ ▄██▀▀▀███▀▀▀██▄   ███    ███ ███    ███
███    ███ ███   ███   ███   ███    ███ ███   ███   ███   ███    ███ ███    █▀
███    ███ ███   ███   ███   ███    ███ ███   ███   ███   ███    ███ ███
███    ███ ███   ███   ███ ▀███████████ ███   ███   ███ ▀███████████ ███
███    ███ ███   ███   ███   ███    ███ ███   ███   ███   ███    ███ ███    █▄
███    ███ ███   ███   ███   ███    ███ ███   ███   ███   ███    ███ ███    ███
 ▀██████▀   ▀█   ███   █▀    ███    █▀   ▀█   ███   █▀    ███    █▀  ████████▀ "


  section() {
    echo -e "\n==> $1"
  }

  formula_present() { brew list --formula "$1" &>/dev/null; }
  cask_present() { brew list --cask "$1" &>/dev/null; }

  ensure_formula() {
    local pkg="$1"
    if formula_present "$pkg"; then
      echo "✓ $pkg (already installed)"
      return
    fi
    echo "Installing $pkg..."
    brew install "$pkg"
  }

  ensure_cask() {
    local cask="$1"
    if cask_present "$cask"; then
      echo "✓ $cask (already installed)"
      return
    fi
    echo "Installing $cask..."
    brew install --cask "$cask"
  }

  open_if_present() {
    local app="$1"
    if [[ -d "/Applications/${app}.app" ]] || [[ -d "$HOME/Applications/${app}.app" ]]; then
      open -a "$app"
    else
      echo "Skipping open: $app not found"
    fi
  }

  section "Permission needed for setup..."
  sudo echo "✓ Granted"

  # Install all packages from Brew
  if ! command -v brew &> /dev/null; then
    section "Installing brew..."
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    ensure_formula git
  fi

  # Clone
  REPO="https://github.com/omacom-io/omamac.git"
  INSTALLER_DIR="$(mktemp -d)"
  trap 'rm -rf "$INSTALLER_DIR"' EXIT

  section "Cloning..."
  git clone --depth 1 "$REPO" "$INSTALLER_DIR"

  section "Installing packages..."
  packages=(tmux mise nvim opencode lazygit lazydocker starship zoxide eza jq gum gh libyaml)
  for pkg in $packages; do ensure_formula "$pkg"; done

  # Install Alacritty manually from GitHub releases
  section "Installing Alacritty..."
  . "$INSTALLER_DIR/install/alacritty.sh"

  # Install Omadots
  curl -fsSL https://raw.githubusercontent.com/omacom-io/omadots/refs/heads/master/install.sh | zsh

  section "Configuring brew init..."
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>"$HOME/.config/shell/inits"
  echo "✓ Zsh"

  # Install secondary apps
  section "Installing apps..."
  casks=(rectangle-pro hammerspoon font-jetbrains-mono-nerd-font docker-desktop google-chrome claude-code raycast)
  for cask in $casks; do ensure_cask "$cask"; done

  # Install optional apps
  section "Installing optional apps..."
  ensure_formula gum
  selected_apps=$(gum choose --no-limit --height=11 \
    --selected="1password" --selected="dropbox" --selected="spotify" \
    --selected="signal" --selected="whatsapp" --selected="obsidian" \
    --selected="zoom" --selected="localsend" --selected="tailscale" \
    "1password" "dropbox" "spotify" "signal" "whatsapp" "obsidian" "zoom" "localsend" "lm-studio" "tailscale")
  while IFS= read -r app; do
    [[ -n "$app" ]] && ensure_cask "$app" || true
  done <<< "$selected_apps"

  # Install dev environments
  section "Installing dev environments..."
  ensure_formula gum
  ensure_formula mise
  selected_langs=$(gum choose --no-limit --height=15 \
    --selected="node" --selected="ruby" \
    "node" "ruby" "python" "go" "rust" "java" "php" "elixir" "erlang" "scala" "kotlin" "deno" "bun")
  while IFS= read -r lang; do
    [[ -n "$lang" ]] && mise use -g "$lang" || true
  done <<< "$selected_langs"

  # Omamac configs
  section "Configuring Mac..."
  mkdir -p "$HOME/.config"
  cp -Rf "$INSTALLER_DIR/config/"* "$HOME/.config/"
  for dir in "$INSTALLER_DIR/config"/*/; do
    echo "✓ $(basename "$dir")"
  done

  # Create hush file to suppress "Last login" message
  touch "$HOME/.hushlogin"
  echo "✓ Hush login"

  . "$INSTALLER_DIR/install/mac.sh"
  echo "✓ Settings"

  # Correct hammerspoon config location
  ensure_cask hammerspoon
  defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HOME/.config/hammerspoon/init.lua"

  # Done!
  section "Finished!"
  echo "1. You must manually create the nine default workspaces with F3"
  echo "2. Manually disable all Keyboard Shortcuts for Windows + Spotlight + Mission Control"
  echo "3. Manually enable 'Switch to Desktop' Keyboard Shortcuts on CMD-[1-9]"
  echo "4. Manually import Rectangle Pro config from ~/.config/rectangle/RectangleProConfig.json (reveal hidden with Cmd + Shift + . in Finder)"
  echo "5. Manually import Raycast config from ~/.config/raycast/Raycast.rayconfig with pw: 12345678"
  echo "6. Remember to authenticate with: gh auth login"
  echo "7. Then logout and back in for everything to take effect (Cmd + Shift + Q)"

  ensure_cask hammerspoon || true
  ensure_cask rectangle-pro || true
  ensure_cask raycast || true
  ensure_cask tailscale || true

  open_if_present "Hammerspoon"
  open_if_present "Rectangle Pro"
  open_if_present "Raycast"
  open_if_present "Tailscale"
}

# Must use a function to prevent brew installs from stealing stdin
install
