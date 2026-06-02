#!/usr/bin/env zsh
set -ue

command echo "Install dotfiles"

# Install Xcode Command Line Tools
xcode_command_line_tools_install() {
  if ! type xcode-select > /dev/null 2>&1; then
    command echo "Install Xcode Command Line Tools"
    xcode-select --install
  fi
}

# Install Homebrew
brew_install() {
  if ! type brew > /dev/null 2>&1; then
    command echo "Install Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Activate brew in the current shell session (post-install PATH is not picked up automatically)
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  if ! type brew > /dev/null 2>&1; then
    command echo "Homebrew install failed"
    exit 1
  fi

  command echo "Install brew packages"
  brew bundle --file=./Brewfile
}

# symbolic link dotfiles to homedir
link_to_homedir() {
  command echo "Backup old dotfiles..."
  if [ ! -d "$HOME/.dotbackup" ];then
    command echo "$HOME/.dotbackup not found. Auto Make it"
    command mkdir "$HOME/.dotbackup"
  fi

  local script_dir="$(cd "$(dirname "${(%):-%x}")" && pwd -P)"
  local dotdir=$(dirname ${script_dir})
  if [[ "$HOME" != "$dotdir" ]];then
    for f in $dotdir/.??*; do
      # ignore files
      [[ `basename $f` == ".DS_Store" ]] && continue
      [[ `basename $f` == ".gitignore" ]] && continue
      [[ `basename $f` == ".git" ]] && continue

      # remove symbolic link
      if [[ -L "$HOME/`basename $f`" ]];then
        command echo "Remove symbolic link $HOME/`basename $f`"
        command rm -f "$HOME/`basename $f`"
      fi

      # backup old dotfiles
      if [[ -e "$HOME/`basename $f`" ]];then
        command echo "Backup $HOME/`basename $f`"
        command mv "$HOME/`basename $f`" "$HOME/.dotbackup"
      fi

      # make directory
      target_dir=$(dirname "$HOME/`basename $f`")
      if [ ! -d "$target_dir" ]; then
        command mkdir -p "$target_dir"
      fi
      # make symbolic link
      command echo "link $f to $HOME"
      command ln -snf $f $HOME
    done

    # Restore .ssh/id_rsa and .ssh/id_rsa.pub from backup
    if [[ -e "$HOME/.dotbackup/.ssh/id_rsa" ]]; then
      command echo "Restore $HOME/.ssh/id_rsa from backup"
      command mv "$HOME/.dotbackup/.ssh/id_rsa" "$HOME/.ssh/id_rsa"
    fi
    if [[ -e "$HOME/.dotbackup/.ssh/id_rsa.pub" ]]; then
      command echo "Restore $HOME/.ssh/id_rsa.pub from backup"
      command mv "$HOME/.dotbackup/.ssh/id_rsa.pub" "$HOME/.ssh/id_rsa.pub"
    fi
  else
    command echo "Same install src dest"
  fi
}

install_mise_plugins() {
  command echo "Install mise plugins"

  if ! type mise > /dev/null 2>&1; then
    command echo "mise is not installed. Please install mise first."
    exit 1
  fi

  local plugins=(
    "java https://github.com/halcyon/asdf-java.git"
    # Add more plugins here
  )

  for plugin in "${plugins[@]}"; do
    local name=$(echo $plugin | awk '{print $1}')
    local url=$(echo $plugin | awk '{print $2}')
    command echo "Install $plugin"
    command mise plugins install $name $url
  done
}

install_helm_schema() {
  command echo "Install helm schema plugin"
  command echo "https://github.com/dadav/helm-schema?tab=readme-ov-file#installation"
  # Check helm is installed
  if ! type helm > /dev/null 2>&1; then
    command echo "helm is not installed. Please install helm first."
    exit 1
  fi
  # Install helm schema plugin
  # --verify=false: dadav/helm-schema does not support plugin verification
  command helm plugin install https://github.com/dadav/helm-schema --verify=false
}

install_sops() {
  command echo "Install sops"
  command echo "https://github.com/getsops/sops?tab=readme-ov-file#1download"
  # Check go is installed
  if ! type go > /dev/null 2>&1; then
    command echo "go is not installed. Please install go first."
    exit 1
  fi
  # Check sops is already installed
  if type sops > /dev/null 2>&1; then
    command echo "sops is already installed."
    exit 0
  fi
  export GOPATH=$(go env GOPATH)
  # Check if GOPATH is set
  if [ -z "$GOPATH" ]; then
    command echo "GOPATH is not set. Please set GOPATH first."
    exit 1
  fi

  command mkdir -p $(go env GOPATH)/src/github.com/getsops/sops/
  command git clone https://github.com/getsops/sops.git $(go env GOPATH)/src/github.com/getsops/sops/
  cd $(go env GOPATH)/src/github.com/getsops/sops/
  command go mod tidy
  command make install
  cd -
}

setup_local_overrides() {
  command echo "Prepare local override files (gitignored)"
  for f in .zshrc.local .zprofile.local; do
    if [ ! -e "$HOME/$f" ]; then
      command echo "Create empty $HOME/$f"
      command touch "$HOME/$f"
    fi
  done
  if [ ! -d "$HOME/.ssh/config.d" ]; then
    command echo "Create $HOME/.ssh/config.d/"
    command mkdir -p "$HOME/.ssh/config.d"
    command chmod 700 "$HOME/.ssh/config.d"
  fi
}

install_npm_globals() {
  command echo "Install npm global packages via mise"

  if ! type mise > /dev/null 2>&1; then
    command echo "mise is not installed. Please install mise first."
    exit 1
  fi

  command echo "Install mise tools (node, etc.) from .config/mise/config.toml"
  command mise install

  local packages=(
    "ccusage"
    "corepack"
  )

  for pkg in "${packages[@]}"; do
    command echo "Install npm package: $pkg"
    command mise exec node -- npm install -g "$pkg"
  done
}

install_claude_code() {
  command echo "Install Claude Code (native install)"
  command echo "https://docs.claude.com/en/docs/claude-code/quickstart"

  if type claude > /dev/null 2>&1; then
    command echo "Claude Code is already installed."
    claude --version
    return 0
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

install_aws_cli() {
  command echo "Install AWS CLI"
  command echo "https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/getting-started-install.html"
  
  # Check if AWS CLI is already installed
  if type aws > /dev/null 2>&1; then
    command echo "AWS CLI is already installed."
    aws --version
    return 0
  fi

  # Install AWS CLI v2 for macOS
  command echo "Downloading AWS CLI v2..."
  curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
  
  command echo "Installing AWS CLI v2..."
  sudo installer -pkg AWSCLIV2.pkg -target /
  
  # Clean up
  command rm -f AWSCLIV2.pkg
  
  # Verify installation
  if type aws > /dev/null 2>&1; then
    command echo "AWS CLI installed successfully!"
    aws --version    
  else
    command echo "AWS CLI installation failed."
    exit 1
  fi
}

setup_docker_cli_plugins() {
  command echo "Setup Docker CLI plugins discovery (buildx, compose)"
  command echo "https://formulae.brew.sh/formula/docker-buildx"

  if ! type brew > /dev/null 2>&1; then
    command echo "brew is not installed. Please install brew first."
    exit 1
  fi
  if ! type jq > /dev/null 2>&1; then
    command echo "jq is not installed. Please install jq first."
    exit 1
  fi

  # brew は buildx/compose を $(brew --prefix)/lib/docker/cli-plugins に置くが
  # docker の既定探索パスに含まれないため、config.json に明示登録する (Intel/ARM 両対応)
  local plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"
  if [ ! -d "$plugin_dir" ]; then
    command echo "Plugin dir not found: $plugin_dir (skip; install docker-buildx/docker-compose via brew first)"
    return 0
  fi

  local config="$HOME/.docker/config.json"
  command mkdir -p "$HOME/.docker"
  if [ ! -f "$config" ]; then
    command echo "{}" > "$config"
  fi

  # cliPluginsExtraDirs へ冪等に追加 (既存の auths 等は保持)。一時ファイルで検証後に置換
  local tmp="$config.tmp.$$"
  if jq --arg dir "$plugin_dir" \
       '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) | if index($dir) then . else . + [$dir] end)' \
       "$config" > "$tmp" && jq empty "$tmp" > /dev/null 2>&1; then
    command mv "$tmp" "$config"
    command echo "Registered $plugin_dir in $config (cliPluginsExtraDirs)"
  else
    command rm -f "$tmp"
    command echo "Failed to update $config"
    exit 1
  fi
}

# 毎週土曜 03:00 に自動再起動する launchd デーモンを登録する (任意実行・要 sudo)
# 副作用が破壊的なため、デフォルトの全体実行には含めずフラグ指定でのみ実行する。
setup_autoreboot() {
  command echo "Setup weekly auto-reboot (Sat 03:00) via launchd"

  local src="./macos/launchd/com.user.autoreboot.plist"
  local dest="/Library/LaunchDaemons/com.user.autoreboot.plist"
  local label="com.user.autoreboot"

  if [ ! -f "$src" ]; then
    command echo "plist source not found: $src (run from the dotfiles repo root)"
    exit 1
  fi

  # symlink は不可: launchd は root:wheel 所有・非ユーザー書込みの実体ファイルのみ受理するため cp する
  command echo "Install $dest (sudo required)"
  command sudo cp "$src" "$dest"
  command sudo chown root:wheel "$dest"
  command sudo chmod 644 "$dest"

  # 冪等化: 既にロード済みなら一旦 bootout してから bootstrap し直す
  if sudo launchctl list | grep -q "$label"; then
    command echo "Reload existing daemon ($label)"
    command sudo launchctl bootout system "$dest" 2>/dev/null || true
  fi
  command sudo launchctl bootstrap system "$dest"

  command echo "Verify:"
  sudo launchctl list | grep "$label" || command echo "(not listed -- check for errors above)"
}

while [ $# -gt 0 ];do
  case ${1} in
    --debug|-d)
      set -uex
      ;;
    --xcode-command-line-tools-install|-X)
      xcode_command_line_tools_install
      exit 0
      ;;
    --brew-install|-b)
      brew_install
      exit 0
      ;;
    --link-to-homedir|-l)
      link_to_homedir
      exit 0
      ;;
    --install-mise-plugins|-m)
      install_mise_plugins
      exit 0
      ;;
    --install-helm-schema|-H)
      install_helm_schema
      exit 0
      ;;
    --install-sops|-S)
      install_sops
      exit 0
      ;;
    --install-aws-cli|-A)
      install_aws_cli
      exit 0
      ;;
    --install-claude-code|-C)
      install_claude_code
      exit 0
      ;;
    --install-npm-globals|-N)
      install_npm_globals
      exit 0
      ;;
    --setup-local-overrides|-L)
      setup_local_overrides
      exit 0
      ;;
    --setup-docker-cli-plugins|-D)
      setup_docker_cli_plugins
      exit 0
      ;;
    --setup-autoreboot|-R)
      setup_autoreboot
      exit 0
      ;;
    *)
      ;;
  esac
  shift
done

xcode_command_line_tools_install
brew_install
link_to_homedir
setup_local_overrides
setup_docker_cli_plugins
install_helm_schema
install_sops
install_mise_plugins
install_aws_cli
install_claude_code
install_npm_globals
command echo "Install completed!!!!"
