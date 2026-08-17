# ~/.bashrc - StormFS Linux default bash configuration

# If not running interactively, stop
[ -z "$PS1" ] && return

# History settings
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Prompt: user@host:dir$
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Colors for ls
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Source oh-my-bash if available
if [ -f "$HOME/.oh-my-bash/oh-my-bash.sh" ]; then
    OSH="$HOME/.oh-my-bash"
    DISABLE_AUTO_UPDATE="true"
    source "$OSH/oh-my-bash.sh"
fi

# PATH additions
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"
