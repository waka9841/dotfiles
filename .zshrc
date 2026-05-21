autoload -Uz compinit
compinit

alias ll='ls -al'

### git ###
alias gitcd='cd `git rev-parse --show-toplevel`'
function delete-merged-branch() {
	git fetch --prune
	git branch --merged | grep -v "*" | xargs -J % git branch -d %
}
### git ###

### kubectl ###
source <(kubectl completion zsh)
alias k=kubectl
### kubectl ###

### kustomize ###
alias kb='kustomize build --load-restrictor LoadRestrictionsNone'
### kustomize ###

### mysql ###
export PATH="/opt/homebrew/opt/mysql@8.4/bin:$PATH"
### mysql ###

### mise ###
eval "$(mise activate zsh)"
### mise ###

### starship ###
eval "$(starship init zsh)"
export STARSHIP_CONFIG=~/.config/starship/starship.toml
### starship ###

### aws cli ###
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit
complete -C '/usr/local/bin/aws_completer' aws
### aws cli ###

# Local overrides (not tracked in this repo)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
