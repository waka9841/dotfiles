# dotfiles
## init
```sh
$ ./.bin/install.sh
```
### options
- `--debug` or `-d`: debug mode
    ```sh
    $ ./.bin/install.sh --debug
    ```
- `--xcode-command-line-tools-install` or `-X`: install xcode-command-line-tools
    ```sh
    $ ./.bin/install.sh --xcode-command-line-tools-install
    ```
- `--brew-install` or `-b`: install homebrew
    ```sh
    $ ./.bin/install.sh --brew-install
    ```
- `--link-to-homedir` or `-l`: link to dotfiles
    ```sh
    $ ./.bin/install.sh --link-to-homedir
    ```
- `--install-mise-plugins` or `-m`: install mise plugins
    ```sh
    $ ./.bin/install.sh --install-mise-plugins
    ```
- `--install-helm-schema` or `-H`: install helm-schema plugin
    ```sh
    $ ./.bin/install.sh --install-helm-schema
    ```
- `--install-sops` or `-S`: install sops
    ```sh
    $ ./.bin/install.sh --install-sops
    ```
- `--install-aws-cli` or `-A`: install AWS CLI
    ```sh
    $ ./.bin/install.sh --install-aws-cli
    ```
- `--install-claude-code` or `-C`: install Claude Code
    ```sh
    $ ./.bin/install.sh --install-claude-code
    ```
- `--install-npm-globals` or `-N`: install npm global packages (via mise)
    ```sh
    $ ./.bin/install.sh --install-npm-globals
    ```
- `--setup-local-overrides` or `-L`: create local override files (`.zshrc.local`, `.zprofile.local`, `.ssh/config.d/`)
    ```sh
    $ ./.bin/install.sh --setup-local-overrides
    ```
- `--setup-docker-cli-plugins` or `-D`: register brew's Docker CLI plugins (buildx, compose) in `~/.docker/config.json`
    ```sh
    $ ./.bin/install.sh --setup-docker-cli-plugins
    ```
- `--setup-autoreboot` or `-R`: install a launchd daemon that reboots the Mac every Saturday at 03:00 (opt-in; **not** run by the default `install.sh`, requires `sudo`)
    ```sh
    $ ./.bin/install.sh --setup-autoreboot
    ```
    Uninstall:
    ```sh
    $ sudo launchctl bootout system /Library/LaunchDaemons/com.user.autoreboot.plist
    $ sudo rm /Library/LaunchDaemons/com.user.autoreboot.plist
    ```
- `--setup-ansible` or `-a`: install ansible for Mikasa.Ansible via pipx, isolated (opt-in; **not** run by the default `install.sh`)
    - pins `ansible-core` to the 2.15 series (`ansible==8.7.0`) on Python 3.11 (supplied by mise), because newer `ansible-core` drops Python versions still required on the target servers
    - avoids the brew build, which `brew upgrade` silently bumps to an incompatible core
    - injects `boto3`/`botocore` into the venv so `amazon.aws` modules work
    ```sh
    $ ./.bin/install.sh --setup-ansible
    ```
    Uninstall:
    ```sh
    $ python3 -m pipx uninstall ansible   # or: pipx uninstall ansible
    ```

## command tips
### Homebrew
Update Brewfile
```sh
$ brew bundle dump --force
```
