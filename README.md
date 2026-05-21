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

## command tips
### Homebrew
Update Brewfile
```sh
$ brew bundle dump --force
```
