### completion ###
# kubectl 補完は毎回生成すると遅い(約50ms)ため、fpath にキャッシュして遅延ロードする
# (kubectl 更新時のみ自動再生成)
fpath=(~/.zsh/completions $fpath)
if [[ ! -f ~/.zsh/completions/_kubectl || ${commands[kubectl]} -nt ~/.zsh/completions/_kubectl ]]; then
	mkdir -p ~/.zsh/completions
	kubectl completion zsh > ~/.zsh/completions/_kubectl
fi

autoload -Uz compinit bashcompinit
# .zcompdump が24時間以内なら補完ディレクトリのセキュリティチェックをスキップ(約300ms短縮)
if [[ -n ~/.zcompdump(#qN.mh-24) ]]; then
	compinit -C
else
	compinit
fi
bashcompinit
### completion ###

alias ll='ls -al'

### git ###
alias gitcd='cd `git rev-parse --show-toplevel`'
function delete-merged-branch() {
	git fetch --prune
	git branch --merged | grep -v "*" | xargs -J % git branch -d %
}
### git ###

### kubectl ###
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
# compinit / bashcompinit はファイル冒頭で初期化済み
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

### update-all ###
# brew / Claude Code / mise / npm グローバル / uv tool をまとめて更新する
# gcloud・uv は brew 管理なので brew upgrade に含まれる
# brew upgrade は --greedy 付き: 自己更新型の cask (raycast 等) は付けないと対象外になる。更新時にアプリが終了する
# macOS 本体は sudo が要るため一覧表示のみ (更新は システム設定 > ソフトウェアアップデート から)
# 最後に、更新し残した brew / mise と、brew 管理外のアプリ (各アプリ内で更新が必要) を表示する
update-all() {
	emulate -L zsh
	setopt local_options null_glob
	local -a failed

	_update_step() {
		print -P "\n%F{cyan}==> $1%f"
		shift
		"$@" || failed+=("$*")
	}

	_update_step "Homebrew: update"  brew update
	_update_step "Homebrew: upgrade" brew upgrade --greedy
	_update_step "Homebrew: cleanup" brew cleanup
	_update_step "Claude Code"       claude update
	_update_step "mise: upgrade"     mise upgrade
	_update_step "npm: global"       npm update -g
	_update_step "uv: tool upgrade"  uv tool upgrade --all
	_update_step "macOS: 更新の確認" softwareupdate --list

	unfunction _update_step

	print -P "\n%F{cyan}==> 残っている更新%f"
	print "[brew]"; brew outdated --greedy --verbose
	print "[mise]"; mise outdated

	# brew 管理外のアプリは自動では更新されないので、版を並べて各アプリでの更新を促す
	local -a brew_apps
	brew_apps=( ${(f)"$(brew info --cask --json=v2 --installed | jq -r '.casks[].artifacts[] | objects | .app? // empty | .[] | strings')"} )
	brew_apps=( ${brew_apps:t} )
	print -P "\n%F{cyan}==> brew 管理外のアプリ (各アプリ / App Store / Self Service で更新を確認)%f"
	local app id ver note
	for app in /Applications/*.app ~/Applications/*.app; do
		(( ${brew_apps[(Ie)${app:t}]} )) && continue
		id=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
		[[ $id == com.apple.* ]] && continue
		ver=$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)
		note=""
		[[ -d $app/Contents/_MASReceipt ]] && note=" [App Store]"
		printf '  - %s %s%s\n' "${app:t:r}" "$ver" "$note"
	done

	if (( ${#failed} )); then
		print -P "\n%F{red}[update-all] 失敗したステップ:%f"
		printf '  - %s\n' "${failed[@]}"
		return 1
	fi
	print -P "\n%F{green}[update-all] 完了%f"
}
### update-all ###

# Local overrides (not tracked in this repo)
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
