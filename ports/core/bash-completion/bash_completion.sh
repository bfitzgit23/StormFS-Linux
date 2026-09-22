# Load system-wide Bash programmable completion when available.
# Owned by the bash-completion package, not aaa_filesystem.
if [ -n "${BASH_VERSION:-}" ] && [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi
