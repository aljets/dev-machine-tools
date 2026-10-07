# Ansible Playbook(s) for Dev Setup

Opinionated playbooks to set up devstack. Super simple playbooks that do very
little, but it adds up. Requires `xcode-select --install` and GitHub SSH access
(dotfiles and notes repos).

Entrypoints: `run_home.yml` (personal mac), `run_work.yml` (home plus work
playbooks), `run_linux.yml`. Vars are in `group_vars/home.yml`;
`run_work.yml` and `run_linux.yml` layer `work.yml` and `linux.yml` on top. Lists don't merge across
groups, so additive ones use separate names (`work_brew_packages`). To run a
single work playbook, pass `-i hosts_work`. Employer-specific config lives
outside this repo in `claude_extra_vars` as `private_*` vars.

Playbooks (work-only: `frontend`, `obsidian`, `claude`,
`claude_notify`, `meeting_bar`, `kitty_session`;
`tmux` is disabled):

- `brew_packages` / `apt_packages`: configured packages
- `brew_cask`: casks and tap formulae
- `fish`: fish config dir, sets fish as login shell
- `dotfiles`: symlinks dotfiles from github repo, Rectangle settings, personal
  git identity (prompted once per machine), private dotfiles from optional
  extra vars
- `vim_plug`: [vim-plug](https://github.com/junegunn/vim-plug) and plugins
  (also installs fzf, which is side-effecty)
- `tmux`: tmux plugin manager
- `frontend`: `n` via npm
- `local_bin`: symlinks scripts from github repo into local bin
- `macos`: battery percentage, caps lock to escape
- `obsidian`: clones notes vault, merges shared settings and templates from
  dotfiles, Templater plugin, registers vault
- `pyenv`: python versions, venv per version, pip modules
- `claude`: Claude Code, settings, MCP servers, plugins
- `claude_notify`: SwiftBar notifications for Claude Code (see
  `playbooks/files/claude-notify/README.md`)
- `meeting_bar`: SwiftBar countdown to the next meeting with a Zoom join alert
  (see `playbooks/files/meeting-bar/README.md`)
- `kitty_session`: kitty session save/restore, including Claude Code sessions

## Use

1. clone it
1. install ansible (`brew install ansible`)
1. configure `playbooks/group_vars/home.yml` and `work.yml`
1. optionally, set up work config in `~/repos/dotfiles` (loaded via
   `claude_extra_vars`) from the dotfiles repo's `work-dotfiles.md`
1. run `ansible-playbook playbooks/run_work.yml` (or `run_home.yml`,
   `run_linux.yml`, or a single playbook). It prompts before upgrading outdated brew packages.

## What problems does this solve?

- Simplifies setting up new computers
- Keeps dev config in sync across machines

Is it worth maintaining an ansible playbook instead of doing everything
manually? Probably not.
