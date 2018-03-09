# Ansible Playbook(s) for Dev Setup

Opinionated playbooks to set up devstack. Current playbooks:

1. lays down dotfiles from github repo (e.g. `.vimrc`, `.tmux.conf`)
1. fetches tmux plugin manager
1. installs configured brew packages
1. installs `node` and `n`

## TODOs

1. config includes configuring which things to run/install, especially in `brew_packages`
1. plug for vim and install plugins?
1. iterm profile?
1. install brew packages
    1. [reattach-to-user-namespace](https://github.com/ChrisJohnsen/tmux-MacOSX-pasteboard#quick-summary)
    1. fzf

## Use

1. clone it
1. [install ansible](http://docs.ansible.com/ansible/intro_installation.html#installing-the-control-machine) (or on mac use `brew`)
1. configure: `playbooks/group_vars/all.yml` with your configuration
1. run it: `ansible-playbook playbooks/dotfiles.yml` (or to run on another host, run `ansible-playbook dotfiles.yml -i 'localhost,' -c local`)

## What problems does this solve?

1. This simplifies setting up new computers with dotfiles and other configuration
1. In the admittedly-rare situation where I am devving on multiple machines, this conveniently keeps dev configuration on all machines in sync

Is it worth maintaining an ansible playbook instead of doing everything manually? Probably not.
