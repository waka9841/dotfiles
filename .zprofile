#### Added by Toolbox App ####
export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
#### Added by Toolbox App ####

#### Homebrew ####
if [ -f /opt/homebrew/bin/brew ]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
	eval "$(/usr/local/bin/brew shellenv)"
else
	echo "Error: Homebrew not found."
fi
#### Homebrew ####

#### pyenv ####
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
#### pyenv ####

#### poetry ####
export PATH="$HOME/.local/bin:$PATH"
#### poetry ####

#### direnv ####
eval "$(direnv hook zsh)"
#### direnv ####

#### lima ####
# export TESTCONTAINERS_HOST_OVERRIDE=$(limactl shell lima ip a show lima0 | grep 'inet '| awk '{print $2}' | cut -f1 -d"/")
# export TESTCONTAINERS_HOST_OVERRIDE='127.0.0.1'
# export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE='/var/run/docker.sock'
# export DOCKER_HOST=$(limactl list docker --format 'unix://{{.Dir}}/sock/docker.sock')
# export DOCKER_BUILDKIT=1
#### lima ####

#### wezterm ####
export WEZTERM_CONFIG_FILE="$HOME/.config/wezterm/wezterm.lua"
#### wezterm ####

#### k9s iterm2 ####
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.config"
#### k9s iterm2 ####

#### golang ####
export GOPATH=$(go env GOPATH)
export PATH=$PATH:$GOPATH/bin
#### golang ####

#### sops ####
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
#### sops ####

# Local overrides (not tracked in this repo)
[ -f "$HOME/.zprofile.local" ] && source "$HOME/.zprofile.local"
