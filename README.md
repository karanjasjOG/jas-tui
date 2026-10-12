# jas-tui

Reproducible Vim + tmux setup for macOS on Apple Silicon. Running `./bootstrap.sh` installs tmux via Homebrew, checks out the two pinned Vim plugins (auto-pairs, vim-sleuth) as git submodules loaded through Vim's native package system, backs up any existing `~/.vimrc`, `~/.vim` and `~/.tmux.conf`, and replaces them with symlinks into this repo. It then verifies everything with `./bootstrap.sh --check`. Vim is Apple's built-in `/usr/bin/vim`; there is no plugin manager and nothing is downloaded at runtime other than the pinned submodules.

These instructions are pinned to **`v0.1.0`**. Always install from a tag, not `main`.

## Prerequisites

- macOS on Apple Silicon.
- Xcode Command Line Tools (provides `git` and `/usr/bin/vim`): `xcode-select --install`
- [Homebrew](https://brew.sh), installed by you and on your `PATH` (`brew --version` works). The script will not install it.

**Linux:** the configs themselves are portable. On Linux without Homebrew the script skips `brew bundle` with a warning; install `git`, `vim` (a build with `+clipboard`, e.g. `vim-gtk3`) and `tmux` with your package manager first. This path is untested.

## Setup

Run these in order:

```sh
git clone --recursive --branch v0.1.0 https://github.com/karanjasjOG/jas-tui.git ~/dotfiles/jas-tui
cd ~/dotfiles/jas-tui
./bootstrap.sh --dry-run   # optional: see what would change
./bootstrap.sh
./bootstrap.sh --check
```

`--check` must end with `CHECK PASSED`. Running `./bootstrap.sh` again is safe and changes nothing.

| Command | Effect |
|---|---|
| `./bootstrap.sh` | Apply (idempotent), then run `--check`. |
| `./bootstrap.sh --dry-run` | Print every action apply would take; change nothing. |
| `./bootstrap.sh --check` | Verify only; change nothing; exit non-zero on any problem. |

## What the script changes on your machine

1. `brew bundle install --no-upgrade` from `Brewfile`: installs `tmux` if missing. Never upgrades.
2. `git submodule update --init --recursive` inside the repo, only if a plugin is not at its pinned commit.
3. For each of these, if it is not already the correct symlink, moves the existing file/dir to `~/.dotfiles-backup/<YYYYmmdd-HHMMSS>/` and creates the symlink:

   | Path | Symlink to |
   |---|---|
   | `~/.vimrc` | `<repo>/vim/vimrc` |
   | `~/.vim` | `<repo>/vim` |
   | `~/.tmux.conf` | `<repo>/tmux/tmux.conf` |

Nothing else is touched. No `sudo`. No backup directory is created when nothing needs backing up.

`--check` verifies: `git`, `vim`, `tmux` exist (prints versions), `vim` has `+clipboard` (warning only), the three symlinks point into the repo, every plugin directory is non-empty, `vim -Nes -i NONE -u ~/.vimrc -c 'qa!'` exits 0 (error text is printed on failure), and `~/.tmux.conf` loads on a throwaway tmux server (`-L bootstrap-check-<pid>`) with no error output.

## Notes on the configs

- `tmux.conf` binds `prefix f` to `~/.local/bin/tmux-sessionizer.sh`. That script is **not** part of this repo; the binding does nothing useful on machines without it. Config parsing is unaffected.
- `vimrc` uses the system clipboard (`"+`), which needs Vim with `+clipboard`. Apple's Vim has it.

## Updating a plugin (deliberately)

```sh
cd ~/dotfiles/jas-tui
git -C vim/pack/plugins/start/<plugin> fetch
git -C vim/pack/plugins/start/<plugin> log --oneline HEAD..origin/HEAD   # read what changes
git -C vim/pack/plugins/start/<plugin> checkout <new-commit>
./bootstrap.sh --check                                                   # must pass
vim                                                                      # try it for real
git add vim/pack/plugins/start/<plugin>
git commit -m "Bump <plugin> to <new-commit>"
git tag v0.x.y
```

Do not run `./bootstrap.sh` (apply) between the checkout and the commit: it resets submodules to the committed pins.

Adding or changing settings works the same way: edit `vim/vimrc` or `tmux/tmux.conf` in the repo (they are what `~` links to), run `--check`, commit, tag.

## Rolling back

**To an earlier version of this repo:**

```sh
cd ~/dotfiles/jas-tui
git checkout v0.1.0                       # or any earlier tag
git submodule update --init --recursive
./bootstrap.sh --check
```

**To your pre-bootstrap files** (undo the install entirely):

```sh
ls ~/.dotfiles-backup/                    # pick the timestamp
B=~/.dotfiles-backup/<timestamp>
rm ~/.vimrc ~/.vim ~/.tmux.conf           # these are only symlinks
mv "$B"/.vimrc "$B"/.vim "$B"/.tmux.conf ~/   # move back whichever exist
```

## If you are an AI agent

- Use the script. Do not edit `~/.vimrc`, `~/.vim` or `~/.tmux.conf` by hand, and do not create or delete those symlinks yourself.
- Clone the tag named at the top of this file, not `main`.
- Run `./bootstrap.sh --dry-run` first, then `./bootstrap.sh`, then `./bootstrap.sh --check`, and report the full output of `--check` to the user.
- If any step fails or `--check` prints `FAIL`, **stop and ask the user**. Do not improvise fixes: no installing Homebrew, no `sudo`, no adding plugins or plugin managers, no editing config files to make a check pass.
- Do not add secrets, tokens, SSH keys or machine-specific config to this repo.

## Published copies

GitHub Pages publishes this README as `setup.md` (and `setup.txt`), and `bootstrap.sh` (and `bootstrap.txt`), served verbatim, with an `index.html` linking to them. See `.github/workflows/pages.yml`.
