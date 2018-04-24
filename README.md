# Ansible Playbook(s) for Dev Setup

Opinionated playbooks to set up devstack. Super simple playbooks that do very
little, but it adds up.

Current playbooks:

1. `dotfiles`
   1. lays down configured dotfiles from github repo (e.g. `.vimrc`, `.tmux.conf`)
1. `vim_plug`
   1. sets up [vim-plug](https://github.com/junegunn/vim-plug) for vim plugins
   1. updates and installs plugins--currently this installs fzf, which is ok
      but seems side-effecty and would ideally be split out
1. `tmux`
   1. fetches tmux plugin manager
1. `brew_packages`
   1. installs configured brew packages
1. `frontend`
   1. installs `node` and `n`
1. `local_bin`
   1. lays down configured executables from github repo to /usr/local/bin

## TODOs

1. iterm profile

## Use

1. clone it
1. [install
   ansible](http://docs.ansible.com/ansible/intro_installation.html#installing-the-control-machine)
   (or on mac use `brew`)
1. configure: `playbooks/group_vars/all.yml` with your configuration
1. run it: `ansible-playbook playbooks/run.yml` (or to run on another host, run
   `ansible-playbook dotfiles.yml -i 'localhost,' -c local`)

## What problems does this solve?

1. This simplifies setting up new computers with dotfiles and other configuration
1. In the admittedly-rare situation where I am devving on multiple machines,
   this conveniently keeps dev configuration on all machines in sync

Is it worth maintaining an ansible playbook instead of doing everything
manually? Probably not.
