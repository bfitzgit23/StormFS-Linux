#!/bin/sh
# Non-destructive installed-system CA/NSS/p11-kit sanity check.
set -u
fail=0
ok(){ printf 'OK:   %s\n' "$*"; }
bad(){ printf 'FAIL: %s\n' "$*"; fail=1; }
warn(){ printf 'WARN: %s\n' "$*"; }

bundle=/etc/pki/tls/certs/ca-bundle.crt
[ -s "$bundle" ] && ok "canonical CA bundle is non-empty" || bad "canonical CA bundle missing/empty"
[ -d /etc/pki/anchors ] && ok "/etc/pki/anchors exists" || bad "/etc/pki/anchors missing"

if command -v trust >/dev/null 2>&1; then
    if trust list 2>/dev/null | grep -q 'type: certificate'; then
        ok "p11-kit trust view contains certificates"
    else
        bad "p11-kit trust view contains no certificates"
    fi
else
    bad "p11-kit trust utility missing"
fi

if [ -L /usr/lib/libnssckbi.so ]; then
    target="$(readlink /usr/lib/libnssckbi.so)"
    case "$target" in *p11-kit-trust.so*) ok "NSS builtin trust redirects to p11-kit" ;; *) bad "unexpected libnssckbi.so target: $target" ;; esac
else
    warn "/usr/lib/libnssckbi.so is not a symlink; verify NSS trust policy"
fi

for link in /etc/ssl/cert.pem /etc/ssl/certs/ca-certificates.crt; do
    if [ -e "$link" ] && [ -s "$link" ]; then ok "$link resolves to a non-empty trust bundle"; else bad "$link missing/broken/empty"; fi
done

if command -v curl >/dev/null 2>&1; then
    if curl --fail --silent --show-error --head --max-time 20 https://www.example.com/ >/dev/null 2>&1; then
        ok "curl HTTPS trust test passed"
    else
        bad "curl HTTPS trust test failed"
    fi
else
    warn "curl unavailable; HTTPS runtime test skipped"
fi

if command -v openssl >/dev/null 2>&1 && [ -s "$bundle" ]; then
    cert_count="$(grep -c 'BEGIN CERTIFICATE' "$bundle" 2>/dev/null || true)"
    [ "${cert_count:-0}" -gt 0 ] && ok "canonical bundle contains $cert_count certificates" || bad "canonical bundle has no PEM certificates"
fi

exit "$fail"
