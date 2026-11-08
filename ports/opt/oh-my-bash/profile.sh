# Enable the system-wide Oh My Bash installation for interactive shells.
if [ -z "${BASH_VERSION-}" ]; then
	return 0 2>/dev/null || exit 0
fi

case $- in
	*i*) ;;
	*) return 0 ;;
esac

[ -n "${OSH-}" ] && return 0
[ -r /usr/share/oh-my-bash/oh-my-bash.sh ] || return 0

export OSH=/usr/share/oh-my-bash
export DISABLE_AUTO_UPDATE=true
. "$OSH/oh-my-bash.sh"
