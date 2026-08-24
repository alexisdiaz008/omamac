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
  app_present() {
    local app="$1"
    [[ -d "/Applications/${app}.app" ]] || [[ -d "$HOME/Applications/${app}.app" ]]
  }

  ensure_formula() {
    local pkg="$1"
    if formula_present "$pkg"; then
      echo "Upgrading $pkg..."
      brew upgrade --formula "$pkg" || true
      echo "✓ $pkg"
      return
    fi
    echo "Installing $pkg..."
    brew install "$pkg"
  }

  ensure_cask() {
    local cask="$1"
    if cask_present "$cask"; then
      echo "Upgrading $cask..."
      brew upgrade --cask "$cask" || true
      echo "✓ $cask"
      return
    fi
    echo "Installing $cask..."
    # --adopt takes over an existing .app (e.g. Chrome installed from google.com)
    brew install --cask --adopt "$cask"
  }

  open_if_present() {
    local app="$1"
    if app_present "$app"; then
      open -a "$app"
    else
      echo "Skipping open: $app not found"
    fi
  }

  omadots_present() {
    [[ -f "$HOME/.config/shell/all" ]] && grep -qF 'source ~/.config/shell/all' "$HOME/.zshrc" 2>/dev/null
  }

  lang_present() {
    local lang="$1"
    mise ls 2>/dev/null | awk '{print $1}' | grep -qx "$lang"
  }

  section "Permission needed for setup..."
  sudo echo "✓ Granted"

  # Install all packages from Brew
  if ! command -v brew &> /dev/null; then
    section "Installing brew..."
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  fi

  section "Updating brew..."
  brew update

  if ! command -v git &> /dev/null; then
    ensure_formula git
  fi

  # Clone
  REPO="https://github.com/alexisdiaz008/omamac.git"
  INSTALLER_DIR="$(mktemp -d)"
  trap 'rm -rf "$INSTALLER_DIR"' EXIT

  section "Cloning..."
  git clone --depth 1 "$REPO" "$INSTALLER_DIR"

  section "Installing packages..."
  packages=(tmux mise nvim opencode lazygit lazydocker starship zoxide eza jq gum gh libyaml zsh-autosuggestions zsh-fast-syntax-highlighting zsh-autocomplete)
  for pkg in $packages; do ensure_formula "$pkg"; done

  # Install Alacritty manually from GitHub releases (skips if already present)
  section "Installing Alacritty..."
  . "$INSTALLER_DIR/install/alacritty.sh"

  # Install Omadots (destructive: wipes nvim, overwrites .zshrc) — skip on rerun
  if omadots_present; then
    section "Omadots (already installed)"
    echo "✓ Skipping Omadots"
  else
    section "Installing Omadots..."
    curl -fsSL https://raw.githubusercontent.com/omacom-io/omadots/refs/heads/master/install.sh | zsh
  fi

  section "Configuring brew init..."
  mkdir -p "$HOME/.config/shell"
  touch "$HOME/.config/shell/inits"
  if ! grep -qF 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$HOME/.config/shell/inits" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>"$HOME/.config/shell/inits"
    echo "✓ Brew init"
  else
    echo "✓ Brew init (already configured)"
  fi

  # Install secondary apps
  section "Installing apps..."
  casks=(rectangle-pro hammerspoon font-jetbrains-mono-nerd-font docker-desktop google-chrome claude-code raycast)
  for cask in $casks; do
    # Docker.app is often installed from docker.com, not Homebrew
    if [[ "$cask" == "docker-desktop" ]] && app_present Docker; then
      echo "✓ docker-desktop (already installed)"
      continue
    fi
    ensure_cask "$cask"
  done

  # Install optional apps — upgrade present, gum only for missing
  section "Installing optional apps..."
  ensure_formula gum
  optional_apps=(1password dropbox spotify signal whatsapp obsidian zoom localsend lm-studio tailscale)
  optional_defaults=(1password dropbox spotify signal whatsapp obsidian zoom localsend tailscale)

  for app in $optional_apps; do
    if cask_present "$app"; then
      ensure_cask "$app"
    fi
  done

  missing_apps=()
  gum_selected_flags=()
  for app in $optional_apps; do
    if ! cask_present "$app"; then
      missing_apps+=("$app")
      if (( ${optional_defaults[(Ie)$app]} )); then
        gum_selected_flags+=(--selected="$app")
      fi
    fi
  done

  if (( ${#missing_apps[@]} > 0 )); then
    selected_apps=$(gum choose --no-limit --height=11 \
      "${gum_selected_flags[@]}" \
      "${missing_apps[@]}")
    while IFS= read -r app; do
      [[ -n "$app" ]] && ensure_cask "$app" || true
    done <<< "$selected_apps"
  else
    echo "✓ All optional apps already installed"
  fi

  # Install dev environments — upgrade present langs, gum only for missing
  section "Installing dev environments..."
  ensure_formula gum
  ensure_formula mise
  optional_langs=(node ruby python go rust java php elixir erlang scala kotlin deno bun)
  lang_defaults=(node ruby)

  for lang in $optional_langs; do
    if lang_present "$lang"; then
      echo "Upgrading $lang..."
      mise upgrade "$lang" || mise install "$lang" || true
      echo "✓ $lang"
    fi
  done

  missing_langs=()
  lang_selected_flags=()
  for lang in $optional_langs; do
    if ! lang_present "$lang"; then
      missing_langs+=("$lang")
      if (( ${lang_defaults[(Ie)$lang]} )); then
        lang_selected_flags+=(--selected="$lang")
      fi
    fi
  done

  if (( ${#missing_langs[@]} > 0 )); then
    selected_langs=$(gum choose --no-limit --height=15 \
      "${lang_selected_flags[@]}" \
      "${missing_langs[@]}")
    while IFS= read -r lang; do
      [[ -n "$lang" ]] && mise use -g "$lang" || true
    done <<< "$selected_langs"
  else
    echo "✓ All optional languages already installed"
  fi

  # Omamac configs
  section "Configuring Mac..."
  mkdir -p "$HOME/.config"
  cp -Rf "$INSTALLER_DIR/config/"* "$HOME/.config/"
  for dir in "$INSTALLER_DIR/config"/*/; do
    echo "✓ $(basename "$dir")"
  done

  # Hook zsh plugins after Omadots overwrites .zshrc
  section "Configuring zsh plugins..."
  if ! grep -qF 'source ~/.config/shell/plugins' "$HOME/.zshrc" 2>/dev/null; then
    cat >>"$HOME/.zshrc" <<'EOF'

# Omamac zsh plugins
source ~/.config/shell/plugins
EOF
  fi
  echo "✓ Zsh plugins"

  # Create hush file to suppress "Last login" message
  touch "$HOME/.hushlogin"
  echo "✓ Hush login"

  . "$INSTALLER_DIR/install/mac.sh"
  echo "✓ Settings"

  # Correct hammerspoon config location (cask already ensured above)
  defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HOME/.config/hammerspoon/init.lua"

  # Done!
  section "Finished!"
  echo "1. You must manually create the nine default workspaces with F3"
  echo "2. Manually disable all Keyboard Shortcuts for Windows + Spotlight + Mission Control"
  echo "3. Manually enable 'Switch to Desktop' Keyboard Shortcuts on CTRL-[1-9]"
  echo "4. Disable Accessibility Zoom shortcuts (Option+Command+/-) so Rectangle Pro can use Cmd+Option+/-"
  echo "5. Manually import Rectangle Pro config from ~/.config/rectangle/RectangleProConfig.json (reveal hidden with Cmd + Shift + . in Finder)"
  echo "6. Manually import Raycast config from ~/.config/raycast/Raycast.rayconfig with pw: 12345678"
  echo "7. Remember to authenticate with: gh auth login"
  echo "8. Then logout and back in for everything to take effect (Cmd + Shift + Q)"

  cask_present hammerspoon || ensure_cask hammerspoon || true
  cask_present rectangle-pro || ensure_cask rectangle-pro || true
  cask_present raycast || ensure_cask raycast || true
  cask_present tailscale || ensure_cask tailscale || true

  open_if_present "Hammerspoon"
  open_if_present "Rectangle Pro"
  open_if_present "Raycast"
  open_if_present "Tailscale"
}

# Must use a function to prevent brew installs from stealing stdin
install
