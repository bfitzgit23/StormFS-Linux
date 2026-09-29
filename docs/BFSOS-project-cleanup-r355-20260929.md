# BFSOS project cleanup — r355 — 2026-09-29

This pass restores the intended source-tree hygiene after the working snapshot accumulated historical tracker files and old installer revisions.

## Kept as canonical/current

- `bootstrap.sh`
- `bootstrap-clean-start.sh`
- `scripts/install-bfs-menu-current.sh`
- `scripts/bfs-build-iso.sh`
- `scripts/bfs-publish-sourceforge.sh`
- `scripts/bfs-publish-sourceforge-v4.sh` compatibility wrapper
- maintained audit/update/test utilities that still have current references or regression value

## Consolidated

- root tracker Markdown -> `docs/`
- historical root audit tables/logs -> `docs/audits/legacy/`
- Forgejo issue template -> GitHub `.github/ISSUE_TEMPLATE/bug-report.md`

## Removed from the maintained source tree

- historical installer implementation snapshots `install-bfs-menu-v50-r52` through `r74`
- legacy text installer
- bootstrap backup/debug copies
- `Pkgfile.bak`
- accidental root `libKF6Archive.so*` binaries
- scratch `proposed-check-script`
- generated log payloads

Git history remains the rollback/history mechanism for removed implementations.

## Validation

After cleanup and r355 source edits, all 34 retained test scripts pass, the release/ports static audits pass, and retained shell/Python source passes syntax validation.
