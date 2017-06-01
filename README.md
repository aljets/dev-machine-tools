# Ansible Playbook(s) for Dev Setup

## What?

An opinionated (read: "Adam's") playbook to set up devstack

Current:

1. lays down dotfiles from github repo (e.g. `.vimrc`, `.tmux.conf`)
1. fetches tmux plugin manager

Future:

1. plug for vim and install plugins?
1. iterm profile?
1. install `ag`

## How should it be used?

1. clone it
1. [install ansible](http://docs.ansible.com/ansible/intro_installation.html#installing-the-control-machine) (or on mac use `brew`)
1. create config file with your variables
1. run it (to run it locally, run `ansible-playbook dotfiles.yml -i 'localhost,' -c local`)

## What problems does this solve?

1. This simplifies setting up new computers with dotfiles and other configuration
1. In the admittedly-rare situation where I am devving on multiple machines, this conveniently keeps dev configuration on all machines in sync

Is it worth maintaining an ansible playbook instead of doing everything manually? Perhaps not.
