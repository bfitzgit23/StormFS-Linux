# Chapter 15: Base Utilities

This chapter covers essential command-line utilities, editors, manual pages, shell completion, and user environment configuration for StormFS Linux.

## 15.1 Core Utilities Overview

StormFS ships with the **GNU Core Utilities** (coreutils) providing the essential file, shell, and text manipulation programs. Verify installation:

```bash
coreutils --version
ls --version
```

### Key Utilities Reference

| Category | Utilities |
|----------|-----------|
| File operations | `cp`, `mv`, `rm`, `ln`, `install`, ` shred` |
| Directory operations | `mkdir`, `rmdir`, `ls`, `tree` |
| Text processing | `cat`, `head`, `tail`, `cut`, `sort`, `uniq`, `wc`, `tr`, `sed`, `awk` |
| System info | `uname`, `uptime`, `df`, `du`, `free`, `lsblk`, `stat` |
| Process | `ps`, `top`, `htop`, `kill`, `nice`, `nohup` |
| Search | `find`, `grep`, `which`, `locate` |
| Archive | `tar`, `gzip`, `bzip2`, `xz`, `zip`, `unzip` |
| Permissions | `chmod`, `chown`, `chgrp`, `umask`, `getfacl`, `setfacl` |

### Essential Additions

```bash
# htop — process viewer
cd /sources && tar -xf htop-3.3.0.tar.xz && cd htop-3.3.0
./configure --prefix=/usr && make -j$(nproc) && make install

# tree — directory listing
cd /sources && tar -xf tree-2.1.1.tgz && cd tree-2.1.1
make && make install PREFIX=/usr

# ncdu — disk usage analyzer
cd /sources && tar -xf ncdu-2.4.tar.gz && cd ncdu-2.4
./configure --prefix=/usr && make && make install
```

## 15.2 vim Configuration

StormFS ships with **vim** as the primary system editor.

### Installing vim

```bash
cd /sources
tar -xf vim-9.1.tar.bz2
cd vim-9.1

./configure --prefix=/usr \
            --with-features=huge \
            --enable-multibyte \
            --enable-cscope=yes \
            --enable-gui=auto \
            --with-x=no
make -j$(nproc)
make install
```

### System-Wide vimrc

Create `/etc/vimrc`:

```vim
" StormFS System vimrc
" /etc/vimrc

" General
set nocompatible
set encoding=utf-8
set fileencodings=utf-8,latin1
set termencoding=utf-8

" UI
set number
set relativenumber
set cursorline
set showcmd
set showmode
set laststatus=2
set ruler
set wildmenu
set wildmode=longest:full,full
set display=lastline
set noshowcmd
set showmatch
set scrolloff=5

" Indentation
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase
set wrapscan

" Behavior
set backspace=indent,eol,start
set autoread
set hidden
set nomodeline
set modelines=0
set history=500
set clipboard=unnamedplus
set mouse=a
set ttymouse=sgr

" Files
set nobackup
set noswapfile
set nowritebackup
set undofile
set undodir=~/.vim/undodir

" Statusline
set statusline=
set statusline+=\ %f
set statusline+=\ %m%r
set statusline+=%=
set statusline+=\ %y
set statusline+=\ [%{&fileencoding?&fileencoding:&encoding}]
set statusline+=\ [%{&fileformat}]
set statusline+=\ %l:%c
set statusline+=\ %p%%
set statusline+=\ 

" Syntax
syntax on
filetype plugin indent on

" Colors
set background=dark
set t_Co=256

" Key mappings
let mapleader=" "
nnoremap <Leader>w :w<CR>
nnoremap <Leader>q :q<CR>
nnoremap <Leader>/ :nohlsearch<CR>
```

### Creating undo directory

```bash
mkdir -p ~/.vim/undodir
```

## 15.3 nano Usage

nano is a simple, user-friendly editor for quick edits.

### Installing nano

```bash
cd /sources
tar -xf nano-8.1.tar.xz
cd nano-8.1

./configure --prefix=/usr \
            --sysconfdir=/etc \
            --enable-color \
            --enable-utf8 \
            --docdir=/usr/share/doc/nano-8.1
make -j$(nproc)
make install
```

### System-Wide nanorc

Create `/etc/nanorc`:

```bash
cat > /etc/nanorc << 'NANORC'
# StormFS System nanorc
# /etc/nanorc

# General
set autoindent
set smarthome
set tabsize 4
set tabstospaces
set linenumbers

# Search
set case-sensitive
set indicator
set showcursor

# Behavior
set mouse
set multibuffer
set nohelp
set afterends
set atblanks
set softwrap

# Syntax highlighting
include /usr/share/nano/*.nanorc
include /usr/share/nano/extra/*.nanorc

# Disable suspend (uncomment if needed)
# set suspend
NANORC
```

## 15.4 man-pages and man-db

### Installing man-db

man-db provides the `man` command and manual page database:

```bash
cd /sources
tar -xf man-db-2.12.1.tar.xz
cd man-db-2.12.1

./configure --prefix=/usr                        \
            --docdir=/usr/share/doc/man-db-2.12.1 \
            --sysconfdir=/etc                    \
            --disable-setuid                     \
            --enable-cache-owner=man             \
            --with-browser=/usr/bin/lynx         \
            --with-pager=/usr/bin/less           \
            --with-config-file=/etc/man_db.conf  \
            --with-nroff=/usr/bin/nroff
make -j$(nproc)
make install
```

### Configure man-db

Edit `/etc/man_db.conf`:

```bash
# Key settings
MANDB_MAP     /usr/share/man    /var/cache/man/catman
MANDB_MAP     /usr/local/man    /var/cache/man/catman-local
MANDB_MAP     /opt/*/man        /var/cache/man/catman-opt

MANPATH_MAP   /bin               /usr/share/man
MANPATH_MAP   /sbin              /usr/share/man
MANPATH_MAP   /usr/bin           /usr/share/man
MANPATH_MAP   /usr/sbin          /usr/share/man
MANPATH_MAP   /usr/local/bin     /usr/local/man
MANPATH_MAP   /usr/local/sbin    /usr/local/man

MANDB_MAP     /usr/share/man     /var/cache/man
MANDB_MAP     /usr/local/man     /var/cache/man

# Section order
MANSECT       1:1p:8:2:3:3p:4:5:6:7:9:0p:n:l:p:o:1x:2x:3x:4x:5x:6x:7x:8x

# Formatter
MANFORMATTER  /usr/bin/mandoc
```

### Installing man-pages

```bash
cd /sources
tar -xf man-pages-6.9.1.tar.xz
cd man-pages-6.9.1

make install prefix=/usr/local
```

### Building the Man Page Database

```bash
mandb
```

### Using man

```bash
# View a manual page
man ls

# View a specific section
man 5 passwd
man 3 printf

# Search for a keyword
man -k "network"
apropos "network"

# Display all sections
man -a passwd

# Output as plain text (useful for piping)
man ls | col -b > ls-manpage.txt
```

### HTML Documentation

```bash
# Install HTML docs (if available)
mkdir -p /usr/share/doc/stormfs
cp -r /sources/docs/* /usr/share/doc/stormfs/
```

## 15.5 bash Completion

### Installing bash-completion

```bash
cd /sources
tar -xf bash-completion-2.12.tar.xz
cd bash-completion-2.12

./configure --prefix=/usr \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/bash-completion-2.12
make install
```

### Enable bash-completion

Add to `/etc/profile` or create `/etc/profile.d/bash_completion.sh`:

```bash
# Source system bash completion
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# Source user-specific completion
if [ -f ~/.bash_completion ]; then
    . ~/.bash_completion
fi
```

### Custom Completions

Create `/etc/bash_completion.d/custom`:

```bash
# Custom completion for stormfs command
_stormfs_completion() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="build install clean update status"

    if [[ ${cur} == -* ]]; then
        COMPREPLY=( $(compgen -W "--help --version --verbose --quiet" -- ${cur}) )
    else
        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
    fi
}

complete -F _stormfs_completion stormfs
```

### Per-User Completion

Create `~/.local/share/bash-completion/completions/`:

```bash
mkdir -p ~/.local/share/bash-completion/completions/
cat > ~/.local/share/bash-completion/completions/myproject << 'EOF'
_myproject_completion() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "start stop restart status log" -- ${cur}) )
}

complete -F _myproject_completion myproject
EOF
```

## 15.6 bash Profile and bashrc Setup

### /etc/profile (System-Wide)

The system-wide profile is sourced for all login shells:

```bash
cat > /etc/profile << 'PROFILE'
# StormFS System Profile
# /etc/profile

# Set default umask
umask 022

# Set PATH
PATH=/usr/local/bin:/usr/bin:/bin
export PATH

# Set MANPATH
MANPATH=/usr/local/man:/usr/share/man
export MANPATH

# Set INFOPATH
INFOPATH=/usr/local/info:/usr/share/info
export INFOPATH

# Set LANG
if [ -z "$LANG" ]; then
    LANG=en_US.UTF-8
    export LANG
fi

# Source profile.d scripts
for i in /etc/profile.d/*.sh ; do
    if [ -r "$i" ]; then
        . "$i"
    fi
done

unset i
PROFILE
```

### /etc/profile.d/ Scripts

Create `/etc/profile.d/editor.sh`:

```bash
cat > /etc/profile.d/editor.sh << 'EOF'
# Set default editor
export EDITOR=vim
export VISUAL=vim
EOF
```

Create `/etc/profile.d/paths.sh`:

```bash
cat > /etc/profile.d/paths.sh << 'EOF'
# Additional user paths
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Go paths
if [ -d /usr/local/go/bin ]; then
    PATH="/usr/local/go/bin:$PATH"
fi

# Rust/Cargo paths
if [ -d "$HOME/.cargo/bin" ]; then
    PATH="$HOME/.cargo/bin:$PATH"
fi

export PATH
EOF
```

Create `/etc/profile.d/less.sh`:

```bash
cat > /etc/profile.d/less.sh << 'EOF'
# Less configuration
export LESSHISTFILE=-
export LESSHISTSIZE=1000
export LESS="-R -M -i -J -w -X -F -x4"
EOF
```

### ~/.bashrc (User Configuration)

The `.bashrc` is sourced for interactive non-login shells. A reference configuration:

```bash
cat > ~/.bashrc << 'BASHRC'
# ~/.bashrc — StormFS User Configuration

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T "
PROMPT_COMMAND='history -a'

# Shopt options
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
shopt -s dirspell
shopt -s cdspell
shopt -s checkjobs

# Prompt
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -pv'
alias h='history'
alias j='jobs -l'
alias ..='cd ..'
alias ...='cd ../..'
alias ports='prt-get search'
alias update='prt-get sysup'

# Functions
mkcd() { mkdir -p "$1" && cd "$1"; }
extract() {
    case "$1" in
        *.tar.bz2) tar xjf "$1"   ;;
        *.tar.gz)  tar xzf "$1"   ;;
        *.tar.xz)  tar xJf "$1"   ;;
        *.bz2)     bunzip2 "$1"   ;;
        *.gz)      gunzip "$1"    ;;
        *.tar)     tar xf "$1"    ;;
        *.xz)      unxz "$1"     ;;
        *.zip)     unzip "$1"     ;;
        *.7z)      7z x "$1"      ;;
        *)         echo "'$1' cannot be extracted" ;;
    esac
}

# Source bash-completion
[[ -f /etc/bash_completion ]] && . /etc/bash_completion

# Source local overrides
[[ -f ~/.bash_completion ]] && . ~/.bash_completion
BASHRC
```

### ~/.profile (Login Shell)

For login shells, create `~/.profile`:

```bash
cat > ~/.profile << 'PROFILE'
# ~/.profile — StormFS User Login Shell

# Source .bashrc if it exists
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

# Set PATH for login shells (if not set in .bashrc)
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Display system info on login (optional)
if [ -t 1 ]; then
    echo ""
    echo "StormFS Linux $(cat /etc/os-release | grep VERSION | cut -d'"' -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo ""
fi
PROFILE
```

## 15.7 Setting locale

### Installing locale Data

```bash
cd /sources
tar -xf glibc-2.40.tar.xz
cd glibc-2.40

# Generate locales
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
```

### Setting Default Locale

```bash
cat > /etc/locale.conf << 'EOF'
LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_TIME=en_US.UTF-8
LC_COLLATE=C
EOF
```

### Verifying Locale

```bash
locale
locale -a
```

## 15.8 References

- [GNU Coreutils Manual](https://www.gnu.org/software/coreutils/manual/)
- [vim Documentation](https://www.vim.org/docs.php)
- [GNU bash Manual](https://www.gnu.org/software/bash/manual/)
- [man-db Documentation](https://man-db.nongnu.org/)
- [bash-completion Project](https://github.com/scop/bash-completion)
- [Chapter 11: Package Management](chapter-11-package-management.md) — Installing utilities
