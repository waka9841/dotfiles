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

### claude mcp ###
# カレントディレクトリ(=コピー元)の ~/.claude.json MCPサーバ設定を、直下の各サブディレクトリへコピーする
# 使い方: 既にMCP登録済みのプロジェクトのディレクトリへ cd して実行する
claude-mcp-copy-subdirs() {
	emulate -L zsh
	local config="$HOME/.claude.json"
	local src="$PWD"

	command -v jq >/dev/null 2>&1 || { print -u2 "[claude-mcp] jq が必要です"; return 1; }
	[[ -f "$config" ]] || { print -u2 "[claude-mcp] 見つかりません: $config"; return 1; }

	# コピー元に mcpServers があるか
	local n
	n=$(jq --arg s "$src" '(.projects[$s].mcpServers // {}) | length' "$config") || return 1
	if [[ "$n" -le 0 ]]; then
		print -u2 "[claude-mcp] コピー元に mcpServers がありません: $src"
		return 1
	fi

	# 直下のディレクトリ(非隠し)を収集
	local -a dirs
	dirs=( "$src"/*(/N) )
	if (( ${#dirs} == 0 )); then
		print -u2 "[claude-mcp] 直下にディレクトリがありません"
		return 1
	fi

	# 絶対パス配列を JSON 化
	local paths_json
	paths_json=$(printf '%s\n' "${dirs[@]}" | jq -Rs 'split("\n") | map(select(length>0))')

	# マージ → 検証 → 反映 (一時ファイルへ書いて検証後に置き換える: jq失敗時も元ファイルは無傷)
	local tmp="$config.tmp.$$"
	if jq --arg src "$src" --argjson paths "$paths_json" '
			.projects[$src].mcpServers as $servers
			| reduce $paths[] as $p (.;
					.projects[$p] = ((.projects[$p] // {}) + {mcpServers: $servers})
				)
		' "$config" > "$tmp" && jq empty "$tmp" >/dev/null 2>&1; then
		mv "$tmp" "$config"
		print "[claude-mcp] $n 個のMCPを ${#dirs} ディレクトリへマージしました"
		printf '  - %s\n' "${dirs[@]##*/}"
		print "[claude-mcp] 反映には対象ディレクトリで claude を再起動してください"
	else
		rm -f "$tmp"
		print -u2 "[claude-mcp] 失敗しました。変更は未適用です"
		return 1
	fi
}
### claude mcp ###

# Local overrides (not tracked in this repo)
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
