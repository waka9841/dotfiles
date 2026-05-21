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
  command helm plugin install https://github.com/dadav/helm-schema
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
    --setup-local-overrides|-L)
      setup_local_overrides
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
install_helm_schema
install_sops
install_mise_plugins
install_aws_cli
command echo "Install completed!!!!"
