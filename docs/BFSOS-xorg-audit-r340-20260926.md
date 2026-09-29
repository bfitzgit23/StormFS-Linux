# BFSOS X.Org audit — r340 — 2026-09-26

Canonical `ports/xorg` recipes inventoried: **180**.

## Source/static results

- Pkgfiles passing `bash -n`: **180/180**.
- Recipes with unresolved hard dependencies: **0**.
- Active plain-HTTP source URLs after normalization: **0**.
- X.Org-hosted source URLs were normalized to the canonical HTTPS `xorg.freedesktop.org/archive/individual/` endpoint.
- Meta-package dependency lists were checked against the canonical package-name inventory.

## Verified upstream changes in this pass

- `mesa`: **26.2.2 -> 26.2.3** (Mesa upstream release news, 2026-09-16).
- `xorg-font-alias`: **1.0.4 -> 1.0.6** (X.Org font archive, 2026-02-08).

`xorg-server` remains on 21.1.24 because the newer 26.0.99.x files are prerelease snapshots; `xwayland` remains on 24.1.13. `libxkbcommon` remains on stable 1.13.2; 1.14.0-beta releases are prereleases.

## Runtime/build acceptance still required

This source/static pass does not claim BFSOS runtime acceptance. Clean-build changed recipes, then install the X.Org meta stack on a clean BFSOS target and test Xorg/xinit/input/video/Xwayland before closing the tracker item.

The complete per-port inventory is in `docs/BFSOS-xorg-audit-r340-20260926.tsv`; regenerate it with `scripts/bfs-xorg-audit.py`.

## Online checker attempt

The repository checker was run across all 180 X.Org recipes. The execution environment could not resolve external source hosts, so it returned 175 `FETCH-ERROR` rows and 5 local/meta `SKIP` rows rather than pretending those were current. The raw output is preserved in `docs/BFSOS-xorg-version-check-r340-20260926.{tsv,log}`. Authoritative web checks were therefore used for the verified updates and key server/input stack noted above; remaining runtime/network-backed provider verification stays open.
