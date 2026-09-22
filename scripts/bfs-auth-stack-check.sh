#!/usr/bin/env bash
set -u

fail=0

ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
bad()  { printf '[FAIL] %s\n' "$*"; fail=1; }

check_pkg_version() {
    local pkg="$1" expected="$2" got=""
    if command -v pkginfo >/dev/null 2>&1; then
        got="$(pkginfo -i 2>/dev/null | awk -v p="$pkg" '$1==p {print $2; exit}')"
    fi
    if [[ -z "$got" ]]; then
        bad "$pkg is not installed"
    elif [[ "$got" == "$expected"-* || "$got" == "$expected" ]]; then
        ok "$pkg $got"
    else
        bad "$pkg version is $got; expected $expected"
    fi
}

echo "=== BFSOS authentication stack check ==="

check_pkg_version cracklib 2.10.3
check_pkg_version linux-pam 1.7.2
check_pkg_version libpwquality 1.4.5
check_pkg_version shadow 4.20.2

[[ -s /usr/lib/cracklib/pw_dict.pwd ]] &&
    ok "CrackLib dictionary exists" ||
    bad "CrackLib dictionary /usr/lib/cracklib/pw_dict.pwd is missing"

[[ -r /etc/security/pwquality.conf ]] &&
    ok "/etc/security/pwquality.conf exists" ||
    bad "/etc/security/pwquality.conf is missing"

[[ -x /usr/sbin/unix_chkpwd && -u /usr/sbin/unix_chkpwd ]] &&
    ok "unix_chkpwd is installed setuid-root" ||
    bad "unix_chkpwd is missing or not setuid-root"

[[ -f /usr/lib/security/pam_pwquality.so ]] &&
    ok "pam_pwquality.so is installed" ||
    bad "pam_pwquality.so is missing"

if grep -Eq '^[[:space:]]*password[[:space:]]+required[[:space:]]+pam_pwquality\.so' \
        /etc/pam.d/system-password 2>/dev/null; then
    ok "system-password uses pam_pwquality"
else
    bad "system-password does not require pam_pwquality"
fi

if grep -Eq 'pam_unix\.so.*yescrypt.*shadow' /etc/pam.d/system-password 2>/dev/null; then
    ok "system-password uses pam_unix yescrypt + shadow"
else
    bad "system-password is missing pam_unix yescrypt/shadow policy"
fi

for service in login passwd su chpasswd newusers chage; do
    [[ -r "/etc/pam.d/$service" ]] &&
        ok "PAM service policy: $service" ||
        bad "missing /etc/pam.d/$service"
done

if [[ -r /etc/pam.d/systemd-user ]] &&
   grep -q 'pam_systemd\.so' /etc/pam.d/systemd-user; then
    ok "systemd-user PAM policy includes pam_systemd"
else
    bad "systemd-user PAM integration is missing"
fi

if command -v loginctl >/dev/null 2>&1; then
    ok "loginctl is available for systemd-logind runtime testing"
else
    warn "loginctl not found"
fi

if command -v pwscore >/dev/null 2>&1; then
    ok "pwscore is available"
else
    bad "pwscore is missing"
fi

echo
if (( fail )); then
    echo "Authentication stack static check: FAILED"
    exit 1
fi

echo "Authentication stack static check: PASSED"
echo "Runtime tests still required: login, su, passwd, chpasswd, SSH password auth,"
echo "weak-password rejection, locked-password accounts, and upgrade/reinstall preservation."
