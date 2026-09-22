#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

ca=ports/core/ca-certificates/Pkgfile
makeca=ports/core/make-ca/post-install

grep -Fq 'nss_certdata_version=' "$ca"
grep -Fq 'NSS_${nss_certdata_version//./_}_RTM' "$ca"
grep -Fq '/usr/share/pki/mozilla/certdata.txt' "$ca"
grep -Fq '/etc/ssl/certdata.txt' "$ca"
grep -Fq '# Depends on: ca-certificates p11-kit' ports/core/make-ca/Pkgfile

# Install/update hooks may rebuild from packaged data but may never fetch roots.
for hook in ports/core/make-ca/post-install ports/core/ca-certificates/post-install; do
    if grep -Eq 'make-ca[[:space:]]+-g|curl[[:space:]]|wget[[:space:]]' "$hook"; then
        echo "network CA initialization remains in $hook" >&2
        exit 1
    fi
done
grep -Fq '/usr/sbin/make-ca -r' "$makeca"
grep -Fq 'trust list --filter=ca-anchors' "$makeca"

echo "CA trust source/install policy regression: PASS"
