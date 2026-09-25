# Ansible Playbook(s) for Dev Setup

Opinionated playbooks to set up devstack. Super simple playbooks that do very
little, but it adds up. Requires `xcode-select --install` and GitHub SSH access
(dotfiles and notes repos).

Playbooks (`run.yml` for mac, `run_linux.yml` for linux):

- `brew_packages` / `apt_packages`: configured packages
- `brew_cask`: casks and tap formulae
- `fish`: fish config dir, sets fish as login shell
- `dotfiles`: symlinks dotfiles from github repo, Rectangle settings, private
  dotfiles and git identity from optional extra vars
- `vim_plug`: [vim-plug](https://github.com/junegunn/vim-plug) and plugins
  (also installs fzf, which is side-effecty)
- `tmux`: tmux plugin manager
- `frontend`: `n` via npm
- `local_bin`: symlinks scripts from github repo into local bin
- `macos`: battery percentage, caps lock to escape
- `obsidian`: clones notes vault, Templater plugin, registers vault
- `pyenv`: python versions, venv per version, pip modules
- `claude`: Claude Code, settings, MCP servers, plugins
- `claude_notify`: SwiftBar notifications for Claude Code (see
  `playbooks/files/claude-notify/README.md`)

## Use

1. clone it
1. install ansible (`brew install ansible`)
1. configure `playbooks/group_vars/local.yml`
1. run `ansible-playbook playbooks/run.yml` (or `run_linux.yml`, or a single
   playbook). It prompts before upgrading outdated brew packages.

## What problems does this solve?

- Simplifies setting up new computers
- Keeps dev config in sync across machines

Is it worth maintaining an ansible playbook instead of doing everything
manually? Probably not.
