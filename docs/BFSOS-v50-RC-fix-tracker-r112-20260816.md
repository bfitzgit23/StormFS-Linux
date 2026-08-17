# BFSOS Installer v50 Test / Fix Tracker


### Bootstrap → installer launch time synchronization
- [x] **IMPLEMENTED in bootstrap r50; regression test pending:** Bootstrap Stage 9 launches the installer with `BFS_TIME_SYNC=no`, so the bootstrap startup sync is reused while standalone installer launches still synchronize normally.
- The Bootstrap startup already synchronizes the system clock; entering the installer from the same Bootstrap session should not trigger another time sync.
- Audit both the Stage 9 launch path in `bootstrap.sh` and the installer startup path so Bootstrap can hand off to the installer without causing a duplicate synchronization.
- Preserve standalone installer behavior as appropriate: launching the installer independently may still need its own startup time synchronization.
- [ ] **Regression test:** Start Bootstrap, allow its normal startup time sync, then launch Stage 9 and confirm no second time-sync operation occurs during the Bootstrap-to-installer handoff.



### Bootstrap Stage 8 chroot exit still shows redundant completion pause
- [x] **FIX IMPLEMENTED in bootstrap r50; regression test pending:** Stage 8 now `continue`s directly back to the Bootstrap menu after its own chroot result handling and cannot fall through into the generic operation-success/pause block.
- The attempted Stage 8 clean-return fix has not eliminated the actual code path producing this screen.
- Trace the complete Stage 8/chroot return path, including `_chroot`, `_run_root_stage`, child-script re-entry, and the generic main-menu completion handler, to identify where the success/pause is really emitted.
- Desired behavior: a normal `exit` from the chroot should return directly to the Bootstrap main menu with no intermediate success screen or Enter prompt.
- Preserve a readable error/pause only when entering the chroot or the chroot operation actually fails.
- [ ] **Regression test:** Enter Stage 8, run `exit`, and confirm the Bootstrap menu reappears immediately with no `Operation completed successfully.` or `Press Enter to return to the menu...` screen.



### Bootstrap Stage 8 chroot availability after normal build
- [x] **BUG FOUND AND FIXED in bootstrap r48; regression test pending:** Stage 8 incorrectly showed `[NOT AVAILABLE]` after a successful normal Stage 2/3/4 build because `_chroot_available()` only recognized rootfs/toolchain **restore** marker files.
- A freshly built BFSOS rootfs is already chroot-capable and must not require Stage 6 or Stage 7 to be run first.
- `_chroot_available()` now accepts any valid built/restored rootfs state marker (`.bfs-stage2-complete`, `.bfs-stage3-complete`, `.bfs-verified`, `.bfs-rootfs-restored`, or `.bfs-toolchain-restored`) together with an executable `/usr/bin/bash` or `/bin/bash`.
- [ ] **Regression test:** After normal Stages 1 -> 2 -> 4 -> 5 (with or without optional Stage 3), confirm Stage 8 shows `[AVAILABLE]` without restoring an archive, and verify entering/exiting the chroot works normally.
- [ ] Also verify Stage 8 becomes available after Stage 6 rootfs restore and after Stage 7 toolchain restore when the resulting rootfs contains a usable shell.



### Bootstrap Stage 5 archive-start dialog
- [x] **IMPLEMENTED in bootstrap r47; regression test pending:** Selecting Stage 5 from the dialog Bootstrap menu now presents a proper `dialog` confirmation/information box before compression starts.
- The dialog explains that the verified base rootfs archive will be created and checked and that compression can take several minutes.
- Canceling the dialog returns to the Bootstrap menu without starting Stage 5.
- Stage 5 still returns directly to the main menu after success; real failures retain the failure handling.

### Bootstrap Stage 6 restore privilege / chroot-readiness audit
- [x] **BUG FOUND AND FIXED in bootstrap r47:** Stage 6 was being called directly from the interactive menu even though restoring a rootfs is a privileged/destructive operation. It now uses the same `_run_root_stage` sudo/root path as Stages 2-5 and chroot.
- [x] `_restore_rootfs()` now explicitly refuses to run unless UID 0.
- [x] Before clearing the existing rootfs, Stage 6 calls `umountfs` and aborts if bootstrap bind/virtual filesystems cannot be cleanly unmounted.
- [x] The existing restore logic validates the archive before destruction, extracts it, recreates required compatibility symlinks/directories, verifies `/usr/bin/bash`, `/usr/bin/gcc`, and the package database, and creates `.bfs-rootfs-restored`.
- [x] The existing chroot availability logic recognizes `.bfs-rootfs-restored` plus a usable bash, so a successful Stage 6 restore makes Stage 8 available without requiring the temporary toolchain restore.
- [ ] **Regression test:** Run Stage 6 from the non-root interactive menu, confirm sudo/root re-entry occurs, the archive restores cleanly, Stage 8 changes to `AVAILABLE`, and entering/exiting the chroot works.



### Bootstrap Stage 4 success-screen cleanup
- [x] **IMPLEMENTED in bootstrap r46; regression test pending:** After successful Stage 4 base-system verification, return directly to the Bootstrap main menu instead of displaying `Operation completed successfully.` followed by `Press Enter to return to the menu...`.
- Stage 4 failures still report the nonzero exit status and retain the failure pause so the error can be read.



### Bootstrap archive safety / Stage 5 failure handling
- [x] **IMPLEMENTED in bootstrap r45:** Stage 5 base-rootfs archive creation now runs with root privileges so protected files in the verified rootfs can be read instead of producing permission-denied tar errors.
- [x] Stage 5 explicitly unmounts and verifies the bootstrap bind/virtual mounts are gone before creating the archive, including the external sources/packages/build-work mounts.
- [x] Archive creation now checks the actual `tar` exit status. If compression fails, the partial archive is deleted and Stage 5 returns failure instead of printing a false success message.
- [x] The completed base archive is immediately tested with `tar -tJf` and sanity-checked for required BFSOS files (`/usr/bin/bash`, `/usr/bin/pkgmk`, `/etc/os-release`).
- [x] When Stage 5 is entered through sudo from the interactive menu, ownership of the finished archive is returned to the invoking user.
- [ ] **Regression test:** Re-run Stage 5 and verify no `Permission denied` messages occur, the archive passes validation, and an intentionally forced tar failure is reported as failure with no partial archive retained.

### Bootstrap toolchain archive safety
- [x] **IMPLEMENTED in bootstrap r45:** Toolchain archive compression no longer dumps the complete verbose tar member list to the interactive terminal.
- [x] Toolchain archive creation explicitly checks the compression exit status and deletes a partial archive on failure.
- [x] The archive is verified with `tar -tJf` and sanity-checked for the compiler, linker, and `pkgmk` before Stage 1 reports archive success.
- [ ] **Regression test:** On the next clean Stage 1 run, verify concise compression output, successful integrity/payload checks, and correct failure handling if archive creation is deliberately interrupted.

### Bootstrap Stage 5 success-screen cleanup
- [x] **IMPLEMENTED in bootstrap r45:** After a successful Stage 5 base archive operation, return directly to the Bootstrap main menu instead of showing `Operation completed successfully.` / `Press Enter to return to the menu...`.
- Real Stage 5 failures still report their nonzero status and retain the pause so the error can be read.

### Bootstrap Stage 3 success-screen cleanup
- [x] **IMPLEMENTED in bootstrap r45:** After a successful Stage 3 rebuild, return directly to the Bootstrap main menu instead of showing the redundant success/pause screen.
- Stage 2 uses the same direct-return behavior after success.

### Bootstrap time synchronization audit
- [x] **IMPLEMENTED in bootstrap r45:** Root stages launched from the interactive Bootstrap menu no longer re-run the startup time synchronization when `sudo` re-enters `bootstrap.sh`.
- A top-level invocation still performs the normal startup synchronization; child stage invocations receive `BFS_SKIP_TIME_SYNC=yes`.
- This removes the observed duplicate sync before Stage 3 and Stage 4 while preserving clock synchronization when bootstrap is initially launched.
- [ ] **Regression test:** Run Stages 1-5 through the interactive menu and confirm only the initial bootstrap startup performs time synchronization.

### Bootstrap Stage 3 `build-work` mount cleanup — implementation update
- [x] **IMPLEMENTED in bootstrap r45:** The installed/final `pkgmk` work directory is now `/var/cache/pkg/build-work/pkgmk-$name`, a removable child directory beneath the bind mount, rather than the bind-mount root `/var/cache/pkg/build-work`.
- This prevents pkgmk cleanup from attempting to remove the active mount point and producing `Device or resource busy`.
- [x] The bootstrap unmount helper now returns a real error if a busy bootstrap mount cannot be unmounted instead of repeatedly retrying forever.
- [ ] **Regression test:** Run Stage 3 and confirm no `rm: cannot remove '/var/cache/pkg/build-work': Device or resource busy` warning appears and all bootstrap mounts are gone afterward.



### Bootstrap Stage 3 `build-work` mount cleanup
- [x] **FIX IMPLEMENTED in bootstrap r45; regression test pending:** During Stage 3, `pkgmk` emitted `rm: cannot remove '/var/cache/pkg/build-work': Device or resource busy`, but the package build continued.
- Investigation confirmed `/tmp/lfs-rootfs/var/cache/pkg/build-work` is an active overlay-backed mount sourced from the live environment/project `build-work` path.
- This is separate from the locale fixes and was not caused by changing `LC_ALL`/`LANG`.
- Do not unmount the work directory while a package is actively building.
- Review the bootstrap Stage 3 mount/setup and cleanup logic after the current build completes.
- If the `build-work` mount is intentional, cleanup must remove/clean the contents safely without attempting to `rm` the active mount point itself.
- Ensure cleanup unmounts the work directory at the appropriate end-of-stage/exit path before attempting to remove the mount-point directory.
- Verify normal completion, failure, interruption, and rerun paths do not leave stale `build-work` mounts behind.
- [ ] **Regression test:** On the next clean Stage 3 run, confirm there are no `Device or resource busy` cleanup messages and no stale `build-work` mount remains after Stage 3 exits.



### Bootstrap locale warning root cause and fixes
- [x] **COMPLETED / ROOT CAUSE IDENTIFIED:** Repeated Stage 3 locale warnings were traced to explicit UTF-8 locale overrides rather than random bootstrap behavior.
- Upstream `pkgutils 5.40.12` sets `LC_ALL=C.UTF-8` in `pkgmk.in` (`pkgmk`), which is unsafe during early BFSOS bootstrap phases because `C.UTF-8` is not guaranteed to exist yet.
- The running temporary-toolchain copy of `pkgmk` was corrected from `LC_ALL=C.UTF-8` to `LC_ALL=C`.
- The BFSOS `ports/core/pkgutils/Pkgfile` was updated so `bootstrap_build()` patches upstream `pkgmk.in` to use `LC_ALL=C` before installing the temporary-toolchain copy.
- **Historical note superseded by #111:** the packaged `/usr/bin/pkgmk` was initially forced to plain `C`; final pkgutils now dynamically selects `C.UTF-8`/`C.utf8` when available and falls back to `C` only when necessary.
- The GCC port was also found to force `LANG=en_US.UTF-8`; `ports/core/gcc/Pkgfile` was changed to use `LANG=C` for bootstrap/build consistency.
- Keep the global bootstrap environment on `LANG=C`, `LC_ALL=C`, and `LANGUAGE=C`.
- [ ] **Verification pending on next clean bootstrap/RC run:** confirm Stage 1/2/3 no longer produce the previous flood of `setlocale: LC_ALL: cannot change locale (C.UTF-8)` warnings.
- If isolated locale warnings remain after a clean rebuild, capture the exact package/log and investigate only that package rather than changing the global locale policy again.
- These locale fixes should be pushed to both the main BFSOS project and the separate ports repository so the bootstrap and port trees remain consistent.

### Bootstrap Stage 3 locale regression check
- [ ] During the next clean Stage 3 rebuild, verify the **revised #111 policy**: `pkgmk` selects an available `C.UTF-8`/`C.utf8` locale when present (needed for UTF-8 archive pathnames) and falls back to plain `C` only when no UTF-8 C locale exists. GCC/build subprocesses must not reintroduce an unavailable locale.
- Check the newly installed temporary-toolchain `pkgmk` with `grep -nE 'LC_ALL|LANG' .../pkgmk` as a regression check after pkgutils is rebuilt.



### Bootstrap Stage 3 time synchronization
- [x] **FIX IMPLEMENTED in bootstrap r45; regression test pending:** Remove the redundant time synchronization step from Bootstrap Stage 3.
- Time is already synchronized when `bootstrap.sh` is initially launched, so Stage 3 should not perform another automatic time sync before rebuilding the base system with the final toolchain.
- Preserve the initial bootstrap startup time synchronization; this change applies specifically to the extra Stage 3 sync.



### Pre-1.0 optional software and console usability checks
- [x] **IMPLEMENTED / BARE-METAL VERIFIED:** GPM is selectable from Optional Software, installs successfully, and `gpm.service` was confirmed running automatically after boot on the 2026-08-15 bare-metal RC test.
- Check whether a `gpm` port already exists in the BFSOS ports tree. If it does not, create and validate a proper GPM port.
- Add **GPM console mouse support** to the installer Optional Software menu.
- If selected, install GPM and enable/configure the appropriate systemd service so console mouse selection/paste works on a real text console.
- Verify that leaving GPM unselected does not alter the default install.

- [ ] **Bare-metal verification of installer console text-size options before BFSOS 1.0.**
- Verify all existing console font/text-size choices on a real Linux virtual console, not only through QEMU/SPICE or SSH.
- Confirm that selecting each size changes the installer console immediately and that returning to **Default** restores the expected normal size.
- Verify the selected persistent font is written correctly to `/etc/vconsole.conf`.
- After first boot, verify `systemd-vconsole-setup` applies the selected font correctly.
- Confirm the requested font files actually exist in the base system and that any fallback behavior is sensible and visible rather than silently masking a missing font.
- Treat broken/nonfunctional text-size selection as a pre-1.0 installer usability bug.

### Bootstrap Stage 2 completion return behavior
- [x] **FIX IMPLEMENTED in bootstrap r45; regression test pending:** Remove the extra terminal completion/pause screen shown after Bootstrap Stage 2 completes successfully.
- Current behavior displays:
  - `Operation completed successfully.`
  - `Press Enter to return to the menu...`
- After a successful Stage 2 completion, return directly to the **Bootstrap main menu** instead of requiring an extra Enter keypress.
- Keep actual Stage 2 success/failure status visible in the Bootstrap menu itself.
- Do not remove or suppress real error dialogs/messages; this change applies only to the redundant success/pause screen after a successful Stage 2 run.



### BFSOS 1.0 public-release documentation and post-1.0 installer UX roadmap
- [x] **INITIAL 1.0-RC DOCUMENTATION REWRITE IMPLEMENTED in r96; final release polish remains gated by regression results:** `README.md` now documents BFSOS architecture, bootstrap stages, package management, installer/storage capabilities, logs, limitations, and support. Revisit final release/stability wording once the storage/RAID/configuration matrix has passed.
- The 1.0 README/docs should clearly explain what BFSOS is, current release/stability status, supported architecture, supported installation/storage configurations, build/install workflow, known limitations, where logs are stored, and how users should report useful bugs/issues.
- Clearly distinguish the **core BFSOS system** from the broader **non-core ports collection**, which will continue to receive cleanup and tooling work after core 1.0 validation.
- After BFSOS 1.0 final is published with polished documentation and usable release/install artifacts, consider/prepare a **DistroWatch submission** to bring additional testers and users to the project.
- Wider public exposure is intended to provide more real-world hardware/configuration coverage and additional bug reports, but should follow—not precede—the 1.0 RC validation cycle.

#### Post-1.0 / target 1.1 timezone and locale selector improvements
- [ ] **Post-1.0 enhancement (target 1.1):** Replace or enhance the current timezone prompt with a Dialog-driven hierarchical/scrollable selector.
- Timezone selection should allow the user to choose a region first (for example `America`, `Europe`, `Asia`) and then move through/select the appropriate city/location from a list.
- Provide consistent **Back**, **Select/Continue**, keyboard navigation, and text-mode fallback behavior matching the rest of the installer.
- [ ] **Post-1.0 enhancement (target 1.1):** Replace or enhance locale selection with a scrollable Dialog checklist/radiolist based on available locales.
- Keep `en_US.UTF-8` as the normal/default user locale unless the user chooses another locale.
- Allow additional locales to be selected/generated when desired, while allowing the system default `LANG` to be chosen separately.
- **The `C` locale must always remain available and must not be removable/disableable by the locale-selection UI.**
- Preserve use of the `C` locale for bootstrap/build operations where deterministic output or operation before the full locale environment exists is desirable.
- These timezone/locale UI improvements are **not BFSOS 1.0 release blockers** unless the existing selectors prove functionally broken during RC testing. Avoid adding unnecessary installer feature risk immediately before 1.0 final.
- These are installer usability improvements suitable for the **1.x series (preferably 1.1)** rather than requiring a 2.0 release.



### BFSOS 1.0-rc1 release-candidate milestone
- [x] **RC1 CANDIDATE CONDITION MET FOR THIS COMPLEX BARE-METAL RUN:** the installation completed and the resulting BFSOS system booted successfully. Remaining storage-matrix/regression tests still gate final 1.0 promotion.
- The immediate release-candidate priority is validation of the **core operating system, bootstrap, installer, boot path, storage layouts, RAID combinations, encryption/LVM/Btrfs configurations, and other supported installation scenarios**.
- Over the next several days, test the remaining RAID/storage/configuration combinations and correct any core/bootstrap/installer/boot regressions discovered during those tests.
- A failure of the current installation to boot is considered a **release-candidate blocker** and must be fixed and retested before promoting the build to 1.0-rc1 status.
- Minor/non-blocking tracker cleanup can continue through the 1.0 release-candidate cycle while the supported installation configurations are validated.
- **Non-core ports are not a 1.0-rc1/core release blocker at this stage.** The broader non-core ports tree is known to need substantial cleanup and should be handled after the 1.0 RCs have established that the core OS and supported installation/storage configurations are reliable.
- After the RAID/configuration matrix is verified through the 1.0 RC cycle and no release-blocking core issues remain, target the final **BFSOS 1.0** release.
- Following core 1.0 validation, shift development emphasis toward repairing/maintaining the non-core ports collection and developing better **ports management, validation, update, and maintenance tooling**.



### Bootstrap time synchronization behavior
- [x] **COMPLETED / VERIFIED:** Synchronize system time once when `bootstrap.sh` starts.
- Do **not** redundantly synchronize time again before Bootstrap Stage 2 when continuing in the same running bootstrap session.
- If the machine is rebooted or a new bootstrap session is started, launching `bootstrap.sh` performs the startup time synchronization again.
- This keeps Stage 2 from doing unnecessary duplicate time-sync work while still ensuring a fresh bootstrap session begins with a corrected clock.



### Bootstrap Stage 1 toolchain archive compression output
- [x] **FIX IMPLEMENTED in bootstrap r45; regression test pending:** After Bootstrap Stage 1 verification succeeds, hide/suppress the verbose toolchain archive compression output during normal interactive use.
- The user does not need to watch the full compression file/progress stream after verification has already completed successfully.
- Show a concise status such as **Compressing toolchain archive...** while the archive is being created, then report the completed archive path/size or a clear error if compression fails.
- Preserve detailed compression output in the appropriate bootstrap log for troubleshooting rather than filling the interactive terminal/menu.



### Download/package failure messaging in bootstrap and installer
- [x] **IMPLEMENTED in bootstrap r50 / installer r40; regression test pending:** Added menu-level failure dialogs/text fallbacks with exit status, latest log context, and last URL when detectable. Bootstrap failures return to the Bootstrap menu; installer package operations record structured failure context and the parent installer displays it instead of silently dropping to raw terminal output.
- **Observed bootstrap failure:** MPC source download returned HTTP 404 and `pkgmk` exited with status 4. Bootstrap Stage 1 terminated without a clear menu-level explanation, while Bootstrap Stage 2 later displayed the raw error text but still did not use the normal dialog/menu workflow.
- **Bootstrap requirement:** Catch source/download/build failures and show a **dialog error box** when Dialog mode is available. The dialog should identify the package or operation, show the failed URL when known, summarize the underlying downloader/build error, include the exit status, and show the preserved package log path.
- **Bootstrap navigation:** The failure dialog should have a **Continue** button. Selecting Continue must return the user directly to the **Bootstrap main menu** without exiting `bootstrap.sh`.
- **Installer review:** The installer currently invokes `ports -u`, `prt-get sysup`, and `prt-get depinst` directly inside a strict-error shell path. A download/build failure from those commands can therefore abort the installation path without installer-specific UI/context unless explicitly caught.
- **Installer requirement:** Catch ports synchronization, mandatory upgrade, and optional package-install failures and show a **dialog error box** with the failed operation/package when known, failed URL when available, useful underlying output, exit status, and installer log path. Preserve the installer log before cleanup.
- **Installer navigation:** The failure dialog should have a **Continue** button. Selecting Continue must return the user to the **installer main menu/configuration screen**, not terminate the installer or dump directly to the shell.
- **Text-mode fallback:** If Dialog is unavailable, print the same failure details in text mode, prompt **Press Enter to continue**, then return to the respective main menu.
- **Do not hide the real error:** The dialog should summarize the failure, but the full raw downloader/build output must remain in the corresponding log for troubleshooting.
- **Regression tests:** Deliberately use a bad source URL once in Bootstrap Stage 1, once in Bootstrap Stage 2, and once during installer package installation. In all cases verify the error is shown in the appropriate dialog/text fallback, the log path is visible, and Continue returns to the correct main menu without terminating the parent workflow.

### Bootstrap Stage 3 availability status
- [x] **COMPLETED / VERIFIED:** Correct Stage 3 (`Rebuild base system with final toolchain`) status logic.
- Stage 3 now shows **[PENDING]** until the required temporary-toolchain/base-system prerequisite stages are complete.
- After Stage 2 is complete, Stage 3 changes to **[AVAILABLE]**.
- After Stage 3 itself is completed, it shows **[COMPLETE]**.
- Corrected in both the dialog and text-fallback bootstrap menus.
- Verified during testing on August 11, 2026: the corrected behavior now appears as intended.


**Installer:** `install-bfs-menu-v50-luks-auto-cryptsetup.sh`\
**Test focus:** RAID + LUKS + LVM\
**Status:** Active testing

## Issues Found

### 1. RAID selection summary is plain text instead of Dialog

-   [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
-   **Area:** RAID creation / RAID type summary
-   **Current behavior:** After choosing a RAID type, the installer
    drops out of the Dialog UI and prints a text summary in the
    terminal.
-   **Observed output:**

``` text
# RAID selection summary

RAID type     : RAID 5
Minimum disks : 3
Layout        : Striping with distributed parity
Redundancy    : One drive may fail
Performance   : Fast reads; good general-purpose writes
Usable space  : Capacity of N-1 members

Press Enter to continue...
```

-   **Desired behavior:** Display this information in a Dialog
    `--msgbox` (or equivalent) and return cleanly to the Dialog
    workflow.
-   **Priority:** UI cleanup
-   **Regression test:** Select each supported RAID level and verify its
    summary appears inside Dialog without dropping back to the terminal.

### 4. RAID creation result/progress is plain text instead of Dialog
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** RAID creation / post-create status
- **Current behavior:** After `mdadm` starts the array, the installer drops to plain terminal output showing `/proc/mdstat`, recovery percentage, estimated completion time, and `Press Enter to continue...`.
- **Observed example:**

```text
mdadm: array /dev/md0 started.

Personalities : [raid4] [raid5] [raid6]
md0 : active raid5 ...
      [>....................]  recovery = 0.0% ...
      bitmap: 2/2 pages [8KB], 65536KB chunk

Press Enter to continue...
```

- **Desired behavior:** Keep the user in Dialog. Show array creation success and status in a Dialog `--msgbox`; optionally use a Dialog `--gauge` if the installer chooses to monitor initial RAID recovery/sync progress.
- **Priority:** UI cleanup
- **Regression test:** Create RAID5 and verify the post-create status never drops back to the terminal UI.

### 5. LUKS device selection is plain text and dumps full `lsblk` output
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation / encrypted-device selection
- **Current behavior:** Choosing "Create a new LUKS container" prints a full `lsblk -fp` style device tree to the terminal, including loop devices, optical media, whole disks, mounted build storage, RAID members, and the assembled MD array, then asks `Block device to encrypt:` as a raw text prompt.
- **Observed behavior:** The terminal shows `/dev/loop0`, `/dev/sr0`, `/dev/vda*`, `/dev/vdb1`-`/dev/vdf1`, `/dev/md0`, and `/dev/vdg`, followed by:

```text
Block device to encrypt:
```

- **Desired behavior:** Use a Dialog selection list for LUKS targets. Show only sensible encryptable block-device candidates, with device path, size, type, and current filesystem/signature. Exclude loop devices, optical media, mounted installer/build media, whole disks when a child partition is the intended unit, and RAID member partitions that are already claimed by an active MD array. The assembled `/dev/md0` should be selectable for the RAID -> LUKS -> LVM test.
- **Priority:** UI + safety cleanup
- **Regression test:** Enter the LUKS create flow with an active RAID array and verify `/dev/md0` is offered while `/dev/vdb1`-`/dev/vdf1`, `/dev/loop0`, `/dev/sr0`, and `/dev/vdg` are not offered as accidental targets.

### 6. `cryptsetup luksFormat` destructive confirmation is raw terminal input
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation / destructive confirmation
- **Current behavior:** `cryptsetup luksFormat` exposes its native terminal warning and requires the user to type the exact confirmation text:

```text
WARNING!
This will overwrite data on /dev/md0 irrevocably.

Are you sure? (Type 'yes' in capital letters):
```

- **Desired behavior:** The installer should present its own clear Dialog `--yesno` destructive-action warning before invoking `cryptsetup`. After explicit confirmation, invoke cryptsetup in a non-interactive/force-confirmed mode where supported so its native typed confirmation does not break the Dialog workflow. Password/passphrase entry should remain secure and must not be exposed on the command line.
- **Priority:** UI + safety cleanup
- **Regression test:** Create a LUKS container and verify the destructive confirmation occurs entirely through Dialog, Cancel/No safely returns without formatting, and no plaintext passphrase appears in process arguments or logs.

### 7. LUKS mapping-name prompt is plain text
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation / opening newly created container
- **Current behavior:** After creating a LUKS container, the installer asks `Mapping name to open now [leave blank to skip]:` using a raw terminal prompt.
- **Desired behavior:** Use a Dialog `--inputbox`, with clear guidance that this creates `/dev/mapper/<name>`, plus a Cancel/Skip path. Consider suggesting a sensible default based on intended use (for example `cryptroot` for `/` and `cryptraid` for an encrypted RAID device).
- **Priority:** UI cleanup
- **Regression test:** Create LUKS on a partition and on an MD array; verify mapping-name entry, skip, and cancel all remain in Dialog and produce the expected mapper device.

### 8. LUKS mapping name should be required
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation / mapper naming
- **Current behavior:** The mapping-name prompt allows a blank value to skip opening the newly created LUKS container.
- **Desired behavior:** Require a valid mapping name when creating a LUKS container through the installer. Do not allow an empty name. Re-prompt on blank or invalid input and explain that the resulting device will be `/dev/mapper/<name>`. Provide sensible suggested defaults such as `cryptroot` for an encrypted root partition and `cryptraid` for an encrypted RAID device.
- **Validation:** Reject whitespace, `/`, and names that would conflict with an existing `/dev/mapper` mapping. Keep an explicit Cancel/Back action separate from an empty mapping name.
- **Priority:** Workflow + UI cleanup
- **Regression test:** Verify blank and invalid names are rejected, existing mapper names cannot be reused accidentally, and a valid name opens the LUKS device successfully.

### 9. LUKS passphrase entry and post-open pause drop to plain terminal UI
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation/opening / passphrase and completion
- **Current behavior:** The LUKS passphrase is requested using the raw `cryptsetup` terminal prompt, and after the operation the installer uses a plain `Press Enter to continue...` pause.
- **Desired behavior:** Keep the workflow in Dialog. Use a secure Dialog password box for passphrase entry and confirmation, then feed the passphrase to `cryptsetup` without exposing it in command-line arguments, logs, shell tracing, or temporary plaintext files. Replace the terminal `Press Enter to continue...` with a Dialog success/status message.
- **Safety:** Never echo the passphrase. Ensure installer logging/xtrace cannot capture it. Clear shell variables containing the passphrase as soon as practical.
- **Priority:** UI + security cleanup
- **Regression test:** Create and open LUKS successfully from Dialog; verify passphrase is hidden, confirmation mismatch is handled cleanly, no passphrase appears in logs/process arguments, and completion returns through Dialog.

### 10. Newly created LUKS containers are not remaining open
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS creation / mapper activation
- **Current behavior:** After creating LUKS containers, `lsblk` correctly shows `crypto_LUKS` on `/dev/vda4` and `/dev/md0`, but the expected mapper devices are inactive (`cryptsetup status cryptraid` and `cryptsetup status luksroot` report inactive).
- **Desired behavior:** When the installer requires a mapping name during LUKS creation, successfully open the new container immediately and verify `/dev/mapper/<name>` exists before returning to the storage menu. If opening fails, show a Dialog error and remain in the LUKS workflow rather than silently continuing.
- **Validation:** After `cryptsetup open`, verify `cryptsetup status <name>` is active and `test -b /dev/mapper/<name>` succeeds.
- **Priority:** Functional LUKS workflow bug
- **Regression test:** Create LUKS on a normal partition and on an MD array; both mappings must remain active and be selectable by the filesystem/LVM setup screens until installer cleanup or an explicit Close action.

### 11. LVM physical-volume selection should be a Dialog device selector
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LVM setup / physical-volume creation
- **Current behavior:** The installer asks the user to type a block-device path manually when creating an LVM physical volume.
- **Desired behavior:** Present eligible devices in a Dialog menu/checklist navigable with Up/Down and selectable with Space/Enter as appropriate. Show useful metadata such as device path, size, type, and current filesystem/signature.
- **Filtering/safety:** Include valid devices and active mapper devices such as `/dev/mapper/cryptraid`; exclude loop/optical devices, mounted installer media, active RAID member partitions, and devices already consumed by another storage layer unless explicitly appropriate.
- **Selection model:** Support selecting one or more PV devices if the installer supports multi-PV volume groups. Provide Back/Cancel without terminating the installer.
- **Priority:** UI + safety cleanup
- **Regression test:** With RAID -> LUKS active, verify `/dev/mapper/cryptraid` appears as an eligible PV and can be selected entirely through Dialog without manually typing its path.

### 12. LVM operation success messages use plain `Press Enter to continue...`
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LVM setup / post-operation feedback
- **Current behavior:** After successful LVM operations, such as creating logical volume `var`, the installer drops to terminal text:

```text
Logical volume "var" created.

Press Enter to continue...
```

- **Desired behavior:** Replace terminal pauses after successful PV/VG/LV operations with Dialog `--msgbox` success messages and return directly to the appropriate LVM Dialog menu.
- **Priority:** UI cleanup
- **Regression test:** Create PVs, a VG, and multiple LVs and verify every success/failure result remains in Dialog with no raw `Press Enter to continue...` screens.

### 13. LVM status/summary output is plain terminal text
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LVM setup / status summary
- **Current behavior:** The installer prints raw `pvs`, `vgs`, and `lvs` output to the terminal, followed by `Press Enter to continue...`.
- **Observed example:** PV `/dev/mapper/cryptraid`, VG `bfs-vg`, and LVs `home` and `var` are shown using the native LVM table output.
- **Desired behavior:** Render a concise LVM summary inside Dialog, ideally using a `--textbox`, `--msgbox`, or formatted menu/table-style screen. Show PV, VG, LV names, sizes, and free space while keeping the user inside the Dialog workflow.
- **Priority:** UI cleanup
- **Regression test:** Open the LVM status/review screen after creating PV/VG/LVs and verify no raw terminal table or `Press Enter to continue...` prompt appears.

### 14. Filesystem selector should hide LUKS backing devices when their decrypted layer is in use
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** Filesystem device selection / storage-layer filtering
- **Current behavior:** The filesystem selector still offers `/dev/md0` and `/dev/vda4` even though both contain active LUKS containers. Selecting or formatting either backing device would overwrite the encryption layer.
- **Desired behavior:** When a block device has a LUKS container and its decrypted mapper is active or consumed by another storage layer, hide the encrypted backing device from normal filesystem-format/mount selection. Show only the usable top-level devices, such as `/dev/mapper/luksroot` and LVs built on `/dev/mapper/cryptraid`.
- **Safety:** Do not allow accidental filesystem formatting of an active LUKS backing device. If an advanced workflow ever exposes it, mark it clearly as `LUKS backing device — do not format` and require an explicit destructive override.
- **Priority:** Safety + UI cleanup
- **Regression test:** With LUKS on `/dev/vda4` and `/dev/md0`, verify neither backing device appears as a normal filesystem target while their decrypted/derived devices are active.

### 15. Remove plain `Press Enter to continue...` after filesystem selection
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** Filesystem selection / transition to next installer stage
- **Current behavior:** After all filesystem targets and mount points have been selected, the installer drops to a raw `Press Enter to continue...` prompt.
- **Desired behavior:** Prefer no extra pause at all: once filesystem selection is complete and validated, proceed directly to the next installer stage. If user confirmation is needed before formatting/mounting, use a Dialog summary/confirmation screen instead of a terminal pause.
- **Priority:** UI/workflow cleanup
- **Regression test:** Complete filesystem assignments and verify the installer either advances directly or displays a meaningful Dialog confirmation; no raw Enter prompt should appear.

### 16. Remove plain pause after base archive stage
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** Base archive / transition to next installer stage
- **Current behavior:** After the base archive operation completes, the installer stops at a raw `Press Enter to continue...` prompt.
- **Desired behavior:** On successful completion, continue automatically to the next installer stage. Do not add a Dialog message merely to replace an unnecessary terminal pause. Use Dialog only when there is meaningful information, a warning, an error, or a decision the user needs to make.
- **Priority:** UI/workflow cleanup
- **Regression test:** Complete the base archive stage successfully and verify the installer advances automatically with no raw Enter prompt or redundant OK dialog.

### 17. Installation summary incorrectly reports no encrypted devices
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** Final installation review / LUKS summary
- **Current behavior:** The BFS Installation summary reports `LUKS Encryption: Enabled YES` but `Encrypted devices: no`, even though this test has LUKS containers on `/dev/vda4` (opened as `/dev/mapper/luksroot`) and `/dev/md0` (opened as `/dev/mapper/cryptraid`, then used by LVM).
- **Desired behavior:** Detect and list the actual encrypted backing devices and mapper names in the final review, including LUKS devices that are underneath LVM/RAID layers.
- **Expected example:** `/dev/vda4 -> luksroot` and `/dev/md0 -> cryptraid`.
- **Priority:** Functional review/reporting bug
- **Regression test:** Build RAID5 -> LUKS -> LVM plus a separate LUKS root and verify the final review reports both encrypted devices and their mappings rather than `no`.
### 18. Remove raw `Press Enter to continue...` before BFS Installation summary
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** Transition into final installation review
- **Current behavior:** A raw terminal `Press Enter to continue...` appears before the BFS Installation summary.
- **Desired behavior:** Continue directly into the Dialog review screen unless an actual user decision is required.
- **Priority:** UI/workflow cleanup

### 19. Fatal crypttab generation failure with existing/reopened LUKS mappings
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed.sh`
- **Area:** LUKS detection / `/etc/crypttab` generation
- **Current behavior:** The installer correctly detects that encrypted storage is present, but `generate_crypttab()` produces zero records and aborts with:

```text
ERROR: Encrypted storage was detected, but no crypttab entries could be generated.
```

- **Test topology:** `/dev/vda4 -> luksroot -> /` and `/dev/md0 -> cryptraid -> LVM -> home/var`.
- **Likely failure point to verify:** `crypt_mapping_records()` discovers `crypt` nodes through `lsblk`, then relies on `lsblk ... PKNAME` to derive the encrypted backing device. Existing/reopened device-mapper stacks may not be represented the way this code expects.
- **Desired behavior:** Discover active LUKS mappings from the actual block-device topology regardless of whether they were created in the current installer process or opened before restarting the installer. Generate entries for both root and encrypted RAID mappings.
- **Expected crypttab mappings:** `luksroot` backed by the LUKS UUID of `/dev/vda4`; `cryptraid` backed by the LUKS UUID of `/dev/md0`.
- **Priority:** Critical functional blocker
- **Regression test:** Restart installer with pre-opened LUKS mappings, select filesystems on mapper/LVM descendants, and verify `/etc/crypttab` is generated correctly without relying on current-session LUKS state.


### 20. Base archive path prompt is not using Dialog
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r2.sh`
- **Area:** Base archive selection
- **Current behavior:** The installer asks for the base/rootfs archive path using a plain terminal prompt rather than Dialog.
- **Desired behavior:** Use a Dialog `--inputbox` (or a file/path selector if practical) with the detected/default base archive path pre-filled, so the user can accept or edit it without leaving the Dialog UI.
- **Priority:** UI cleanup
- **Regression test:** Reach base archive selection and verify the archive path is requested entirely through Dialog with the default path visible/editable.


### 21. Final installation review does not show configured RAID arrays
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r4.sh`
- **r4 correction:** The earlier `/proc/mdstat` parser checked the wrong field (`$2 ~ /^raid/`) for lines shaped like `md0 : active raid5 ...`, causing `RAID enabled: YES` but an array list of `none`. r4 parses the actual MD status line correctly and reports the live array.
- **Area:** Final installation review / RAID summary
- **Current behavior:** The final review omits the configured software RAID array(s), so the storage summary does not show the RAID layer even when `/dev/md0` is part of the installation topology.
- **Desired behavior:** Add a RAID section to the review showing each array device, RAID level, member devices, size, and current state. For this test topology it should show `/dev/md0`, RAID5, and members `/dev/vdb1 /dev/vdc1 /dev/vdd1 /dev/vde1 /dev/vdf1`.
- **Detection:** Derive the review from actual active MD state (`/proc/mdstat`/`mdadm --detail`) rather than only installer-session variables, so restarted/resumed installs are reported correctly.
- **Priority:** Review/reporting correctness
- **Regression test:** Restart the installer with an existing active RAID5 and verify the final review still lists the array, level, and members.

### 22. Filesystem and mount-point assignment needs a single multi-entry Dialog workflow
- [x] Partial workflow fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r2.sh`
- **Note:** Replaced the repeated `Add another?` prompt with a persistent selector and explicit `Done selecting filesystems` action. A fuller Add/Edit/Remove planner can still be refined later if desired.
- **Area:** Filesystem selection / mount-point assignment
- **Current behavior:** The installer configures one filesystem/mount point at a time and repeatedly asks whether the user wants to add another partition/filesystem.
- **Desired behavior:** Replace the repeated yes/no loop with a persistent Dialog assignment screen. The user should be able to move through eligible devices, add/edit/remove assignments, and see the complete filesystem plan before selecting `Done`.
- **Suggested workflow:** Show eligible top-level devices in one menu; selecting a device opens its filesystem/format/mount-point options; return to the same assignment screen with the configured value displayed. Provide `Add/Edit`, `Remove`, `Back`, and `Done` actions rather than repeatedly asking `Add another?`.
- **Safety:** Continue hiding consumed backing devices such as active LUKS parents and RAID member partitions. Clearly identify EFI, boot, swap, mapper devices, and LVs.
- **Validation on Done:** Require exactly one `/`, reject duplicate mount points, validate EFI/boot choices where applicable, and show a final filesystem plan before destructive formatting.
- **Priority:** Major UI/workflow improvement
- **Regression test:** Configure `/`, `/boot`, `/boot/efi`, swap, `/home`, and `/var` without answering a repeated yes/no prompt after each assignment.


### 23. make-ca package conflicts with ca-certificates ownership
- [x] Fix
- **Implemented in:** `Pkgfile-make-ca-release4-fixed`
- **Area:** Package installation / CA trust store
- **Current behavior:** `make-ca 1.16.1-3` tries to install `etc/ssl/certs/ca-certificates.crt`, but that path is already owned by the installed `ca-certificates` package, causing `pkgadd` to abort.
- **Confirmed owner:** `ca-certificates` owns `etc/ssl/certs/ca-certificates.crt`; current link is `/etc/ssl/certs/ca-certificates.crt -> /etc/ssl/cert.pem`.
- **Desired behavior:** Do not have `make-ca` package own a path already owned by `ca-certificates`. Remove the compatibility symlink from the make-ca package and ensure the CA trust-store packages provide a consistent chain that httpup can use.
- **Priority:** Critical packaging/install blocker
- **Regression test:** Fresh install with both ca-certificates and make-ca must complete without file-ownership conflicts, and `ports -u` must succeed afterward.


### 24. Add intelligent default mount points during filesystem assignment
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Area:** Filesystem / mount-point assignment
- **Current behavior:** Mount points must be entered manually even when the selected device name or filesystem makes the intended mount point obvious.
- **Desired behavior:** Pre-fill a sensible mount-point suggestion while keeping it editable by the user.
- **Suggested defaults:**
  - LV named `home` -> `/home`
  - LV named `var` -> `/var`
  - LV named `root` -> `/`
  - dm-crypt mapping named `luksroot` -> `/`
  - `ext2` partition -> `/boot` when `/boot` is not already assigned
  - `vfat`/FAT32 partition -> `/boot/efi` when `/boot/efi` is not already assigned
  - swap -> `swap`
- **Safety:** Defaults are suggestions only. Do not overwrite an existing assignment or guess for generic Btrfs/ext4/XFS devices without a useful device/LV/mapping name.
- **Priority:** Filesystem workflow improvement
- **Regression test:** Selecting `bfs-vg/home`, `bfs-vg/var`, `/dev/vda2` ext2, `/dev/vda1` vfat, and `luksroot` should pre-fill `/home`, `/var`, `/boot`, `/boot/efi`, and `/` respectively.
### 25. Show complete filesystem plan in the final Yes/No confirmation
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Area:** Filesystem assignment confirmation
- **Current behavior:** The final confirmation page presents only Yes/No, so the user cannot verify what was selected before continuing.
- **Desired behavior:** The confirmation Dialog must display the complete pending filesystem plan above the Yes/No choice.
- **Display for each assignment:** device, filesystem, mount point, and whether it will be formatted/reformatted. Include swap explicitly.
- **Example information:** `/dev/mapper/luksroot -> btrfs -> /`, `/dev/bfs-vg/home -> btrfs -> /home`, `/dev/bfs-vg/var -> btrfs -> /var`, `/dev/vda2 -> ext2 -> /boot`, `/dev/vda1 -> vfat -> /boot/efi`, `/dev/vda3 -> swap`.
- **Behavior:** `Yes` accepts the displayed plan; `No` returns to the filesystem assignment screen so selections can be corrected rather than discarding the whole workflow.
- **Priority:** Safety / usability
- **Regression test:** Configure multiple filesystems and verify the final Yes/No Dialog visibly lists every selected device, filesystem, mount point, format choice, and swap before the user commits.

### 26. Convert "Show Current Storage Devices" to Dialog and remove Enter pause
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Area:** Storage menu / current-device display
- **Current behavior:** `Show Current Storage Devices` dumps storage information to the terminal and then uses a raw `Press Enter to continue...` pause.
- **Desired behavior:** Capture the storage-device output and display it in a scrollable Dialog window (`--textbox` or equivalent) with normal Dialog navigation such as OK/Back.
- **Required cleanup:** Remove the terminal `Press Enter to continue...` prompt entirely. Closing the Dialog should return directly to the storage menu.
- **Priority:** UI consistency
- **Regression test:** Open `Show Current Storage Devices`; verify no raw terminal output or Enter pause appears.
### 27. Preselect git and wget in Optional Software
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Area:** Optional Software Dialog
- **Current behavior:** `git` and `wget` are not enabled by default.
- **Desired behavior:** Show both `git` and `wget` as selected/on by default while still allowing the user to deselect either package.
- **Priority:** Default-package usability
- **Regression test:** Open Optional Software on a fresh installer run and verify both `git` and `wget` are initially checked.

### 28. Add save/load support for complete installer configuration profiles
- [~] Partial implementation
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh` (profile save/load UI, non-secret core settings, filesystem assignments, device validation)
- **Remaining:** RAID/LUKS/LVM creation is currently imperative in v50, so a profile cannot yet safely recreate those layers from scratch. Finish this when storage setup is refactored into a declarative plan; never store LUKS passphrases.
- **Area:** Installer configuration / main menu
- **Goal:** Allow the user to save the current installer selections to a reusable configuration file and load a saved configuration on a later installer run.
- **Save:** Store non-secret installer choices including hostname, timezone, locale, network configuration, users/user options, storage topology selections, RAID configuration, LUKS device/mapping choices, LVM configuration, filesystem and mount-point assignments, Btrfs/Snapper choices, optional software, base archive choice, bootloader/GRUB choices, and normal/fallback EFI installation choices.
- **Load:** Populate installer state from the selected profile so the user does not need to answer every installer question again.
- **Secrets:** Never store user/root passwords, LUKS passphrases, private keys, or other authentication secrets in the profile. Prompt for those normally when required.
- **Validation:** Loading a profile must validate devices and other machine-specific values against the current system. Missing or changed devices must be clearly flagged and returned to the user for correction; never blindly perform destructive operations using stale device paths.
- **Review:** A loaded profile must still pass through the normal installer review/confirmation screens before destructive actions or installation begin.
- **UI:** Add Dialog options such as `Load configuration`, `Save current configuration`, and `Save configuration as...`.
- **Format:** Use a documented, human-readable configuration format that can be inspected and edited manually.
- **Portability:** Where practical, allow stable identifiers such as UUID/PARTUUID/LABEL in addition to `/dev/...` paths so profiles survive device-name changes.
- **Priority:** Major usability / repeat-install feature
- **Regression test:** Save a complete configuration, restart the installer, load it, verify all non-secret choices are restored, verify passwords/passphrases are still requested, and verify a deliberately missing storage device is detected before any destructive operation.

### 29. Returning from final chroot should go directly back to installer menu
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Area:** Final chroot / installer navigation
- **Current behavior:** After exiting the BFS chroot, the installer prints:

```text
Returned from the BFS chroot.

Press Enter to continue...
```

- **Desired behavior:** Remove the terminal pause entirely. After the chroot exits successfully, return directly to the installer menu (or the appropriate post-install menu) without requiring an extra Enter key.
- **UI:** If a message is desired, show it briefly in Dialog or simply return to the menu; do not drop to raw terminal output.
- **Priority:** UI/workflow cleanup
- **Regression test:** Enter the final BFS chroot, exit it, and verify the installer immediately returns to the menu with no raw `Press Enter to continue...` prompt.


### 30. Encrypted storage is not activated automatically at boot
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r4.sh`
- **Area:** GRUB / Dracut kernel command line / encrypted-root boot
- **Severity:** Critical boot blocker
- **Observed first-boot behavior:** GRUB passed the Btrfs root filesystem UUID (`root=UUID=d342daa4-...`) but no `rd.luks.uuid=` parameter. Dracut waited for that Btrfs UUID for roughly 200 seconds, then dropped to the debug shell because `/dev/mapper/luksroot` had never been created.
- **Root LUKS proof:** `/dev/vda4` correctly reports `TYPE=crypto_LUKS` with UUID `d202ab19-7873-49cf-b625-53d4f8471d06`. Manually running `cryptsetup open /dev/vda4 luksroot` immediately exposed the expected Btrfs UUID `d342daa4-1c49-4616-bf94-bc6cd2690055`, after which exiting the Dracut shell allowed boot to continue.
- **Encrypted RAID proof:** The installed system then assembled `/dev/md0` RAID5 successfully with all 5/5 members, but `/dev/mapper/cryptraid` was absent. `/dev/md0` correctly reported `TYPE=crypto_LUKS` with UUID `e46a2023-298f-475e-8627-32847f93411b`. Manually running `cryptsetup open /dev/md0 cryptraid` followed by `vgchange -ay` exposed the `bfs-vg/home` and `bfs-vg/var` LVs and allowed boot to complete.
- **Current GRUB defaults:** `/etc/default/grub` contains only `GRUB_CMDLINE_LINUX_DEFAULT="consoleblank=1800"`.
- **Dracut detection proof:** `dracut --print-cmdline` detects at least the encrypted root and recommends `rd.luks.uuid=luks-d202ab19-7873-49cf-b625-53d4f8471d06`.
- **Desired behavior:** During bootloader/initramfs configuration, derive required Dracut arguments from the actual selected storage topology and add them to the GRUB kernel command line. At minimum include every LUKS container needed for the installed filesystem tree. For this topology that means the root LUKS UUID and the LUKS-on-MD UUID; also ensure the MD/LVM portions required to reach encrypted RAID-backed filesystems are not disabled in early boot.
- **Suggested arguments for this test topology:** `rd.luks.uuid=luks-d202ab19-7873-49cf-b625-53d4f8471d06`, `rd.luks.uuid=luks-e46a2023-298f-475e-8627-32847f93411b`, plus the LVM/MD activation arguments recommended by root-run `dracut --print-cmdline` for the active layout.
- **Installer validation:** Before declaring installation complete, compare the generated GRUB command line with `dracut --print-cmdline`/the detected storage topology and fail or warn if an encrypted root lacks an `rd.luks.uuid=` argument.
- **Regression test:** Rebuild initramfs and GRUB, cold boot with no mappings pre-opened, verify the boot process prompts for required LUKS passphrase(s), creates `luksroot` and `cryptraid` automatically, assembles `/dev/md0`, activates `bfs-vg`, mounts `/`, `/home`, and `/var`, and reaches the normal login without a Dracut/emergency-shell intervention.

- **Confirmed root cause / proof:** Explicit `rd.luks.uuid=` arguments fixed automatic encrypted-root activation. `rd.md=1` alone was not sufficient to assemble the MD array in early boot. Adding `rd.auto` caused `/dev/md0` to assemble automatically with all 5/5 members, after which Dracut found the LUKS container on `/dev/md0`, prompted for it, activated LVM, and booted normally.
- **Permanent implementation:** r4 derives storage arguments dynamically from `/etc/crypttab`, `/etc/fstab`, live LVM metadata, and the detected RAID requirement. It writes storage arguments to `GRUB_CMDLINE_LINUX` in `/etc/default/grub` so they persist across future kernel upgrades and also apply to recovery entries. `consoleblank=1800` remains in `GRUB_CMDLINE_LINUX_DEFAULT`.
- **Generated arguments:** MD RAID adds `rd.auto rd.md=1`; every required crypttab UUID adds `rd.luks.uuid=luks-<UUID>`; every selected filesystem backed by an LV adds `rd.lvm.lv=<VG>/<LV>`.
- **Validation:** After `grub-mkconfig`, r4 verifies that the generated Linux entries contain all required RAID/LUKS/LVM arguments and also checks recovery entries when present.



### 31. "Assemble existing arrays" aborts clean install when no arrays exist
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r6-classic-slackware.sh`
- **Area:** Software RAID / assemble-existing workflow / error handling
- **Observed behavior:** On a deliberately clean target with all previous MD signatures wiped, selecting "Assemble existing arrays" runs `mdadm --assemble --scan`. `mdadm` correctly returns non-zero with `No arrays found in config file or automatically`, but the installer's global ERR trap treats that expected result as fatal and aborts near line 1777.
- **Root cause:** The r5 function attempted to tolerate the command with `set +e`, but a bare failing command can still interact with the installer's ERR trap. The command must execute in a conditional context where failure is explicitly handled.
- **Desired behavior:** No existing arrays is a normal condition on a fresh install. Show a Dialog message explaining that no arrays were found and return to the RAID menu so the user can choose `Create a new array`.
- **Fix:** Run `mdadm --assemble --scan` inside an `if` condition, capture its status without triggering the fatal ERR path, and distinguish "no arrays exist" from a partial/real assembly failure.
- **Regression test:** Wipe all MD member signatures, enter Software RAID -> Assemble existing arrays, verify the installer shows a non-fatal "No existing RAID arrays were found" Dialog and returns to the RAID menu.


### 32. LUKS mapper name is lost after prompt
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r7-classic-slackware.sh`
- **Area:** LUKS create/open workflow / Bash variable scoping
- **Observed behavior:** LUKS2 formatting succeeds, but the installer reports `The new container was created, but /dev/mapper/ could not be opened.` The mapper name is blank, `/dev/md0` contains a valid LUKS2 header, and `/dev/mapper/cryptraid` remains inactive.
- **Root cause:** `ask_mapping_name()` declared a local variable named `mapping` while also receiving `mapping` as the caller's output-variable name. Because Bash local variables are dynamically scoped, `printf -v "$result_variable"` updated the helper's local `mapping`, leaving `luks_menu`'s `mapping` empty.
- **Fix:** Rename the helper-local value to `selected_mapping`, so `printf -v "$result_variable"` writes back to the caller's `mapping` variable.
- **Regression test:** Create a LUKS container on `/dev/md0`, accept the default mapper name `cryptraid`, verify `/dev/mapper/cryptraid` is created and active, then continue into LVM setup.


### 33. Active MD RAID array disappears from LUKS target selector
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r8-classic-slackware.sh`
- **Area:** LUKS target discovery / MD RAID integration
- **Observed behavior:** After creating `/dev/md0`, the RAID array was no longer offered as a target when creating a new LUKS container, even though `/proc/mdstat` showed the array active.
- **Root cause:** LUKS target discovery depended primarily on `lsblk TYPE` matching `raid*`. MD device TYPE reporting can vary with util-linux/array state, so a valid assembled `/dev/md*` device could be omitted.
- **Fix:** Enumerate active MD arrays directly from `/proc/mdstat` first, add them explicitly to the LUKS candidate list, deduplicate them against the later `lsblk` scan, and continue suppressing the individual member partitions.
- **Regression test:** Create `/dev/md0`, enter LUKS -> Create a new LUKS container, verify `/dev/md0` appears while its member partitions do not.



### 34. Existing LUKS selector duplicates an MD-backed LUKS container
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** LUKS reopen UI / device deduplication
- **Observed behavior:** A LUKS container on `/dev/md0` appeared once for every RAID member because recursive `lsblk` repeated the same MD path.
- **Fix:** Deduplicate LUKS candidates by canonical device path before building the Dialog menu.
- **Regression test:** Close an MD-backed LUKS mapping, choose Open existing LUKS, and verify `/dev/md0` appears exactly once.

### 35. LVM PV selector duplicates RAID/LUKS mapper paths
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** LVM physical-volume UI / device deduplication
- **Observed behavior:** `/dev/mapper/cryptraid` could appear multiple times because recursive `lsblk` repeated descendants beneath each MD member.
- **Fix:** Deduplicate LVM candidate devices by path before presenting the checklist.
- **Regression test:** With RAID -> LUKS active, verify `/dev/mapper/cryptraid` appears exactly once in the PV selector.

### 36. Volume-group creation should select from existing physical volumes
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** LVM UI / volume-group creation
- **Current behavior:** Creating a volume group asks for physical-volume device path(s) as free-form text.
- **Desired behavior:** Query actual initialized physical volumes with `pvs` and present them in a Dialog checklist. Allow selecting one or more PVs with Space, then create the requested VG from those selections.
- **Suggested flow:** `Create PV` -> device checklist -> `pvcreate`; `Create VG` -> deduplicated existing-PV checklist -> `vgcreate`; `Create LV` -> existing-VG selector -> LV name/size -> `lvcreate`.
- **Why:** Prevents typing mistakes, prevents selecting devices that are not initialized PVs, and makes the LVM workflow consistent with the rest of the storage UI.
- **Related cleanup:** Apply the same device-path deduplication rule used for Issues #34/#35 so RAID/LUKS-backed PVs appear only once.
- **Regression test:** Create a PV on `/dev/mapper/cryptraid`, choose Create volume group, verify the PV appears exactly once in the checklist, select it, create `bfs-vg`, and confirm `vgs`/`pvs` show the expected relationship.


### 37. Filesystem confirmation does not show the selected filesystem plan
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** Filesystem assignment / confirmation UI
- **Current behavior:** After selecting devices, filesystem actions, and mount points, the final Yes/No confirmation only asks `Use these filesystem and mount-point selections?` and does not display the actual selections.
- **Expected behavior:** The confirmation screen itself must show every selected device, its mount point, and whether it will be formatted or preserved before the user chooses Yes or No.
- **Required display:** For each selected target show at least `Device`, `Mount point`, and an unambiguous action such as `FORMAT as btrfs`, `FORMAT as ext2`, `FORMAT as vfat`, `FORMAT as swap`, or `KEEP existing filesystem / do not format`.
- **Implementation note:** The installer already builds `storage_selection_summary_text()`, but the current Dialog `--yesno` confirmation does not include that summary text. Embed the generated filesystem plan directly into the confirmation prompt (or use an equivalent confirmation Dialog that presents the full plan before Yes/No).
- **Regression test:** Assign `/`, `/boot`, `/boot/efi`, swap, `/home`, `/var`, etc.; select a mix of format and keep actions; choose Done; verify the very next confirmation visibly lists every device, mount point, and format/keep action before accepting Yes.


### 38. Final review does not show configured LVM volume groups or logical volumes
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** Final installation review / LVM summary
- **Observed behavior:** The Review selections screen reports `LVM Enabled: yes` but shows `Volume Group: none` and `Logical Volumes: none` even after the VG/LVs were created and are in use.
- **Expected behavior:** The final review must enumerate the actual active/selected LVM topology instead of only reporting that LVM is enabled.
- **Required display:** Show each VG name and each LV beneath it, including at least the LV path/name and size. Where possible, also show the backing PV(s) so the user can verify the complete `PV -> VG -> LV` chain before installation.
- **Suggested data source:** Query live LVM metadata with `pvs`, `vgs`, and `lvs` rather than relying only on installer state variables, because VGs/LVs may have been created or activated through multiple paths.
- **Example:** `Volume Group: bfs-vg`; `Logical Volumes: /dev/bfs-vg/home (500G), /dev/bfs-vg/var (500G)`; `Physical Volume: /dev/mapper/cryptraid`.
- **Regression test:** Create the RAID -> LUKS -> LVM layout, open Review selections, and verify the real VG and all LVs are listed instead of `none`.


### 39. Make the Classic Slackware theme more authentically nostalgic and make it the default
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** Dialog theme / visual styling in installer and `bootstrap.sh`
- **Current behavior:** The Classic Slackware theme captures the general cyan/blue/yellow palette, but the screen is too uniformly cyan and the normal text/border contrast feels flatter and more modern than the classic Slackware `setup` appearance. Both scripts currently default to another theme unless a saved setting or environment override selects Slackware.
- **Desired behavior:** Tune only the Classic Slackware theme to more closely resemble the nostalgic ncurses/Dialog Slackware installer look while leaving all other themes available, and make **Classic Slackware the default theme for both the installer and `bootstrap.sh`** on a fresh configuration.
- **Default-selection behavior:** Change the built-in fallback/default theme in both scripts to `slackware`. Existing users who already have a saved theme preference should keep that saved preference; explicit environment overrides such as `BFS_INSTALLER_THEME` / `BFS_BOOTSTRAP_THEME` should continue to take precedence.
- **Visual changes to investigate:** Use a black terminal/screen background with cyan dialog panels; use black/dark normal dialog text; bright yellow dialog titles; strong blue active-selection bars with bright white text; vivid red/blue menu tags or accelerator characters; yellow selected tags where appropriate; stronger gray/white border and scrollbar contrast; and enable the classic Dialog drop-shadow/raised-window effect for this theme.
- **Buttons:** Active buttons should have the high-contrast old Dialog appearance (blue background with bright white/yellow text); inactive buttons should remain clearly distinguishable against the cyan dialog.
- **Scope:** Apply the same Classic Slackware styling consistently to both the BFSOS installer and `bootstrap.sh`. Do not alter the other selectable themes.
- **Regression test:** Cycle through installer and bootstrap menus, yes/no prompts, checklists, password/input boxes, scrolling review dialogs, and storage menus using Classic Slackware. Verify readability, selection visibility, borders/shadows, and a consistent nostalgic Slackware `setup` appearance.


### 40. Add explicit support for separate `/usr` and general non-root mount ordering
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** Filesystem layout / mount ordering / Dracut early-boot dependencies
- **Current concern:** The installer supports additional mount points, but separate `/usr` needs stronger handling than ordinary mounts such as `/opt`, `/srv`, `/var`, or `/home`.
- **Required behavior for `/usr`:** Treat `/usr` as an early-boot-critical filesystem. Ensure the final initramfs can reach every storage layer required to mount it (plain block device, LUKS, MD RAID, LVM, etc.), generate the correct `/etc/fstab` entry, and include `/usr` in the same storage-dependency validation used for root.
- **Dracut module requirement:** When `/usr` is a separate filesystem, automatically add Dracut's `usrmount` module to the generated BFS storage config (for example `add_dracutmodules+=" usrmount "`). If `/usr` depends on LUKS, MD RAID, or LVM, also include the corresponding `crypt`, `mdraid`, and/or `lvm` modules based on the actual `/usr` ancestry.
- **Initramfs validation:** After rebuilding the initramfs, verify that the image contains `usrmount` whenever `/usr` is separate, plus every required supporting storage module. Fail or warn before reboot if the early-boot `/usr` dependency cannot be satisfied.
- **General mount-order rule:** Mount all selected filesystems before rootfs extraction and before chroot/package configuration so files destined for separate mount points such as `/usr`, `/opt`, `/var`, or `/home` are written to the correct filesystem instead of being placed underneath the future mount point on `/`.
- **Normal additional mounts:** `/opt`, `/srv`, `/var`, `/home`, `/tmp`, and other non-early-boot mount points can use the normal additional-filesystem path, but they still must be mounted before extraction/configuration when their content is part of the base system or installed packages.
- **Validation:** Before installation, detect duplicate/nested mount-point conflicts and establish parent-before-child mount order. Before first boot, verify `/usr` is reachable from the initramfs when it is separate.
- **Regression tests:** Test at least (1) separate plain `/usr`; (2) `/usr` on LVM; (3) `/usr` on LUKS/LVM or RAID-backed storage; and (4) separate `/opt` to confirm files are extracted onto the intended filesystem. For every separate-`/usr` case, inspect the final initramfs and confirm `usrmount` and the required storage modules are present before cold boot.


### 41. Add installer accessibility option for larger virtual-console font
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Area:** Accessibility / installer settings / Linux virtual console
- **Motivation:** High-DPI and 4K displays can make the default Linux virtual-console font difficult to read. The installer should provide an easy large-font mode for users with low vision.
- **Installer setting:** Add a Settings option such as `Console font size` with at least `Default`, `16`, and `20` choices. Apply the selected font immediately to the live installer console so menus and text become easier to read during installation.
- **Runtime-only switch:** Add a command-line/environment switch that enables large-console mode when launching the installer from a terminal without permanently changing the selected installed-system console font. Example interfaces could be `--large-console`, `--console-font=16`, `--console-font=20`, or an environment variable such as `BFS_CONSOLE_FONT=20`.
- **Installed-system option:** Allow the user to choose whether the selected large font should also be written into the installed system's vconsole configuration so the same larger font is used at boot/login after installation.
- **Implementation direction:** Use `setfont` with an installed console font that is known to exist. Detect available PSF fonts before presenting sizes, and gracefully fall back to the current font if the requested font is unavailable.
- **Persistence:** Save the installer UI font preference alongside the existing installer settings, while keeping the runtime-only launch switch able to override it for the current run.
- **High-DPI behavior:** Do not assume a fixed screen resolution. The feature should be font-size based so it works on 1080p, 1440p, 4K, and VM consoles.
- **Regression tests:** Test the installer on a normal console and a 4K/high-DPI console; verify switching between Default/16/20 applies immediately; verify the launch-time switch works; verify the installed-system vconsole font is only changed when explicitly requested.

## Previously Identified / Fixed During This Test Cycle
### make-ca CA bundle compatibility

-   [x] Add `/etc/ssl/certs/ca-certificates.crt` compatibility symlink
    to the make-ca port.
-   [x] Correct make-ca description.
-   [x] Confirm make-ca 1.16.1.
-   [x] Remove circular `make-ca -> p11-kit -> make-ca` package
    dependency.
-   [x] `ports -u` works after CA fix.

### LUKS / cryptsetup

-   [x] cryptsetup 2.8.7 port installs successfully.
-   [x] Complete RAID + LUKS + LVM functional boot proof. Fresh r4 installer regression still recommended.
-   [x] Complete encrypted-root boot proof after adding the confirmed GRUB/Dracut arguments from Issue #30.

## New Issues During Testing

*Add each new issue below before continuing so it is not forgotten.*

### Issue

-   [ ] Fix
-   **Area:**
-   **Current behavior:**
-   **Desired behavior:**
-   **Priority:**
-   **Regression test:**

## Final v50 Cleanup Checklist

-   [x] Convert remaining text-mode submenus/prompts to Dialog where
    appropriate.
-   [ ] Verify Back/Cancel works from every storage submenu without
    terminating installer.
-   [ ] Verify RAID member selector only shows appropriate partitions.
-   [ ] Verify already-selected RAID members disappear from subsequent
    selection choices.
-   [ ] Verify RAID arrays are detected correctly even if Linux
    assembles them as `/dev/md127` instead of `/dev/md0`.
-   [x] Verify LUKS detection automatically installs cryptsetup.
-   [x] Verify `/etc/crypttab`.
-   [x] Verify Dracut includes required `crypt`, `mdraid`, and `lvm`
    support.
-   [x] Verify GRUB kernel command line for encrypted root.
-   [x] Verify RAID + LUKS + LVM survives reboot with the confirmed Issue #30 arguments.
-   [ ] Verify Snapper configs and initial snapshots.
-   [ ] Verify EFI GRUB installation and fallback
    `EFI/BOOT/BOOTX64.EFI`.


## v50 Tracker Fix Build

- **Generated:** 2026-08-09
- **Script:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Syntax check:** `bash -n` passed.
- **r2 additions:** Dialog base-archive path input, RAID review generated from live mdadm state, filesystem-selection loop now uses an explicit Done action, and make-ca release 4 removes the ca-certificates file conflict.
- **Critical crypttab change:** active dm-crypt mappings now obtain their backing device from `cryptsetup status` rather than `lsblk PKNAME`, which was blank for the reopened mappings in this test.
- **Test next:** reuse the existing RAID/LUKS/LVM topology, select the filesystems/mount points, and run through installation to verify crypttab, dracut, GRUB, and encrypted-root boot.


## r3 Remaining-Changes Build

- **Generated:** 2026-08-09
- **Script:** `install-bfs-menu-v50-tracker-fixed-r3.sh`
- **Syntax check:** `bash -n` passed.
- **Implemented:** intelligent mount-point defaults; filesystem plan embedded directly in the final Yes/No confirmation; Current Storage Devices moved to Dialog; git + wget default on; final chroot returns directly to the installer menu.
- **Profiles:** added Save, Save As, and Load under Installer Settings. Profiles exclude passwords/passphrases and validate saved block-device paths. Full RAID/LUKS/LVM recreation remains intentionally tracked as partial until those menus are converted from immediate destructive actions to a declarative storage plan.


## r4 Boot-Storage Fix Build

- **Generated:** 2026-08-09
- **Script:** `install-bfs-menu-v50-tracker-fixed-r4.sh`
- **Issue #30:** dynamically generates permanent GRUB/Dracut storage arguments and stores them in `/etc/default/grub`; RAID adds the confirmed `rd.auto rd.md=1`, LUKS UUIDs come from `/etc/crypttab`, and required LV arguments are derived from `/etc/fstab` plus LVM metadata.
- **Future kernels / recovery:** storage arguments are written to `GRUB_CMDLINE_LINUX`, not only the generated `grub.cfg`, so later `grub-mkconfig` runs and recovery entries retain the required storage topology.
- **Validation:** installer verifies generated normal/recovery GRUB entries contain required RAID/LUKS/LVM arguments.
- **Issue #21:** fixed the live `/proc/mdstat` parser that could report `RAID enabled: YES` while listing arrays as `none`.
- **Additional UI cleanup:** assembling existing RAID arrays and viewing RAID details now stay in Dialog instead of dropping to raw terminal output with `Press Enter to continue...`.
- **Still partial by design:** Issue #28 profile support does not recreate RAID/LUKS/LVM destructively from a profile until storage setup is refactored into a declarative plan.


## r21 Storage / UI / Accessibility Polish Build

- **Generated:** 2026-08-10
- **Installer:** `install-bfs-menu-v50-tracker-fixed-r21.sh`
- **Bootstrap:** `bootstrap-r21-classic-slackware-default.sh`
- **Syntax checks:** `bash -n` passed for both scripts.
- **Issues #34/#35:** deduplicate MD-backed LUKS and LVM device paths.
- **Issue #36:** VG creation now selects from real unassigned PVs; LV creation selects from real VGs.
- **Issue #37:** filesystem confirmation now embeds the full device/mount/FORMAT-or-KEEP plan before Yes/No.
- **Issue #38:** final review queries live `pvs`, `vgs`, and `lvs` metadata.
- **Issue #39:** Classic Slackware is the fresh-install default in installer and bootstrap, with black screen, cyan panels, stronger borders, blue selections, and Dialog shadow.
- **Issue #40:** non-root filesystems are mounted parent-before-child before extraction; separate `/usr` causes `usrmount` to be forced into the generated Dracut config and verified in the completed initramfs.
- **Issue #41:** installer Settings now provide Default/16/20 console-font choices, optional installed-system persistence, plus runtime-only `--large-console`, `--console-font SIZE`, and `BFS_CONSOLE_FONT` overrides.
- **Issue #28 remains intentionally partial:** profile replay does not yet recreate destructive RAID/LUKS/LVM topology; that still requires a declarative storage planner and must never store passphrases.

## r22 Follow-up Issues Found During VM Regression Testing

### 42. Add a destructive storage-reset helper for repeated installs and recovery
- [x] Fix / enhancement revalidated
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r27.sh`
- **r27 regression fix:** Expanded MD detection to report active arrays and inactive member metadata with `mdadm --examine`; the destructive checklist now retains RAID-member devices after array deactivation and labels them explicitly before zeroing superblocks/wiping selected metadata.
- **Area:** Installer Settings / storage maintenance / test workflow
- **Goal:** Add an explicit Settings action that detects old LVM, LUKS, and MD RAID state and can tear it down cleanly before a fresh installation.
- **UI:** Add a clearly destructive option such as `Reset existing storage metadata...`. Never run it automatically.
- **Detection:** Before confirmation, enumerate active and inactive MD arrays, LUKS mappings/containers, LVM PVs/VGs/LVs, swap devices, mounted target filesystems, and stale filesystem/signature metadata.
- **Preview:** Show exactly what will be affected before doing anything: mounts to unmount, swap to disable, VGs/LVs to deactivate/remove, LUKS mappings to close, MD arrays to stop, member devices whose MD superblocks will be removed, and devices on which `wipefs` will run.
- **Safety:** Require an explicit destructive confirmation. Exclude the live installer media, BFSOS source/build disk, and any device not selected/confirmed by the user. Never guess that an unrelated disk is safe to erase.
- **Order of operations:** Unmount target filesystems -> swapoff -> deactivate/remove LVs/VGs/PVs as requested -> close LUKS mappings -> stop MD arrays -> zero MD superblocks when requested -> run `wipefs` on confirmed backing devices/arrays -> `udevadm settle`.
- **Modes:** Ideally provide both `Deactivate only` and `Destroy metadata / fresh start` so normal recovery work does not require wiping anything.
- **Why:** Repeated VM installer testing currently requires many manual `vgchange`, `cryptsetup close`, `mdadm --stop/--zero-superblock`, and `wipefs` commands.
- **Regression test:** Build RAID -> LUKS -> LVM storage, leave it active, invoke the reset helper, confirm the preview is correct, perform a full reset, and verify `pvs`, `vgs`, `lvs`, `/dev/mapper`, `/proc/mdstat`, and `lsblk -f` show the expected clean state while the BFSOS build disk remains untouched.

### 43. Partition/filesystem Cancel must return to Storage setup, not abort installation
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Storage assignment / Dialog navigation / error handling
- **Observed behavior:** Cancelling the partition/filesystem selection path can escape as a non-zero return and trigger `ERROR: Installation cancelled`, invoking fatal cleanup.
- **Desired behavior:** `Back` or Dialog Cancel returns to Storage setup. Only an explicit `Cancel installation`/Quit action may terminate the installer.
- **State preservation:** RAID/LUKS/LVM objects already created should remain available when returning to Storage setup unless the user explicitly removes them.
- **Regression test:** Create RAID/LUKS/LVM state, enter filesystem assignment, press Cancel, and verify the installer returns to Storage setup with storage state intact and no fatal cleanup.

### 44. Improve failure logging for navigation and generated/chroot failures
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Logging / ERR trap
- **Current behavior:** Some failures produce only `ERROR: Installation cancelled` or `Installation stopped near line 1`, hiding the command/function that actually returned non-zero.
- **Desired behavior:** Log the failing command, source file, function stack, real line number, and exit status. Normal Dialog Back/Cancel return codes must be handled explicitly and never reach the fatal ERR path.
- **Log preservation:** Keep the live-environment installer log even when target mounts are cleaned up, and copy it into the installed system whenever the target remains available.

### 45. Rework filesystem-plan confirmation into a readable scrollable view
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Filesystem confirmation UI
- **Observed behavior:** With many devices/LVs the confirmation table wraps across lines and becomes difficult to read.
- **Desired behavior:** Use a wide, vertically scrollable fixed-column view showing at least Number, Device, Action (`FORMAT as ...` / `KEEP`), and Mount point. Keep Continue/Back controls clear and prevent rows from wrapping into each other.
- **Priority:** Safety-critical readability before destructive formatting.

### 46. Improve mount-point defaults from logical-volume/device names
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Filesystem assignment / mount-point suggestion
- **Desired behavior:** Infer common mount points from the final LV/device component: `root` -> `/`, `usr` -> `/usr`, `opt` -> `/opt`, `home` -> `/home`, `var` -> `/var`, `tmp` -> `/tmp`, `srv` -> `/srv`, and `swap` -> swap. Keep the suggestion editable.

### 47. Loaded profiles must refresh main-menu configured/pending indicators
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Installer profiles / main menu state
- **Observed behavior:** Profile values appear to load, but sections still show `[PENDING]`.
- **Desired behavior:** After loading a profile, recalculate each section status from restored values. Storage may remain pending when destructive topology still requires manual recreation.

### 48. Match the Classic Slackware theme to Slackware's actual current dialogrc
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh` and `bootstrap-r26.sh`
- **Area:** Installer and bootstrap theme
- **Reference verified:** Slackware64-current `dialog-1.3_20260721-x86_64-1.txz`, `etc/dialogrc.new` (`$Id: slackware.rc,v 1.13 2025/12/22 ...`), which Slackware's `build_installer.sh` copies into the installer as `/etc/dialogrc`.
- **Correction to earlier assumption:** Slackware intentionally uses a BLUE full-screen background. Do not replace it with black merely to look more nostalgic.
- **Goal:** Make BFSOS `Classic Slackware` match the real Slackware dialog palette and behavior as closely as practical, while retaining BFSOS-specific text/layout.
- **Behavior values:** `aspect = 0`, `separate_widget = ""`, `tab_len = 0`, `visit_items = OFF`, `use_scrollbar = OFF`, `use_shadow = ON`, `use_colors = ON`.
- **Core palette:** `screen_color = (WHITE,BLUE,OFF)`, `shadow_color = (WHITE,BLACK,OFF)`, `dialog_color = (BLACK,CYAN,OFF)`, `title_color = (YELLOW,CYAN,ON)`, `border_color = (CYAN,CYAN,ON)`.
- **Buttons:** active `(WHITE,BLUE,ON)`; inactive uses `dialog_color`; inactive accelerator/key `(RED,CYAN,OFF)`; inactive label `(BLACK,CYAN,ON)`.
- **Input/search:** input `(BLUE,WHITE,OFF)` with normal border; search `(YELLOW,WHITE,ON)`; search title `(WHITE,WHITE,ON)`; search border `(RED,WHITE,OFF)`.
- **Menus/items:** menubox and item use `dialog_color`; selected item uses `screen_color`.
- **Tags:** normal tag uses `title_color`; selected tag uses `screen_color`; tag key uses inactive button-key color; selected tag key `(RED,BLUE,ON)`.
- **Checklist/arrows:** check uses `dialog_color`; selected check `(WHITE,CYAN,ON)`; up/down arrows `(GREEN,CYAN,ON)`.
- **Other verified values:** position indicator uses inactive button-key color; item-help uses shadow color; active form text uses inputbox color; form text `(CYAN,BLUE,ON)`; readonly form item `(CYAN,WHITE,ON)`; gauge `(BLUE,WHITE,ON)`; border2/inputbox_border2/searchbox_border2/menubox_border2 use `dialog_color`.
- **Scope:** Apply the same authentic Classic Slackware theme implementation to both the BFSOS installer and `bootstrap.sh`.
- **Regression test:** Compare installer/bootstrap menus, input boxes, checklists, selected rows, buttons, titles, arrows, shadows, and gauges against Slackware's current `dialogrc` behavior.

### 49. Simplify large-console-font persistence
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Accessibility / console font settings
- **Desired behavior:** Selecting `Large 16` or `Large 20` should apply immediately to the installer and automatically configure the installed BFSOS virtual console to use the same font. Remove the separate `Use selected console font after install` question. `Default` retains the normal installed-system default.

### 50. Optional Software and sudo should not start as pending
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Main-menu status/defaults
- **Optional Software:** Never show `[PENDING]`; no optional packages is valid. Use `[OPTIONAL]` initially and `[CONFIGURED]` after choices are made.
- **Sudo:** If untouched, default to normal sudo authentication requiring the user's password and show `[DEFAULT]` (or equivalent), not `[PENDING]`.
- **General rule:** Reserve `[PENDING]` for sections that genuinely require user attention before installation can proceed.
- **Optional package addition:** Add the existing BFSOS `wpa_supplicant` port (`ports/core/wpa_supplicant`) to Optional Software.

### 51. Review/install forward action should be Continue
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** Review/install navigation
- **Desired behavior:** The forward action from Review into installation must be labeled `Continue`. `Back` must only return to the previous configuration screen. Make cancellation an explicit separate action.

### 52. Detect stale signatures on newly created MD arrays
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** MD RAID -> LUKS workflow
- **Observed behavior:** A newly created `/dev/mdX` can expose a stale `crypto_LUKS` or filesystem signature from previous contents, causing the LUKS `Create new container` selector to hide the otherwise valid RAID array.
- **Desired behavior:** Immediately after MD creation, inspect the array with `wipefs`. If stale signatures are present, show them and offer an explicit `Wipe signatures`, `Keep`, or `Cancel` choice before continuing.
- **Safety:** Never silently wipe signatures.

### 53. Pre-reboot validation: complex encrypted RAID/LVM/Btrfs install is boot-test ready
- [x] Validation passed
- **Area:** Final installation validation / Dracut / GRUB / storage
- **Validated topology:** UEFI + separate ext2 `/boot`; LUKS `cryptroot` -> LVM `bfs-root` -> separate Btrfs `/`, `/usr`, and `/opt`; MD RAID -> LUKS `cryptraid` -> LVM `bfs-vg` -> separate Btrfs `/home` and `/var`; Btrfs snapshot subvolumes; disk swap.
- **Dracut modules verified in generated initramfs:** `btrfs`, `crypt`, `crypt-lib`, `dm`, `lvm`, `mdraid`, `rootfs-block`, and `usrmount`.
- **Separate `/usr` support verified:** initramfs contains Dracut `pre-pivot/50-mount-usr.sh`; generated `/etc/dracut.conf.d/20-bfs-storage.conf` records `Separate /usr: yes` and forces `usrmount crypt lvm mdraid`.
- **GRUB verified:** generated kernel command line contains `root=/dev/mapper/bfs--root-root`, `rootflags=subvol=@`, `rd.auto`, `rd.md=1`, both LUKS UUID arguments, and `rd.lvm.lv=bfs-root/root`; correct BFSOS kernel and initramfs paths are present.
- **ZRAM verified:** kernel config has `CONFIG_ZRAM=m` and the installed `zram.ko` exists under `/lib/modules/7.1.5-BFS-Linux/kernel/drivers/block/zram/`.
- **Decision:** Do not make further Dracut/GRUB changes before the reboot test. The current configuration should be tested as generated by the installer.
- **Next test:** Cleanly leave chroot/unmount, reboot from the installed disk, confirm both LUKS prompts/unlocks, MD assembly, both VGs, separate `/usr`, `/opt`, `/var`, `/home`, and successful systemd userspace boot.

### 54. Update installed release branding URLs from BFS-Linux to BFSOS
- [x] Fix
- **Completed:** Installed test system produced BFSOS Codeberg URLs correctly, and the installer keeps the extracted os-release safeguard. The source `aaa_filesystem` Pkgfile had already been corrected in the project tree before this pass.
- **Area:** `aaa_filesystem` / `/etc/os-release` branding
- **Observed behavior:** Installed `/etc/os-release` still uses `https://codeberg.org/bmadonnaster/BFS-Linux` for `HOME_URL`, `SUPPORT_URL`, and `BUG_REPORT_URL` even though the repository has been renamed to BFSOS.
- **Desired behavior:** Change all three generated URLs to the current BFSOS repository and BFSOS issues page.
- **Scope:** Search release/branding files and installer-generated metadata for any remaining stale `BFS-Linux` repository references so new installs do not recreate them.
- **Priority:** Cosmetic/non-boot-blocking; fix after the current reboot test rather than modifying this installed test system before first boot.
- **r35 safeguard:** The installer now rewrites stale BFS-Linux Codeberg URLs in the extracted `/etc/os-release`/`/usr/lib/os-release` to BFSOS. The source `ports/core/aaa_filesystem/Pkgfile` still needs to be updated directly when that port file is supplied; it was not among the uploaded files for this pass.
### 55. Rename the blue theme to Classic Debian and reproduce Debian's real installer palette from source
- [x] Enhancement
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh` and `bootstrap-r26.sh`
- **Area:** Installer and bootstrap themes / Debian-inspired theme
- **Rename:** Change the existing blue-theme display name to **Classic Debian** everywhere it appears in installer menus, bootstrap menus, saved theme/profile labels, help text, and documentation. Preserve the existing internal key where practical for compatibility, or add a migration/alias so saved configurations using the old theme name still load correctly.
- **Research source of truth:** Do not rely on screenshots or memory. Base the Classic Debian palette on Debian's actual installer frontend source.
- **Primary Debian source:** Debian's installer uses `cdebconf` with a `newt` frontend. The authoritative source tree is the Debian Installer Team `cdebconf` repository and the versioned Debian Sources copies.
- **Historical evidence:** Debian's `cdebconf` changelog records explicit newt color changes, including support for a dark background via `FRONTEND_BACKGROUND=dark` and later readability changes for select, multiselect, and button colors.
- **Related palette source:** `newt` itself defines color-set roles such as root, border, window, shadow, title, button, active button, checkbox, entry, listbox, textbox, helpline, and progress-scale colors. Debian's frontend may override or remap these, so inspect `cdebconf`'s newt frontend first and use `newt` defaults only where Debian leaves them unchanged.
- **Research targets:** Locate and compare the current and historically representative Debian installer newt frontend code/config for root/screen, window/dialog, borders/shadows, titles, active/inactive buttons, entries, normal/selected menu rows, checkboxes/radiolists, help/status text, progress bars, and any `FRONTEND_BACKGROUND` logic.
- **Implementation goal:** Translate the verified Debian installer palette into the BFSOS Dialog-based theme as faithfully as practical while keeping BFSOS-specific layouts and controls.
- **Scope:** Apply the renamed **Classic Debian** theme consistently to both the BFSOS installer and `bootstrap.sh`; do not alter Classic Slackware or other themes.
- **Compatibility:** Existing saved profiles/configs referring to the old blue-theme identifier/name must continue to work and should map automatically to Classic Debian.
- **Regression test:** Compare BFSOS Classic Debian menus, prompts, input boxes, checklists, selected rows, buttons, titles, shadows, help text, and progress displays against the Debian installer source-defined appearance; verify theme selection and saved-profile migration work in both installer and bootstrap.
- **Research starting points:** Debian Installer Team `cdebconf` source on Salsa; Debian Sources package history for `cdebconf`; `cdebconf` newt frontend source and changelog entries for `FRONTEND_BACKGROUND=dark`; Debian `newt` source for base color-set definitions where needed.

- **Source research completed for r26:** Debian `cdebconf` 0.280 `src/modules/frontend/newt/newt.c` uses `newtDefaultColorPalette` unless `FRONTEND_BACKGROUND=dark`; its alternate dark palette remains explicitly defined in the frontend. Debian's `cdebconf` changelog documents the black-background mode and later select/multiselect/button readability changes.
- **Classic palette basis used in BFSOS:** the normal newt palette roles map to white-on-blue root/screen, black-on-light-gray window/border, red-on-light-gray title/active button, yellow-on-blue entry/selected-list accents, and a white-on-black shadow. Dialog's `WHITE` is used as the closest standard-color approximation to newt `lightgray`.
- **Compatibility:** the internal theme key remains `classic`, so existing settings/profiles continue loading while the visible name changes from `Classic Blue` to `Classic Debian`.
### 56. Add explicit early-boot GRUB/LVM arguments for separate `/usr`
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Area:** GRUB generation / Dracut early-LVM activation / separate `/usr`
- **Observed boot failure:** With `/usr` on `bfs-root/usr`, Dracut loaded `usrmount` and all required storage modules, unlocked `cryptroot`, activated `bfs-root/root`, and mounted root, but `/usr` failed because `bfs-root/usr` was not activated early. The generated kernel command line contained `rd.lvm.lv=bfs-root/root` but omitted `rd.lvm.lv=bfs-root/usr`.
- **Manual proof:** Adding `rd.lvm.lv=bfs-root/usr` to the GRUB kernel command line allowed the system to boot successfully.
- **Required fix:** Whenever `/usr` is on an LVM LV, add an explicit `rd.lvm.lv=<VG>/<LV>` argument for that `/usr` LV in addition to the root LV argument.
- **General rule:** Generate explicit `rd.lvm.lv=` arguments for every filesystem that is genuinely required in initramfs/early userspace, not merely every LV in the system.
- **Do not over-broaden by default:** Normal late mounts such as `/opt`, `/var`, `/home`, `/srv`, and similar filesystems do not need explicit early-LVM kernel arguments solely because they are LVs. Let normal systemd/fstab activation handle them after switch-root unless their ancestry is needed to reach `/usr` or another early-boot-critical path.
- **RAID/LUKS handling:** Continue generating explicit early-boot RAID/LUKS arguments from the ancestry of root and separate `/usr`. It is safe to include required parent MD/LUKS devices, but avoid blindly adding every unrelated RAID/LUKS device in the machine because that can trigger unnecessary unlock prompts, array assembly, delays, or failures for storage that is not required to boot.
- **Topology-driven implementation:** Walk the block-device ancestry for `/` and `/usr`; collect only the required LVM LVs, LUKS UUIDs, and MD arrays; deduplicate arguments; persist them in `GRUB_CMDLINE_LINUX`; regenerate `grub.cfg`; and verify the generated normal and recovery entries contain all required early-storage arguments.
- **Regression tests:** 
  1. Root on LVM with no separate `/usr`.
  2. Root + separate `/usr` on different LVs in the same VG.
  3. `/usr` on LUKS -> LVM.
  4. `/usr` on MD RAID -> LUKS -> LVM.
  5. Extra unrelated LVs/RAID/LUKS present for `/home`, `/var`, or data; confirm they do not cause unnecessary early boot prompts or kernel arguments.

- **Boot regression confirmed/fixed:** the first cold boot failed because only `bfs-root/root` was activated. Manually adding `rd.lvm.lv=bfs-root/usr` in GRUB allowed BFSOS to boot successfully. r26 now derives explicit `rd.lvm.lv=` arguments from `/` and `/usr` only, rather than all LVs.
- **Topology scope:** required LUKS UUIDs and MD discovery flags are likewise derived from the ancestry of `/` and `/usr`, avoiding unnecessary unlock prompts or assembly of unrelated data/home storage.

## r26 Tracker Implementation Pass

- **Generated:** 2026-08-10
- **Installer:** `install-bfs-menu-v50-tracker-fixed-r26.sh`
- **Bootstrap:** `bootstrap-r26.sh`
- **Syntax checks:** `bash -n` passed for both scripts.
- **Issues completed in this pass:** #42, #43, #44, #45, #46, #47, #48, #49, #50, #51, #52, #55, #56.
- **Issue #54 remains open:** `/etc/os-release` URL correction belongs in the `aaa_filesystem` port/Pkgfile rather than either of the two scripts supplied for this pass.
- **Storage maintenance:** Settings now includes a previewed `Deactivate only` mode and an explicit checklist-driven destructive metadata reset. Protected live-root/project storage is excluded.
- **Filesystem navigation/UI:** Back from filesystem assignment returns to Storage setup; the final plan is shown in a wide scrollable textbox followed by Continue/Back confirmation; LV names such as `usr`, `opt`, `var`, `home`, `tmp`, and `srv` get sensible mount-point suggestions.
- **Profiles/status:** loaded profiles recalculate configured/pending state; Optional Software defaults to `OPTIONAL`; sudo defaults to password-authenticated `DEFAULT`.
- **Optional software:** `wpa_supplicant` is available as an optional package.
- **Console accessibility:** selecting Large 16/20 automatically persists that choice to the installed system; selecting Default disables persistence.
- **Themes:** Classic Slackware now uses the exact Slackware `dialogrc` values gathered during testing; Classic Blue is renamed Classic Debian and translated from Debian cdebconf/newt source while preserving the `classic` internal key.
- **RAID stale signatures:** newly-created arrays are checked with `wipefs -n` and the user is explicitly offered a safe wipe/keep choice.
- **Failure diagnostics:** ERR trap now records exit status, source, line, function, command, and caller instead of `line 1`.
- **Install navigation:** final installation confirmation is Continue/Back; Back returns to configuration instead of triggering fatal cleanup.
- **Early boot storage:** GRUB arguments are derived from boot-critical `/` and `/usr` ancestry. Separate `/usr` on LVM now receives its own `rd.lvm.lv=` parameter.

## r27 Follow-up Issues Found During Installed-System Testing

### 57. Fix GRUB/Dracut topology logic for complex storage
- [x] Fix — reopened after r27 regression test
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** GRUB generation / Dracut / complex storage
- **Observed behavior:** The completed install did not automatically emit the complete/correct boot-storage arguments required by the tested topology. Manual correction was required before reboot.
- **Required behavior:** Derive boot-critical storage ancestry and emit the required `rd.luks.uuid=`, `rd.md.uuid=`, and `rd.lvm.lv=` arguments. Finalize `/etc/crypttab` and mdadm configuration before rebuilding the initramfs, then regenerate `grub.cfg` and validate the generated boot entries/initramfs.
- **Regression scope:** LUKS -> LVM and MD RAID -> LUKS -> LVM, including separate `/usr`, `/opt`, `/home`, `/var`, and complex Btrfs layouts.
- **r27 regression #1 — truncated MD UUID:** The MD UUID parser emitted only the first colon-delimited field (`rd.md.uuid=4a9b5206`) instead of the complete mdadm UUID (`rd.md.uuid=4a9b5206:8ebe46e5:6d41cbba:3468e1e1`). Preserve the complete value exactly as reported by `mdadm --detail` / `mdadm --detail --scan`; do not parse it with a generic colon field split.
- **r27 regression #2 — stale verifier:** The generator switched to explicit `rd.md.uuid=...`, but the GRUB verifier still failed the install with `boot-critical RAID storage requires rd.auto`. Generator and verifier must use the same storage model. A valid explicit `rd.md.uuid=` must satisfy RAID verification; `rd.auto` must not be required when explicit MD UUIDs are emitted.
- **r27 regression #3 — missing explicit LUKS cmdline:** The tested RAID -> LUKS -> LVM plus separate LUKS root topology generated no `rd.luks.uuid=` values even though `/etc/crypttab` contained both mappings. Generate explicit LUKS UUID arguments for every boot-required encrypted layer in the selected storage ancestry.
- **Known-good manual result for this test topology:**
  - `rd.luks.uuid=77d5c3fb-083b-4ea3-9aa8-11f4e85d334e`
  - `rd.luks.uuid=a82d9766-a424-4530-b4a7-9b8de91d0b2c`
  - `rd.md.uuid=4a9b5206:8ebe46e5:6d41cbba:3468e1e1`
  - `rd.lvm.lv=bfs-root/root`
  - `rd.lvm.lv=bfs-root/usr`
  - `rd.lvm.lv=bfs-raid/home`
  - `rd.lvm.lv=bfs-raid/var`
- **Initramfs validation from failed r27 test:** The initramfs already contained `crypttab`, `mdadm.conf`, `cryptsetup`, `mdraid`, and LVM support, so this failure was isolated to GRUB/storage-command-line generation and verification rather than missing initramfs storage tooling.
- **Post-install menu clarification:** The missing Chroot/Finish menu was not a separate post-install-menu bug in this test. The installer aborted during final GRUB verification, so it correctly never reached the success/post-install menu.
- **Regression test:** Build the same RAID0 -> LUKS -> LVM layout plus separate LUKS root, regenerate initramfs/GRUB without manual edits, verify full MD UUID preservation, both LUKS UUIDs, all required LVs in normal and recovery entries, and confirm the installer reaches the final Chroot/Finish menu after validation succeeds.


### 58. Correct Review vs Option 10 final-summary navigation labels
- [x] Fix
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Review/install navigation
- **Observed behavior:** r27 overcorrected the navigation labels so both the configuration Review screen and the Option 10 final installation summary show `Continue`.
- **Desired behavior:** The Review/configuration screen must provide `Back` so the user can return and change selections. Option 10's final installation summary must show `Continue` at the bottom to proceed into installation; it must not show `Back`.
- **Regression test:** Confirm the Review/configuration screen says `Back`, then enter Option 10 and confirm the final summary says `Continue`. Verify Back actually returns to configuration and Continue advances toward installation.


### 59. Consolidate BFSOS logs under `/var/log/bfs`
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r27.sh` and `bootstrap-r27.sh`
- **Area:** Bootstrap/build logging / installer logging
- **Observed behavior:** Build logs are currently installed under `/var/logs/bfs-build/`, while installer logs correctly use `/var/log/bfs/installer/`.
- **Desired layout:** `/var/log/bfs/bfs-build/` for package/bootstrap build logs and `/var/log/bfs/installer/` for installer logs.
- **Cleanup:** Remove new uses of the legacy `/var/logs` path and update log-copy/install logic so all BFSOS-specific logs live below `/var/log/bfs/`.
- **r27 implementation:** Bootstrap copies base-package build logs to `/var/log/bfs/bfs-build`; installer logs remain `/var/log/bfs/installer`.

### 60. Add `wireless_tools` to Optional Software
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r27.sh`
- **Area:** Optional Software
- **Package:** `wireless_tools` 30.pre9
- **Status:** Port built and runtime tools verified during installed-system testing.
- **Desired behavior:** Offer `wireless_tools` in the installer's Optional Software selection alongside `wpa_supplicant`.
- **r27 implementation:** Added `BFS_INSTALL_WIRELESS_TOOLS`, profile save/load support, Dialog/text optional-package selection, and chroot package-list installation.

## r27 Test Notes

- Full installer run completed without installer errors before first reboot.
- `wpa_supplicant` 2.11 was verified installed and runnable against OpenSSL 4 (`libssl.so.4` / `libcrypto.so.4`).
- `wireless_tools` was successfully built after correcting the BFSOS port to invoke `build_opt` from `pkg_build` and package the statically linked utilities without expecting a nonexistent `libiw.so.30` from the default upstream build.

### 61. Clear terminal screen on installer/bootstrap exit
- [x] Fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r27.sh` and `bootstrap-r27.sh`
- **Area:** Installer/bootstrap terminal cleanup / UI
- **Observed behavior:** Exiting the installer or `bootstrap.sh` can leave the full-screen `dialog` background and menu colors painted across the terminal instead of restoring a clean shell view.
- **Desired behavior:** On every normal exit, Cancel/Quit path, and handled error exit, restore the terminal state and clear/redraw the screen before returning to the shell.
- **Implementation note:** Centralize terminal cleanup in the existing exit/cleanup handler so both the installer and bootstrap consistently run the appropriate `clear`/terminal-reset sequence after `dialog` is closed. Avoid scattering cleanup calls through individual menus.
- **Regression test:** Exit normally, use Back/Cancel/Quit paths, and trigger a handled failure under each theme; confirm the shell returns with no stale installer/bootstrap background, colors, cursor state, or screen contents.
- **r27 implementation:** Both scripts centralize terminal reset in their EXIT cleanup handlers, reset SGR attributes, show the cursor, and clear/redraw `/dev/tty` after restoring `DIALOGRC`.


## r27 Implementation Pass

- **Generated:** 2026-08-11
- **Installer:** `install-bfs-menu-v50-tracker-fixed-r27.sh`
- **Bootstrap:** `bootstrap-r27.sh`
- **Issues addressed:** #42 regression, #57, #58, #59, #60, #61.
- **Still open:** #54 (`aaa_filesystem` branding URLs) because the port Pkgfile was not part of this script pair.
- **Required regression test:** run a fresh complex-storage VM install and verify generated GRUB/initramfs without manual edits, storage-reset RAID detection/destruction, Review button label, optional `wireless_tools`, installed log paths, and clean terminal exit.

### 62. Change OpenSSH prompt to enable-on-boot wording
- [x] Fix
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Optional software / service configuration
- **Observed behavior:** The installer currently presents OpenSSH like an optional package even though `openssh` is already installed by the BFSOS bootstrap/base system.
- **Desired behavior:** Ask `Do you want to enable OpenSSH on boot?` and treat the answer as service configuration for `sshd.service`, not as a package-install decision.
- **Regression test:** Confirm OpenSSH is already present from the base system, the installer asks only whether to enable it at boot, and the selected answer produces the expected `sshd.service` enablement state.

### 63. Run mandatory `prt-get sysup` after `ports -u`
- [x] Enhancement / fix
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Ports synchronization / installed-system upgrade
- **Reason:** A user may install from an older base rootfs archive. Synchronizing the ports tree alone does not upgrade packages already present in that base system.
- **Desired behavior:** After a successful `ports -u`, run `prt-get sysup` inside the installed system as a mandatory system upgrade before the final initramfs/Dracut and GRUB generation.
- **Failure behavior:** A failed `prt-get sysup` must stop the installation rather than silently continuing with a partially upgraded system.
- **Logging:** Capture the system-upgrade output in the installer log so package changes and failures can be diagnosed later.
- **Regression test:** Test with an intentionally older base archive; confirm ports synchronize, installed packages upgrade, failures propagate, and final Dracut/GRUB generation occurs only after the upgrade succeeds.

## r28 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No installer/bootstrap code changed in this revision.
- **Reopened:** #58 to distinguish the Review/configuration `Back` action from Option 10 final-summary `Continue`.
- **Added:** #62 OpenSSH enable-on-boot wording/service logic.
- **Added:** #63 mandatory `prt-get sysup` after `ports -u`, before final Dracut/GRUB generation.

### 64. Offer optional package-cache cleanup after successful installation
- [x] Enhancement
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Post-install package/cache cleanup
- **Timing:** Ask only after all package installation and the mandatory `prt-get sysup` have completed successfully, immediately before returning to the installer menu.
- **Prompt:** Ask whether the user wants to clear the built/downloaded binary package cache under `/var/cache/pkg/packages/`.
- **Default:** No. Keeping the cached binary packages can be useful for reinstalling packages or troubleshooting without rebuilding them.
- **Yes behavior:** Remove the contents of `/var/cache/pkg/packages/` while leaving the directory itself in place.
- **Scope:** Do not clear `/var/cache/pkg/sources/`; source-cache cleanup is outside this option.
- **Safety:** Do not offer or perform this cleanup during a failed or partially completed package upgrade, so cached packages remain available for diagnosis/recovery.
- **Regression test:** Complete an install/update with cached packages present, choose No and verify they remain; repeat choosing Yes and verify `/var/cache/pkg/packages/` is empty while `/var/cache/pkg/sources/` is untouched.

### 65. Tie the bootstrap and installer workflows together
- [x] Enhancement
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Bootstrap menu / installer integration
- **Goal:** Make the normal BFSOS workflow flow directly from building a usable base rootfs into launching the installer, instead of treating bootstrap and installation as unrelated entry points.
- **Installer location:** Move the primary installer script into the repository `scripts/` directory. The bootstrap menu should resolve it relative to `SCRIPT_DIR` rather than relying on the caller's current working directory.
- **Bootstrap menu:** Add an explicit `Launch BFSOS installer` entry that runs the repository installer from `scripts/`.
- **Installer discovery:** Do not hard-code a single versioned installer filename in `bootstrap.sh`. Discover matching installer scripts under `scripts/` with a stable pattern (for example `install-bfs-menu-v*.sh`), exclude obvious backups/test artifacts where practical, and select the newest usable version automatically.
- **Version selection rule:** Prefer the highest/newest installer revision deterministically. If filenames contain a date/time or revision component, use that ordering rather than whichever file happens to be returned first by the filesystem.
- **Visibility:** Show the exact installer path/version bootstrap is about to launch so the user can see which revision was selected.
- **Normal workflow:** The common path should make bootstrap stages 1, 2, and 4 plus rootfs archive creation prominent/required for producing an installable BFSOS base.
- **Stage 3:** Keep the full final-toolchain/base rebuild available, but clearly label it **optional**. It is useful for users who deliberately want to rebuild the system a second time, but it must not be presented as a prerequisite for installation.
- **Rootfs archive:** Keep creation/compression of the base rootfs archive as a mandatory part of the normal build-to-install workflow because the installer consumes that archive.
- **Installer handoff:** Before launching the installer, verify that a usable base rootfs archive exists. If not, explain which required bootstrap/archive step is incomplete rather than launching into a guaranteed failure.
- **Return behavior:** When the installer exits normally or is cancelled, return cleanly to the bootstrap menu with the terminal restored.
- **Direct execution:** Moving the installer under `scripts/` must not prevent advanced users from invoking it directly.
- **Path migration:** Update documentation, helper scripts, tracker references, and any hard-coded repository-root installer paths to the new `scripts/` location.
- **Regression test:** From a clean repository, complete the normal bootstrap path without stage 3, create the rootfs archive, launch the installer from the bootstrap menu, cancel/return, relaunch it, and verify paths, permissions, terminal cleanup, archive detection, and direct installer execution all work.

### 66. Clarify mandatory vs optional bootstrap stages in the menu
- [x] UI / workflow enhancement
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Bootstrap menu
- **Goal:** Make it immediately obvious which stages are needed to produce an installable BFSOS base and which are optional validation/rebuild operations.
- **Required normal-build stages:** Present bootstrap options 1, 2, and 4 as part of the normal required workflow, together with mandatory base-rootfs archive creation/compression.
- **Optional rebuild stage:** Mark option 3 as optional and describe it as a second/final rebuild for users who want the additional rebuild pass.
- **Status tracking:** Completion/pending indicators must not treat skipped option 3 as an incomplete/error state when the user follows the normal installable-base workflow.
- **Installer readiness:** The new installer-launch entry should base readiness on the genuinely required stages and availability of the rootfs archive, not on completion of optional stage 3.
- **Existing archive readiness:** On bootstrap startup, inspect the default base-archive directory. If a valid base rootfs archive already exists, treat the installable-base requirement as satisfied even when the current checkout has no fresh stage markers from this session.
- **Menu status:** Reflect that state clearly in the bootstrap menu (for example `READY`/`ARCHIVE AVAILABLE`) so the user can launch the installer immediately without rebuilding mandatory stages unnecessarily.
- **Safety:** Archive presence should satisfy installer readiness only after validating that the file is readable and matches a supported BFSOS base-rootfs archive format.
- **Regression test:** Verify a user can complete the required workflow, intentionally skip stage 3, create the archive, and launch/install BFSOS without warnings claiming the build is incomplete.


## r29 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No bootstrap or installer code changed in this revision.
- **Added:** #65 bootstrap-to-installer integration and moving the primary installer into `scripts/`.
- **Added:** #66 distinguish the required bootstrap path from optional stage 3 and ensure installer readiness does not depend on stage 3.
- **Planned workflow:** build required base stages -> create/compress rootfs archive -> launch installer directly from the bootstrap menu.

- **Status semantics:** Use the three status words consistently: `PENDING` means a required prerequisite has not been satisfied; `AVAILABLE` means an action can be run now but is not itself a completion requirement; `COMPLETE` means the corresponding build/verification/archive requirement has been satisfied.
- **Required stages 1, 2, and 4:** Show `PENDING` until their completion checks pass, then `COMPLETE`.
- **Stage 3 optional rebuild:** Do not show `PENDING` merely because it was skipped. Show `AVAILABLE` while it can be run and `COMPLETE` after it has actually completed.
- **Rootfs archive creation:** Show `PENDING` until a valid base archive exists, then `COMPLETE`.
- **Restore actions:** `Restore newest base rootfs archive` and `Restore newest temporary toolchain archive` are actions, not mandatory stages. Show `AVAILABLE` whenever a valid source archive exists. They must not remain `PENDING` just because the user has not chosen to restore something.
- **Chroot:** Show `AVAILABLE` whenever a usable rootfs exists; otherwise `PENDING` because there is nothing to enter yet.
- **Installer launch:** Show `AVAILABLE` whenever a valid base rootfs archive exists and the installer can be discovered; otherwise `PENDING`. Launching the installer is an action, so it should not be labeled `COMPLETE` simply because it was run once.

### 67. Add graphical base-rootfs archive selection and browsing
- [x] UI / workflow enhancement
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Installer base archive selection
- **Goal:** Avoid requiring the user to manually type a base-rootfs archive path when the archive is outside the default location.
- **Default archive behavior:** First search/check the normal BFSOS base-rootfs archive location. If a usable archive exists, show the discovered archive and its full path and offer to use it immediately.
- **Newest archive selection:** When multiple valid base archives exist in the default location, automatically choose the newest one. If the filename contains the BFSOS date/time stamp, sort by that embedded timestamp first; fall back to file modification time only when a reliable timestamp cannot be parsed from the name.
- **Deterministic tie-break:** If two candidates resolve to the same parsed timestamp, use a stable secondary sort (such as modification time then filename) so selection is predictable.
- **Display:** The detected/default archive screen should identify that it is the newest available archive and show the selected filename, full path, size, and timestamp before the user accepts it.
- **Default archive choices:** When an archive is found, provide clear actions to use the detected archive, browse/select a different archive, or go Back.
- **Missing-default behavior:** If no usable archive exists in the default location, open the file-selection/browse interface automatically rather than presenting a dead/default path.
- **Browse interface:** Use a Dialog file selector such as `--fselect` when available so the user can navigate directories and choose the base archive interactively.
- **Archive validation:** After selection, verify the selected path exists, is a regular readable file, and uses an archive/compression format supported by the installer before accepting it.
- **Confirmation:** Show the selected archive's full path and useful metadata such as file size before committing the selection.
- **Session behavior:** Preserve the selected archive path for the remainder of the installer session and in installer profile/state handling where appropriate.
- **Bootstrap integration:** When the installer is launched from the bootstrap workflow added by #65, prefer the rootfs archive just created by bootstrap as the detected/default archive.
- **Text-mode fallback:** If Dialog/file selection is unavailable, retain a text-mode path prompt with validation rather than making archive selection impossible.
- **Regression test:** Test with (1) a valid archive in the default location, (2) no default archive, (3) choosing a different archive despite a valid default, (4) invalid/non-readable selections, and (5) launching from bootstrap immediately after archive creation.


## r30 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No installer/bootstrap code changed in this revision.
- **Added:** #67 interactive base-rootfs archive discovery/browsing with default-archive preference, validation, and bootstrap handoff support.


## r31 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No bootstrap or installer code changed in this revision.
- **Updated #65:** Bootstrap installer launch must discover the newest versioned installer under `scripts/` instead of hard-coding one filename.
- **Updated #66:** A valid existing base-rootfs archive in the default archive directory can satisfy installer readiness and should be reflected in bootstrap menu status.
- **Updated #67:** When multiple default base archives exist, select the newest archive deterministically, preferring the date/time embedded in the filename when present.


### 69. Normalize bootstrap `PENDING` / `AVAILABLE` / `COMPLETE` status logic
- [x] UI / workflow fix
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Bootstrap menu status indicators
- **Observed behavior:** The current bootstrap helper treats nearly every non-completed item as `PENDING`, including restore operations that are already usable when an archive exists. Chroot is handled separately as `AVAILABLE`, so the menu currently mixes completion state and action availability inconsistently.
- **Required semantics:**
  - `PENDING` — a required prerequisite or required build result is not yet satisfied.
  - `AVAILABLE` — the action can be run now, but running it is optional/repeatable and it is not a required completion gate.
  - `COMPLETE` — a build, verification, or archive requirement has been satisfied.
- **Expected menu behavior:**
  - Temporary toolchain build: `PENDING` -> `COMPLETE`.
  - Base-system build with temporary toolchain: `PENDING` -> `COMPLETE`.
  - Optional final rebuild (stage 3): `AVAILABLE` -> `COMPLETE`; never `PENDING` solely because it was skipped.
  - Verify completed base system: `PENDING` -> `COMPLETE`.
  - Create/compress base rootfs archive: `PENDING` -> `COMPLETE` once a valid archive exists.
  - Restore newest base rootfs archive: `AVAILABLE` whenever a valid archive exists; otherwise `PENDING`.
  - Restore newest temporary toolchain archive: `AVAILABLE` whenever a valid toolchain archive exists; otherwise `PENDING`.
  - Chroot into BFS rootfs: `AVAILABLE` when a usable rootfs exists; otherwise `PENDING`.
  - Launch BFSOS installer: `AVAILABLE` when a valid base archive exists and a current installer is discoverable; otherwise `PENDING`.
- **Implementation:** Replace the one-size-fits-all `_stage_complete_text` / `_dialog_stage_status` use with per-action status helpers or a generic status function that can distinguish completion checks from availability checks.
- **Consistency:** Text-mode and Dialog menus must report the same status for every option.
- **Regression test:** Test a clean tree, completed stage 1 only, completed stage 2, skipped stage 3, verified base, archive present, restored rootfs, restored toolchain, and installer-ready states. Confirm each menu item uses exactly the expected `PENDING`, `AVAILABLE`, or `COMPLETE` label.


## r32 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No bootstrap or installer code changed in this revision.
- **Updated #66:** Defined exact `PENDING`, `AVAILABLE`, and `COMPLETE` semantics for the streamlined bootstrap/install workflow.
- **Added #69:** Normalize status logic in both text and Dialog bootstrap menus, especially optional stage 3, restore actions, chroot, and installer launch.


### 70. Offer ZRAM swap when no disk swap is configured
- [x] Enhancement
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Installer storage / swap configuration
- **Trigger:** After storage assignment is complete, detect whether the installed system has a configured swap partition or swap logical volume.
- **No-swap behavior:** If no disk-backed swap is configured, ask whether the user wants to enable ZRAM swap on the installed BFSOS system.
- **Prompt:** Clearly explain that ZRAM provides compressed swap in RAM and does not require a swap partition.
- **Default:** Yes when no other swap exists, while still requiring the user to confirm the choice.
- **Existing-swap behavior:** If disk-backed swap exists, do not silently enable ZRAM. Either skip the ZRAM prompt or present ZRAM separately as an optional supplemental swap choice.
- **Kernel validation:** Before configuring ZRAM, verify the target kernel/config/modules provide ZRAM support (for example built-in `CONFIG_ZRAM=y` or module `CONFIG_ZRAM=m` with the corresponding module installed). Do not assume support from the live environment.
- **Configuration:** Install/write the appropriate BFSOS/systemd ZRAM configuration so ZRAM swap is created automatically during normal boot.
- **Failure behavior:** If the user selects ZRAM but the installed kernel or required userspace support is unavailable, show a clear warning/error and do not claim ZRAM is enabled.
- **Review screen:** Explicitly show both disk swap and ZRAM state, for example `Disk swap: none` and `ZRAM swap: enabled`, so compressed swap is not hidden from the installation summary.
- **Post-install verification:** Verify the installed configuration exists and is enabled before declaring the ZRAM setup successful.
- **Regression test:** Test (1) no swap + ZRAM Yes, (2) no swap + ZRAM No, (3) disk swap configured, (4) ZRAM kernel support missing, and (5) reboot of a completed ZRAM-enabled install followed by `swapon --show`/equivalent verification.


## r33 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No installer/bootstrap code changed in this revision.
- **Added:** #70 optional ZRAM swap configuration when no disk-backed swap is selected, including target-kernel validation, review visibility, boot-time configuration, and post-install verification.


### 71. Keep final GRUB verification consistent with generated storage arguments
- [x] Fix
- **Implemented in r35:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh` and/or `bootstrap.sh` as applicable.
- **Area:** Final installation validation / success transition
- **Observed behavior:** r27 generated explicit `rd.md.uuid=` arguments, then aborted the installation because the verifier still required `rd.auto`. This prevented the normal successful-installation Chroot/Finish menu from appearing.
- **Desired behavior:** The final verifier must validate exactly the storage arguments the generator intentionally emits. Do not require obsolete/alternative arguments that are not part of the chosen generation strategy.
- **Failure reporting:** When validation fails, clearly state which expected argument/value is missing or malformed. For MD RAID, print the expected complete UUID and the actual generated kernel line.
- **Success transition:** Only after final GRUB/initramfs verification succeeds should the installer show the Installation Complete dialog and the Chroot/Finish menu.
- **Logging:** Keep logging active through final verification and the post-install transition so any late failure is captured in the installer log.
- **Regression test:** Test successful and intentionally broken RAID/LUKS/LVM cmdlines. Broken configuration must fail with an actionable message; correct configuration must pass and reach the post-install menu.


## r34 Tracker Update

- **Generated:** 2026-08-11
- **Tracker-only update:** No installer/bootstrap code changed in this revision.
- **Reopened/expanded #57:** r27 truncated colon-separated MD UUIDs, omitted explicit LUKS UUID arguments for the tested topology, and used a stale verifier that still required `rd.auto`.
- **Added #71:** Keep final GRUB verification synchronized with generated storage arguments and preserve logging through the final validation/post-install transition.
- **Test conclusion:** The missing Chroot/Finish menu was a consequence of final GRUB verification failure, not a standalone menu bug.

## r35 Implementation Pass

- **Generated:** 2026-08-11
- **Installer moved for normal workflow:** `scripts/install-bfs-menu-v50-tracker-fixed-r35.sh`
- **Bootstrap:** `bootstrap.sh`
- **Implemented:** #57, #58, #62, #63, #64, #65, #66, #67, #69, #70, #71.
- **#54:** Installed-system safeguard implemented; source `aaa_filesystem/Pkgfile` remains pending because that port file was not supplied in this pass.
- **GRUB fix:** Full colon-separated MD UUIDs are preserved, explicit LUKS UUIDs come from finalized crypttab, and verification no longer requires stale `rd.auto`/`rd.md=1`.
- **Bootstrap/install handoff:** Bootstrap discovers the newest executable versioned installer under `scripts/` and hands it the newest valid base archive.
- **Normal bootstrap path:** stages 1, 2, 4, and rootfs archive creation are required; stage 3 is optional and reports AVAILABLE until completed.
- **Package policy:** every install performs `ports -u` followed by mandatory `prt-get sysup`; optional packages are installed afterward.
- **Post-install cleanup:** user is asked whether to clear `/var/cache/pkg/packages/*`; default is No.
- **Swap policy:** when no disk swap is selected, installer offers ZRAM (default Yes) and validates installed-kernel ZRAM support before enabling its systemd service.
## r38 Tracker Update

- **Generated:** 2026-08-11
- **Bootstrap:** `bootstrap.sh` through r42
- **Installer:** no installer code changed in this tracker update.
- **Bootstrap changes below are completed and regression-tested interactively in the VM unless otherwise noted.**

### 72. Fix bootstrap theme Settings workflow and defaults
- [x] UI / workflow fix
- **Implemented in:** `bootstrap.sh`
- **Area:** Bootstrap Settings / interface themes
- **Default theme:** Classic Slackware is the startup default on every normal bootstrap invocation. A stale saved theme from an earlier test must not silently make Debian or another theme the startup default.
- **Theme choices:** The bootstrap Settings theme selector now exposes all supported themes in one place:
  - `Slackware` — Classic Slackware theme and default.
  - `Debian` — Classic Debian installer/newt-style theme.
  - `Monochrome`.
  - `Midnight`.
  - `Light`.
- **Visible theme labels:** Capitalize the first character of every left-hand theme name. Use `Debian`, not the internal identifier `classic`, as the visible label.
- **Internal compatibility:** The Debian palette may continue to use the existing internal `classic` theme key so the underlying implementation does not need to be renamed.
- **Back behavior:** Back/Esc from the theme selector returns cleanly to the previous/bootstrap menu. Navigating Settings must not produce `Operation completed successfully` or a `Press Enter to return to the menu...` pause.
- **Settings layout:** The main bootstrap menu shows only `Settings`, with no current-theme text on the right-hand side so additional settings can be added later without changing the main-menu layout.
- **Menu placement:** `Settings` is no longer a numbered/scrollable menu entry. It is a dedicated bottom dialog button positioned between `<Select>` and `<Quit>`.
- **Regression test:** Start bootstrap with no special environment override, confirm Classic Slackware is selected by default, open Settings, verify all five themes and capitalization, apply each theme, use Back/Esc, and confirm the main menu returns immediately without an operation-success/pause screen.

### 73. Use AVAILABLE / NOT AVAILABLE for bootstrap chroot status
- [x] UI / workflow fix
- **Implemented in:** `bootstrap.sh`
- **Area:** Bootstrap main-menu status
- **Observed behavior:** Chroot was shown as `PENDING`, which incorrectly implied it was an unfinished required stage.
- **Desired behavior:** Chroot is an optional action and must display only:
  - `AVAILABLE` when a usable restored BFSOS environment exists.
  - `NOT AVAILABLE` when it cannot currently be entered.
- **Availability gate:** Do not mark chroot available merely because a base archive or toolchain archive exists. Require that the base rootfs and/or temporary toolchain has actually been restored into the working tree and that a usable Bash exists in the rootfs.
- **Consistency:** Apply the same wording and availability logic to both Dialog and text-mode bootstrap menus.
- **Regression test:** With only archives present, verify Chroot shows `NOT AVAILABLE`; restore the base rootfs or temporary toolchain as appropriate and verify it changes to `AVAILABLE` only when the restored filesystem is actually usable.

### 74. Match installer theme-name capitalization to bootstrap
- [x] UI consistency fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r36.sh`. Theme selector now shows `Slackware`, `Debian`, `Monochrome`, `Midnight`, and `Light`, with Slackware first/default and internal `classic` compatibility preserved.
- **Area:** Installer Settings / interface themes
- **Observed behavior:** Bootstrap now presents the left-hand theme names as `Slackware`, `Debian`, `Monochrome`, `Midnight`, and `Light`, while the installer still needs the same visible naming convention.
- **Desired behavior:** Update the installer theme-selection UI to use the same capitalization and user-facing names as `bootstrap.sh`.
- **Required visible names:** `Slackware`, `Debian`, `Monochrome`, `Midnight`, `Light`.
- **Debian naming:** Show `Debian` in the selector rather than exposing an internal theme key such as `classic`; descriptions may still identify it as the Classic Debian installer/newt-style theme.
- **Default:** Classic Slackware remains the installer default.
- **Compatibility:** Preserve internal theme keys/profile compatibility where practical; this is a display-name/UI consistency change, not a requirement to rename stored identifiers.
- **Regression test:** Compare installer and bootstrap theme selectors side-by-side and confirm theme names, capitalization, order/default behavior, and descriptions are consistent.
### 75. Return directly to bootstrap after installer exits
- [x] UI / workflow fix
- **Implemented in:** `bootstrap-r44-tracker-complete.sh`. Returning from the installer now resets the terminal and immediately redraws bootstrap with no generic success/failure message or Enter pause.
- **Area:** Bootstrap-to-installer handoff / return behavior
- **Observed behavior:** After the installer exits back to `bootstrap.sh`, bootstrap currently shows:
  - `Operation completed successfully.`
  - `Press Enter to return to the menu...`
- **Desired behavior:** When the installer exits normally or is cancelled and control returns to bootstrap, immediately redraw and return to the bootstrap main menu.
- **Do not show:** No generic `Operation completed successfully.` message and no `Press Enter to return to the menu...` pause for the installer-launch action.
- **Scope:** This exception applies specifically to the `Launch BFSOS installer` menu action. Normal build stages may continue to show completion/failure output and pause when that output is useful.
- **Terminal handling:** Restore/reset the terminal cleanly after the installer exits before redrawing the bootstrap menu so no installer colors, background, cursor state, or stale screen content remain.
- **Regression test:** Launch the installer from bootstrap, then test both normal installer exit and Cancel/Back/Quit paths. In every case, confirm control returns immediately to the bootstrap main menu with no intermediate success/pause screen.

### 76. Move Bootstrap Settings to bottom action-button row
- [x] UI / workflow fix
- **Implemented in:** `bootstrap.sh` r43
- **Area:** Bootstrap main menu
- **Observed behavior:** `Settings` was incorrectly added as a numbered item at the bottom of the scrollable bootstrap menu.
- **Desired behavior:** Remove `Settings` from the numbered menu entries and place it on the bottom action-button row between `Select` and `Quit`.
- **Final dialog button order:** `<Select>`  `<Settings>`  `<Quit>`.
- **Behavior:** Selecting the Settings button opens the existing Bootstrap Settings / Interface Theme screen; returning from Settings redraws the bootstrap main menu normally.
- **Compatibility:** Text-mode fallback retains the numeric Settings choice because it has no dialog button row.
- **Status:** Completed in bootstrap r43.

### 77. Silently return when Chroot is NOT AVAILABLE
- [x] UI / workflow fix
- **Implemented in:** `bootstrap-r44-tracker-complete.sh`. Selecting Chroot while unavailable now immediately redraws the menu; no root-stage call, error, success message, or pause is produced.
- **Area:** Bootstrap main menu / Chroot action
- **Observed behavior:** When `Chroot into BFS rootfs` shows `NOT AVAILABLE`, pressing Enter on that menu item currently proceeds into the action path and produces an error/message before returning.
- **Desired behavior:** If Chroot is `NOT AVAILABLE`, selecting it should do nothing except immediately redraw the bootstrap main menu.
- **Do not show:** No error message, no `Operation failed`, no `Operation completed successfully`, and no `Press Enter to return to the menu...` pause.
- **Availability logic:** Continue using the existing `_chroot_available` test. The menu action should check availability before invoking the root/chroot stage.
- **Available behavior:** When Chroot shows `AVAILABLE`, Enter should continue to launch the chroot normally.
- **Regression test:** With Chroot showing `NOT AVAILABLE`, highlight it and press Enter; confirm the bootstrap menu immediately redraws with no intermediate output or pause. Then restore a usable rootfs/toolchain, confirm it changes to `AVAILABLE`, and verify Enter launches the chroot normally.
### 78. Rescan all storage after every destructive or topology-changing storage operation
- [x] Installer storage-detection bug
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r36.sh`. Added centralized `refresh_storage_state()` and wired it into cfdisk return, storage metadata destruction, RAID assembly/create/signature wipe, LUKS create/open/close, LVM PV/VG/LV creation, and filesystem/swap formatting.
- **Area:** Installer storage discovery / partitioning / filesystems / RAID / LUKS / LVM
- **Observed behavior:** Possible stale-device-state bug: after launching `cfdisk` from inside the installer and creating or changing partitions, the RAID member selection screen appeared not to reflect the newly written partition table.
- **Expanded requirement:** Do not limit the fix to `cfdisk`. After every destructive or storage-topology-changing operation, force a fresh kernel/userspace storage rescan and rebuild the installer's device inventory before presenting another storage-selection or review screen.
- **Operations that must trigger a rescan include at minimum:**
  - returning from `cfdisk` or another partition-table editor after changes;
  - creating, deleting, resizing, or rewriting partitions/partition tables;
  - formatting or reformatting filesystems and initializing swap;
  - creating, assembling, stopping, destroying, or otherwise changing MD RAID arrays;
  - creating, opening, closing, formatting, or otherwise changing LUKS mappings;
  - creating/removing/changing LVM PVs, VGs, and LVs;
  - destructive signature/wipe operations such as `wipefs`;
  - any other installer action that changes block-device names, mappings, filesystem/type metadata, sizes, parent/child relationships, or availability.
- **Refresh sequence:** Review use of `partprobe`, `blockdev --rereadpt`, `udevadm settle`, MD/LUKS/LVM discovery commands, and/or equivalent safe mechanisms as appropriate for the operation. The goal is a reliable fresh view of all storage devices, not merely the disk that was just edited.
- **No stale cache:** Do not reuse a partition/device list gathered before the destructive operation. Re-run the installer storage-enumeration logic (`lsblk` and any RAID/LUKS/LVM discovery used by the installer) after the rescan.
- **Consumers of refreshed state:** RAID member selection, filesystem/format selection, mount-point assignment, swap selection, LUKS, LVM, installation review, and every later storage screen must use the refreshed inventory.
- **Failure handling:** If the kernel cannot reread a partition table or refresh a device because it is busy, clearly report the condition rather than silently continuing with stale information.
- **Regression test:** Exercise each supported destructive/topology-changing storage path, then immediately enter the next relevant storage screen and verify device names, partitions, sizes, filesystem/type information, RAID/LUKS/LVM mappings, and availability match the new state without restarting the installer.
### 79. Verify sudo default uses password authentication
- [x] Installer configuration verification
- **Verified in source:** The installer default remains `SUDO_MODE=password`, which writes `%wheel ALL=(ALL:ALL) ALL`. `NOPASSWD` is only written when the user explicitly selects the no-password mode, matching the successful VM test.
- **Area:** Installed-system sudo / privilege escalation defaults
- **Check:** Confirm that the installer installs and configures `sudo` as the default privilege-escalation mechanism for regular users.
- **Required default:** `sudo` must require the invoking user's password by default.
- **Do not default to:** Passwordless `NOPASSWD` sudo access.
- **Configuration review:** Check `/etc/sudoers` and any installer-created files under `/etc/sudoers.d/` to make sure the regular-user/admin group rule uses normal password authentication and that no broader `NOPASSWD` rule overrides it.
- **Validation:** Run `visudo -c` on the installed system and test from a regular configured user with a cleared sudo timestamp (`sudo -k`) to confirm the next `sudo` command prompts for that user's password.
- **Regression test:** Fresh install with a normal user, log in as that user, run `sudo -k` followed by a harmless sudo command, and verify a password prompt appears and valid user credentials are required.
### 80. Make Review (option 10) flow directly into Ready to install (option 11)
- [x] Installer UI / workflow fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r36.sh`. Option 10 Review now advances directly to Ready to install; Back from Ready reopens Review; Continue starts installation without returning to the main menu.
- **Area:** Installer main menu options 10 and 11 / final pre-install workflow
- **Observed behavior:** Option 10 (`Review selections`) displays the installation review, but pressing `Continue` returns to the installer main menu instead of advancing to the final installation confirmation.
- **Correct workflow:** Options 10 and 11 should behave as one continuous pre-install sequence:
  1. Select option 10 and display the complete `Review selections` screen.
  2. Press `Continue` on the review screen.
  3. Advance directly to the option 11 `Ready to install` screen (`Begin the BFS installation?`).
  4. Press `Continue` there to begin installation.
  5. Press `Back` on `Ready to install` to return directly to the `Review selections` screen.
- **Review-screen behavior:** The important fix is not to send `Continue` back to the main menu. `Continue` must advance to `Ready to install`.
- **Main-menu option 11:** Directly selecting option 11 may continue to open the `Ready to install` stage, but the normal intended path is Review -> Ready to install -> Install.
- **No state loss:** Moving forward or backward between Review and Ready to install must preserve all current installer selections.
- **Regression test:** Enter option 10, review selections, press `Continue`, verify `Ready to install` appears immediately; press `Back`, verify the same review reappears; press `Continue` again and then `Continue` on Ready to install, and verify installation begins without returning to the main menu between these stages.
### 81. Exit directly to terminal after installation is finished
- [x] Installer UI / workflow cleanup
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r36.sh`. Removed the redundant final completion/unmount text and terminal review dump; Finish restores terminal state and returns directly to the caller while normal cleanup remains active.
- **Area:** Installer completion / final exit
- **Observed behavior:** After the installation has completed and the user finishes the post-install/chroot workflow, the installer still prints an extra completion/unmount message instead of simply returning control to the shell.
- **Desired behavior:** Once installation is complete and the user chooses to finish/exit, perform the required cleanup and unmount operations, restore the terminal state, and return directly to the live-environment terminal prompt.
- **Do not show:** No extra final `BFS installation completed...` message, no generic success message, and no `Press Enter` pause after the user has already finished the installation workflow.
- **Keep:** The existing completion/post-install screen may still provide the explicit choices to chroot into the installed system or finish the installation; this issue concerns what happens after the user chooses to finish.
- **Implementation note:** The current installer path explicitly prints `BFS installation completed. The installer will unmount the target filesystems.` after the post-install menu; remove that redundant final output while preserving cleanup/unmount behavior.
- **Regression test:** Complete an installation, use the post-install chroot option if desired, exit the chroot, then choose Finish. Confirm filesystems are cleaned up/unmounted and control returns directly to the live shell prompt with no additional completion dialog/message or pause.
### 82. Fix `bfs-zram.service` systemd ordering cycle
- [x] Installer / installed-system boot fix
- **Implemented in:** `install-bfs-menu-v50-tracker-fixed-r36.sh`. Generated ZRAM service now uses `DefaultDependencies=no`; default ZRAM capacity is dynamically set to 2× physical RAM. The ordering fix was also validated manually in the VM: ZRAM active and `systemctl is-system-running` returned `running`.
- **Area:** ZRAM swap / systemd unit ordering
- **Observed on first successful installed-system boot:** `bfs-zram.service` itself starts successfully and creates the configured ZRAM swap, but systemd reports an ordering cycle involving `tmp.mount`, `swap.target`, `bfs-zram.service`, `basic.target`, and `sysinit.target`. The cycle can cause `tmp.mount` to be dropped from the boot transaction and leaves `systemctl is-system-running` reporting `degraded`.
- **Current generated unit:** `bfs-zram.service` uses `After=systemd-modules-load.service`, `Before=swap.target`, and `WantedBy=swap.target`, while normal service default dependencies also place it after `basic.target`/`sysinit.target`. Because `tmp.mount` is `After=swap.target` and participates in the early local-filesystem ordering, this produces a dependency cycle.
- **Required fix:** Make the ZRAM setup service an explicitly early boot service by adding `DefaultDependencies=no` while retaining the required module-load ordering and `Before=swap.target` relationship. Keep it enabled from `swap.target`.
- **Target unit shape:**
  ```ini
  [Unit]
  Description=BFSOS compressed ZRAM swap
  DefaultDependencies=no
  After=systemd-modules-load.service
  Before=swap.target

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  ExecStart=/usr/libexec/bfs-zram-setup
  ExecStop=/usr/libexec/bfs-zram-stop

  [Install]
  WantedBy=swap.target
  ```
- **Default ZRAM sizing:** Set the default ZRAM device size to **2× the system's physical RAM**. Example: a system with 32 GiB RAM should default to a 64 GiB `/dev/zram0`.
- **Sizing implementation:** Calculate the size dynamically from detected physical memory rather than hard-coding a fixed size. Keep any explicit user-configured size override if the installer/settings already provide one.
- **Do not regress:** ZRAM must still be initialized before `swap.target` is considered reached, `/dev/zram0` must become active swap, and shutdown must still cleanly stop the service.
- **Regression test:** Fresh install with ZRAM enabled, cold boot, confirm there are no `Found ordering cycle` messages for ZRAM/swap/tmp, `tmp.mount` is not dropped because of the ZRAM unit, `systemctl status bfs-zram.service` is successful, `swapon --show` lists the configured ZRAM device at approximately 2× physical RAM by default, and `systemctl is-system-running` is not degraded because of this ordering issue.
### 83. Diagnose/fix VM reboot not returning after `reboot`
- [x] Boot / VM integration bug
- **Root cause found / host fix applied:** The VM launcher contained QEMU `-no-reboot`, which intentionally exits QEMU on guest reboot. The option was removed from the live launcher and its shell syntax was checked. This is a VM-launcher issue, not a BFSOS guest/GRUB defect; one reboot regression test remains to confirm behavior.
- **Area:** Installed BFSOS reboot behavior under QEMU
- **Observed behavior:** The installed BFSOS VM boots successfully from a cold start, but issuing `reboot` from the running installed system does not bring the VM back up normally/visibly. The VM appears to disappear or fail to return after shutdown/reboot.
- **Important distinction:** Cold boot from the VM launcher works, so this is not currently evidence of a GRUB/initramfs/root-filesystem boot failure. The problem appears specific to the reboot path and may involve guest shutdown/reboot handling, QEMU launcher options, firmware/UEFI reset behavior, or the installed system's reboot mechanism.
- **Investigation:** Determine whether QEMU exits completely on guest reboot, remains running but loses display/network, or resets and then fails during the next firmware/boot sequence. Inspect the launcher command line and QEMU log after reproducing the issue.
- **Checks:** Review QEMU options such as `-no-reboot`, shutdown/reboot handling, background process supervision, SPICE lifecycle, UEFI/OVMF behavior, and whether the launcher intentionally exits when the guest requests reboot.
- **Guest-side checks:** Inspect the previous boot journal (`journalctl -b -1`) after the next successful cold start for shutdown/reboot errors, and verify systemd reached the expected reboot target cleanly.
- **Do not conflate with installer boot success:** The first cold boot already proved that GRUB, initramfs, LUKS, MD RAID, LVM, Btrfs, separate `/usr`, `/opt`, `/var`, `/home`, and EFI boot all work from a powered-off VM.
- **Regression test:** Boot the installed VM, issue `reboot`, and confirm the same QEMU process successfully resets and returns to the BFSOS boot/login prompt without manually restarting the VM launcher.

## r48 Tracker Update

- **Generated:** 2026-08-11
- **Bootstrap implementation:** `bootstrap-r44-tracker-complete.sh`
- **Installer implementation:** `install-bfs-menu-v50-tracker-fixed-r36.sh`
- **Tracker status:** All currently listed code/configuration changes through issue 83 have been applied. Items whose final proof requires another install/reboot remain noted as regression tests even though the requested code change is implemented.
- **Validation performed:** Both updated shell scripts pass `bash -n`. Static checks confirm the new bootstrap short-circuit/return behavior, installer theme labels, storage refresh hooks, sudo password default, Review -> Ready flow, clean final exit, and ZRAM service/sizing changes.


## r68 Bare-metal post-install findings — 2026-08-12

### 84. Fix installer post-install chroot ordering / target cleanup
- [x] **IMPLEMENTED in installer r40; regression test pending**
- **Observed behavior:** The installation itself completed successfully, but selecting the post-install chroot option returned control to `bootstrap.sh` instead of entering the newly installed BFSOS system.
- **Root cause found during manual recovery:** By the time chroot was attempted/retried, the installed target had already been fully unmounted and the LVM/LUKS storage stack had been closed. `/mnt/bfs` therefore no longer contained the installed root and `/mnt/bfs/usr/bin/bash` could not be found.
- **Required fix:** Perform the optional post-install chroot **before** final target unmount, LVM deactivation, LUKS close, RAID teardown, and other final cleanup.
- Preserve the complete installed mount tree while the user is inside the post-install chroot.
- Only run final cleanup after the user exits the chroot and chooses to finish/return.
- If the installer ever has to reconstruct the mount tree before chroot, it must honor the configured Btrfs subvolumes rather than mounting Btrfs top-level ID 5.
- **Regression test:** Complete an install with separate Btrfs `/`, `/usr`, `/opt`, `/home`, and `/var`, choose the post-install chroot option, confirm `/usr/bin/bash` is available and the chroot opens, exit it, then confirm cleanup occurs and control returns correctly.

### 85. Preserve Btrfs subvolume mounts for post-install chroot
- [x] **IMPLEMENTED in installer r40; regression test pending**
- **Observed during manual chroot recovery:** Mounting the raw `/usr` Btrfs LV exposed only `@usr` and `@usr-snapshots`; `/usr/bin/bash` existed at `@usr/bin/bash`, not at the Btrfs top level.
- The installed layout was confirmed as:
  - `/` -> `subvol=@`
  - `/usr` -> `subvol=@usr`
  - `/opt` -> `subvol=@opt`
  - `/home` -> `subvol=@home`
  - `/var` -> `subvol=@var`
- **Required fix:** Any installer chroot/remount/recovery helper must use the exact subvolume selected/generated for each mountpoint.
- Do not treat a successfully mounted Btrfs top-level filesystem as sufficient for chroot availability.
- **Regression test:** Verify the automatic post-install chroot sees `/usr/bin/bash`, `/usr`, `/opt`, `/home`, and `/var` at their normal paths and does not expose `@usr`, `@opt`, `@home`, or `@var` as the mounted filesystem root.

### 86. Include every required LVM LV in generated GRUB `rd.lvm.lv=` arguments
- [x] **IMPLEMENTED in installer r40; regression test pending**
- **Observed after installation:** `/etc/default/grub` contained `rd.lvm.lv=` entries for `bfs-root/root`, `bfs-root/usr`, `bfs-raid/home`, and `bfs-raid/var`, but omitted the separately configured `bfs-root/opt` LV.
- **Manual correction used for this test:** Added `rd.lvm.lv=bfs-root/opt`, rebuilt the initramfs with Dracut, and regenerated `/boot/grub/grub.cfg`.
- A second manual append accidentally produced `rd.lvm.lv=bfs-root/opt` twice, demonstrating that the permanent installer fix should **generate/deduplicate** the complete argument list rather than blindly append strings.
- **Required fix:** Build GRUB/dracut LVM arguments from the final configured LV/mountpoint model. Include every LV that must be activated for the installed system and emit each `rd.lvm.lv=<vg>/<lv>` exactly once.
- At minimum for this tested layout the generated list must contain:
  - `bfs-root/root`
  - `bfs-root/usr`
  - `bfs-root/opt`
  - `bfs-raid/home`
  - `bfs-raid/var`
- Preserve both LUKS UUID arguments and the MD RAID UUID when those layers are configured.
- **Regression test:** Install with multiple LVs across both encrypted root storage and encrypted MD RAID storage, then verify `/etc/default/grub` and generated `grub.cfg` contain every required LV exactly once before first boot.

### 87. Add final generated boot-configuration validation before installer success
- [x] **IMPLEMENTED / strengthened in installer r40; regression test pending**
- The manual post-install audit showed the value of validating the generated boot configuration before reboot.
- **Required validation:** Before reporting the installation fully ready, verify the generated `fstab`, GRUB kernel command line, initramfs, EFI files, encryption/RAID/LVM references, and Btrfs subvolume mappings.
- `findmnt --verify --verbose` on this bare-metal install completed with **Success, no errors or warnings detected** after the manual corrections.
- Verify the expected kernel and initramfs exist in `/boot`, and that UEFI installs contain both the BFSOS GRUB EFI loader and the configured fallback loader when applicable.
- Treat missing required `rd.luks.uuid`, `rd.md.uuid`, `rd.lvm.lv`, root mapping, or Btrfs root subvolume argument as a pre-reboot error rather than discovering it on first boot.
- **Regression test:** Run this validation automatically on the next complex RAID + LUKS + LVM + Btrfs installation and confirm it catches an intentionally omitted required boot argument.

### 88. Rework default ZRAM sizing for very high-memory systems
- [x] **IMPLEMENTED in installer r40; regression test pending**
- **Observed on this bare-metal test:** The machine has 128 GiB RAM. The current 2x-RAM ZRAM default would imply an extremely large ZRAM configuration, and the installer warned/failed the available-root-space suitability check, so ZRAM was declined for this installation.
- **Required fix:** Do not scale the default ZRAM size indefinitely as `2 x physical RAM`.
- Add a sensible maximum/default cap and make the recommendation aware of the installed system/storage configuration.
- The installer must continue allowing the user to disable ZRAM or explicitly choose an appropriate size.
- **Regression test:** Test low-memory, typical-memory, and 128 GiB+ systems and confirm the proposed/default ZRAM size remains reasonable and never blocks or destabilizes an otherwise valid installation.

### 89. Console font bare-metal follow-up from this installation
- [x] **BARE-METAL VERIFIED:** 32-pixel `latarcyrheb-sun32` persists in `/etc/vconsole.conf`; native 4K remained physically small, while 1920x1080 console mode produced a comfortable physical size.
- The installer large-font option was not selected during this run, so this install does not yet prove the installer text-size selection path.
- Manual chroot testing confirmed `LatGrkCyr-12x22.psfu.gz` is present and `setfont LatGrkCyr-12x22` succeeds.
- `/etc/vconsole.conf` was manually changed from `FONT=Lat2-Terminus16` to `FONT=LatGrkCyr-12x22`.
- After first boot, verify systemd applies `LatGrkCyr-12x22` correctly on the real console.
- Keep the existing pre-1.0 requirement to test the installer's selectable font sizes separately; the manual change is not a substitute for that installer regression test.

### 90. Bare-metal complex-storage install and untouched first boot passed
- [x] **BARE-METAL FIRST BOOT PASSED:** complex UEFI + separate `/boot` + LUKS + LVM + Btrfs + MD RAID0 + second LUKS/LVM booted successfully; all intended subvolumes mounted, RAID assembled, SSH/sudo worked, and `systemctl --failed` reported zero failed units.
- The installer completed without an installation-stage failure on the tested UEFI + separate `/boot` + LUKS + LVM + Btrfs + MD RAID0 + second LUKS/LVM configuration.
- Post-install inspection confirmed the intended Btrfs subvolumes, RAID/LUKS/LVM layers, EFI files, kernel, initramfs, and `fstab` after the manual GRUB correction.
- **2026-08-15 untouched r41 result:** Fresh install generated the complete boot configuration automatically and cold-booted with no manual GRUB/Dracut edits. Both LUKS containers opened normally, MD RAID assembled, both VGs activated, and all configured Btrfs subvolume filesystems mounted successfully.
- This complex RAID0 + LUKS + LVM + multi-Btrfs layout is now a passed RC regression scenario. Keep separate usability/font and alternate-RAID tests open as tracked elsewhere.


### 91. Default text-console resolution for high-DPI displays
- [x] **IMPLEMENTED / DISPLAYPORT BARE-METAL VERIFIED; HDMI/other connector regression pending:** installer detects the connected DRM connector and adds a deduplicated 1920x1080@60 console `video=` argument when supported. The 2026-08-15 fresh install correctly detected the active DisplayPort output and generated `video=DP-1:1920x1080@60` without hard-coding DP globally.
- **Bare-metal result:** On the tested 3840x2160 DisplayPort monitor, the console font became very small after the DRM console switched to the native 4K mode.
- Manually adding `video=DP-1:1920x1080@60` produced a comfortable console size with the 32-pixel font and remained readable after the graphics/DRM handoff.
- **Planned default:** Add a 1920x1080 text-console video mode to the BFSOS GRUB defaults/GRUB port so new installs do not default to an excessively tiny 4K virtual console.
- Do not blindly duplicate the argument if it is already present; GRUB command-line generation should deduplicate persistent video arguments.
- Consider hardware/output-name portability before finalizing the implementation: the tested connector is `DP-1`, so the permanent mechanism should avoid assuming every machine uses that connector name if GRUB/kernel syntax allows a safer generic/default approach.
- [ ] **Regression test:** Verify 1920x1080 console mode on bare metal, HDMI/DP variants where available, and confirm it does not interfere with later graphical desktop resolution selection.

### 92. Installer console font choices: verify/fix 16, ~20/22, and 32-pixel persistence
- [x] **r42 FONT-PERSISTENCE HARDENING IMPLEMENTED; bare-metal regression pending:** retained 16 and ~20 choices plus 32-pixel Extra Large, made the BFSOS-shipped fonts explicit priorities, and added visible/logged persistence diagnostics.
- Keep the existing **16-pixel** and approximately **20-pixel** console-font choices.
- Add a new **32-pixel / Extra Large** console-font choice to the installer.
- **Bare-metal result:** `latarcyrheb-sun32.psfu.gz` is installed, loads successfully with `setfont`, and is much more usable on a 4K physical display when paired with a 1920x1080 text-console resolution.
- The earlier 22-pixel test (`LatGrkCyr-12x22`) was still effectively microscopic at native 3840x2160, so font size alone is not sufficient on high-DPI consoles.
- The installer should write the selected persistent font to `/etc/vconsole.conf`.
- If the Extra Large option is selected, consider pairing it with the installer/GRUB high-DPI console-resolution option rather than changing graphical desktop resolution.
- **2026-08-15 observation:** A fresh r41 install believed to have selected the ~20 option booted with `/etc/vconsole.conf` containing `FONT=Lat2-Terminus16`. The installed system does contain both `/usr/share/consolefonts/Lat2-Terminus16.psfu.gz` and `/usr/share/consolefonts/LatGrkCyr-12x22.psfu.gz`. Manually writing `FONT=LatGrkCyr-12x22` persisted across reboot and worked correctly, proving the font file and `systemd-vconsole-setup` path are good. Because user-selection error is still possible, treat the ~20 result as a confirmed discrepancy requiring repeat verification rather than assuming every font path is broken.
- **r42 change:** For size 16 prefer `Lat2-Terminus16`; for ~20 prefer the actually shipped `LatGrkCyr-12x22` before generic 19/20/22 fallbacks; for 32 prefer `latarcyrheb-sun32`. The installer now shows which font it found after selection, logs the exact installed `FONT=` value, and validates `/etc/vconsole.conf` after writing it.
- **16-pixel interpretation:** `Lat2-Terminus16` is likely functioning correctly but can still look very small on a 4K/high-DPI console. Do not classify appearance alone as a failure.
- [ ] **Regression test:** On fresh installs deliberately test 16, ~20/22, and 32 separately. Immediately confirm the selected size/font shown by the installer, inspect `/etc/vconsole.conf` before reboot, then verify the same font is applied by `systemd-vconsole-setup` after reboot. Expected BFSOS fonts are `Lat2-Terminus16`, `LatGrkCyr-12x22`, and `latarcyrheb-sun32` respectively when present.


### 93. Eliminate hard-coded VG/LV naming assumptions
- [x] **IMPLEMENTED in installer r40; regression test pending with arbitrary VG/LV names:** GRUB LVM discovery now derives every LV-backed fstab filesystem from the actual LVM metadata and no longer filters by assumed mountpoints/VG names.
- The installer must treat user-selected valid VG/LV names as authoritative and reuse the exact recorded names everywhere.
- Arbitrary valid names must flow consistently through LVM creation, mounts, `/etc/fstab`, `/etc/crypttab`, Dracut/initramfs configuration, `/etc/default/grub`, generated `grub.cfg`, post-install chroot/remount logic, and cleanup.
- Do not reconstruct later boot/storage configuration from assumed names such as `bfs-root`, `bfs-raid`, or `bfs-vg`.
- Build `rd.lvm.lv=` arguments from the final recorded storage model and emit each required `<vg>/<lv>` exactly once.
- **Regression test:** Deliberately install using unusual but valid names such as `test-vg-123` and another nonstandard VG name, with multiple LVs and Btrfs subvolumes. Confirm the entire install, post-install chroot, GRUB/dracut generation, cleanup, and first boot succeed without any naming-specific assumptions.

## r72 implementation pass — actionable tracker fixes consolidated
- [x] `bootstrap-r50-rc-tracker-fixed.sh` passes `bash -n`.
- [x] `install-bfs-menu-v50-tracker-fixed-r40.sh` passes `bash -n`; the generated chroot heredoc was also rendered with representative values and independently passed `bash -n`.
- [x] Stage 9 bootstrap-to-installer handoff suppresses duplicate time sync without changing standalone installer behavior.
- [x] Stage 8 normal chroot exit no longer reaches the generic success/pause handler.
- [x] Bootstrap build failures now have a Dialog/text failure summary with status, log path/context, and detected URL when available.
- [x] Installer ports/sysup/optional-package operations now record structured failure context; parent UI reports the failure instead of silently terminating at raw package output.
- [x] Installer post-install chroot reconstructs the canonical Btrfs mount tree when root is unmounted or Bash is hidden by an incomplete/top-level subvolume mount.
- [x] GRUB LVM arguments now derive from every actual LV-backed fstab filesystem, fixing omissions such as separate `/opt` and avoiding hard-coded VG names.
- [x] GRUB storage/video argument generation is idempotent/deduplicated.
- [x] High-DPI console default is generated by detecting a connected DRM connector and pairing it with 1920x1080@60; no fixed `DP-1` connector is hard-coded globally.
- [x] Installer font selector now supports Default, 16, ~20 (19/20/22 fallbacks), and 32-pixel Extra Large.
- [x] ZRAM default remains adaptive but is capped at 32 GiB by default (`BFS_ZRAM_MAX_GIB` can override the cap).
- [x] GPM is exposed in Optional Software; a valid `gpm` port still needs to be present/verified in the ports tree.

- [x] Post-install chroot mount-tree validation now checks every configured Btrfs mount against its expected subvolume and reconstructs the full tree if any role is missing/wrong.
- [x] Installer package-failure recovery now returns to the installer menu, preserves the mounted target/logs, and changes format actions to `keep` before a retry so a package/download failure does not immediately reformat the already-created filesystems.
- [x] `findmnt --verify --verbose` is now part of final installed-system validation when available; its report is preserved at `/root/bfs-fstab-verify.log`.
- [x] GRUB final validation also verifies the generated console `video=` argument when one was selected.
- [x] The 1920x1080 console default is only generated for a connected DRM output that advertises 1920x1080, avoiding an unsupported forced mode on lower-resolution displays.
- [x] GPM service enablement is attempted automatically when GPM is selected and a `gpm.service` unit is provided by the package.
- [ ] Hardware/build regression tests remain for items that cannot be proven by static script validation alone (archive interruption, clean Stage 3 locale/build-work run, Stage 6 restore, alternate RAID levels, connector variants, unusual VG/LV names, and GPM package build/service behavior).


### 94. Package/download failure checkpoint and true installer resume
- [x] **IMPLEMENTED in installer r43; destructive/runtime regression still pending:** The r40 package-failure recovery path is intended to return to the installer menu, preserve the target, and change format actions to `keep`, but real testing still showed a failed package/download path can leave the installer UI and dump the user back to a terminal/bootstrap context. Treat the existing recovery implementation as **not fully verified** until this workflow passes an actual failed-download test.
- **Required behavior on failure:** Catch failures from `ports -u`, `prt-get sysup`, `prt-get depinst`, package builds/downloads, and optional-package installation without terminating the installer process.
- Show the normal installer failure dialog with the failed operation/package, URL when detectable, exit status, and preserved log path.
- Selecting **Continue** must return directly to the installer main menu with the complete install configuration preserved.
- Preserve the already-created/mounted target and force every filesystem format action to `keep` before offering a retry. Never automatically repeat partitioning, LUKS creation, RAID creation, LVM creation, formatting, or base extraction when those stages already completed successfully.
- Record explicit install checkpoints/state, at minimum equivalent to `base_extracted`, `packages_complete`, `system_config_complete`, and `bootloader_complete`, so retry behavior is deterministic rather than inferred from partial filesystem contents.
- When **Install / Retry** is selected after a package/download failure, validate/remount the target as needed, run `ports -u` again so a repaired port tree is picked up, retry the failed/incomplete package transaction, and continue from the next incomplete checkpoint.
- A successful retry must continue normally through remaining configuration, initramfs/Dracut generation, GRUB generation/validation, and final install checks.
- The installer result/footer must preserve the real nonzero failure status while the installation is failed. Do not record `Result: SUCCESS` or exit status 0 for a failed package operation. Clear the failed state only after a successful retry or explicit user cancellation/abort handling.
- **Regression test:** Intentionally use a bad source URL so a package download fails; verify the installer stays alive and returns to its menu. Repair the port from another terminal, select Retry, confirm a fresh `ports -u` occurs, confirm no filesystem is reformatted/base archive re-extracted, and verify installation resumes through GRUB and completes successfully.

### 95. GRUB LVM argument regression — only root LV emitted with arbitrary VG names
- [x] **FIXED AND BARE-METAL REGRESSION PASSED in installer r41:** Fresh r41 install with arbitrary/non-default storage names automatically generated every required LVM argument, and the untouched system cold-booted successfully.
- **Tested topology:** LUKS mappings `shitthedam` and `fuckraid`; VGs `gotroot` and `thenotos`; LVs `gotroot/root`, `gotroot/usr`, `gotroot/opt`, `thenotos/home`, and `thenotos/var`; RAID0 `/dev/md0` underneath the second LUKS mapping.
- **Correctly generated:** `/etc/fstab` contained all five LV-backed filesystems and their Btrfs subvolumes; `/etc/crypttab` contained both custom LUKS mapping names/UUIDs; `/etc/mdadm.conf` contained the RAID UUID; LVM metadata showed both VGs and all five LVs active.
- **Incorrectly generated:** `/etc/default/grub` contained both `rd.luks.uuid=` values and the correct `rd.md.uuid=`, but only `rd.lvm.lv=gotroot/root`. Generated `grub.cfg` therefore also contained only the root LV hint.
- **Missing arguments observed:** `rd.lvm.lv=gotroot/usr`, `rd.lvm.lv=gotroot/opt`, `rd.lvm.lv=thenotos/home`, and `rd.lvm.lv=thenotos/var`.
- **Manual validation:** Adding all five `rd.lvm.lv=VG/LV` arguments to `GRUB_CMDLINE_LINUX`, then running `dracut --force --kver 7.1.5-BFS-Linux` and `grub-mkconfig -o /boot/grub/grub.cfg`, produced the expected GRUB Linux line with all five LVs plus both LUKS UUIDs, RAID UUID, `rootflags=subvol=@`, and `video=DP-1:1920x1080@60`.
- **Required installer fix:** The GRUB/Dracut topology builder must enumerate every required LV-backed filesystem from the finalized installed-system storage plan/fstab and append the actual `rd.lvm.lv=<vg>/<lv>` value for each one. Do not hard-code VG names and do not stop after the root LV.
- **r41 root-cause fix:** The r40 implementation resolved each fstab filesystem to a device and then passed that device back to `lvs` as a positional LV selector. On the real arbitrary-name topology that lookup identified the root LV but failed to identify the remaining LV-backed filesystems. r41 instead inventories all LVs with `vg_name`, `lv_name`, and `lv_path`, then matches every fstab entry by both canonical device path and filesystem UUID. This avoids dependence on whether device-mapper presents an LV as `/dev/mapper/...`, `/dev/<vg>/<lv>`, or `/dev/dm-N`.
- **Static regression proof:** A mocked five-LV test using `gotroot/root`, `gotroot/usr`, `gotroot/opt`, `thenotos/home`, and `thenotos/var` now returns all five required `VG/LV` identities. The updated full installer passes `bash -n`.
- **2026-08-15 hardware proof:** Fresh r41 install used LUKS mappings `veryveryhard` and `hardon`, VGs `bfs-nonroot` and `bfs-raidmd0`, and LVs `root`, `usr`, `opt`, `home`, and `var`. `/etc/default/grub` and all generated normal/recovery Linux lines contained all five unique `rd.lvm.lv=` arguments plus both LUKS UUIDs, the full MD UUID, `rootflags=subvol=@`, and the detected DisplayPort video argument. No manual correction was made.
- **Cold-boot proof:** The freshly installed system booted successfully without intervention. LUKS, MD RAID, LVM, Btrfs subvolumes, and GRUB/Dracut activation all worked automatically. #95 is closed.


## r75 GRUB/LVM regression fix pass — 2026-08-14

- **Installer:** `install-bfs-menu-v50-r41-grub-lvm-fix.sh`.
- **Issue #95:** implementation fixed; fresh-install hardware regression still required.
- **Cause addressed:** removed the fragile per-device positional `lvs ... "$device"` lookup used by the r40 GRUB topology builder. The new discovery path inventories all LVs and correlates fstab filesystems using canonical block-device identity and filesystem UUID.
- **Expected result:** arbitrary VG/LV names and separate LV-backed `/`, `/usr`, `/opt`, `/home`, `/var`, or other fstab mountpoints should each contribute one deduplicated `rd.lvm.lv=<VG>/<LV>` argument to `GRUB_CMDLINE_LINUX` and generated normal/recovery GRUB entries.
- **Validation performed:** updated installer passes `bash -n`; targeted mock topology test returns all five LVs from the #95 bare-metal layout.
- **Bare-metal boot evidence from 2026-08-14:** the manually corrected complex installation booted normally and the LUKS containers opened without intervention. This reinforces that the remaining #95 defect was installer GRUB argument generation rather than a fundamental GRUB/Dracut/LUKS incompatibility. The fresh-install test is still required because the successful boot used the manually corrected GRUB command line.
- **Next #95 regression:** perform a fresh install using arbitrary VG/LV and LUKS mapping names, inspect `/etc/default/grub` and `/boot/grub/grub.cfg` before reboot, verify all required `rd.lvm.lv=` arguments are present exactly once, then cold boot without manual edits.
- **Issue #94:** remains open. The current retry path preserves filesystem format selections after a chroot/package failure, but it still re-enters the broader install path and lacks the explicit durable phase checkpoints requested by the tracker. Do not mark true package/download resume complete until an intentional bad-URL test proves the installer remains in its UI and resumes from deterministic checkpoints.

### 96. Add a BFSOS LTS kernel flavor with broad hardware support and curated Debian patch backports
- [x] **SUPERSEDED/IMPLEMENTED by #121 in r101; runtime validation pending:** Add a separately maintained BFSOS LTS kernel flavor after the current GRUB/bootloader generation path is stable and regression-tested.
- **Base:** Track a supported upstream Linux LTS branch and update promptly to current stable point releases, especially for security and serious correctness fixes.
- **Configuration goal:** Provide a deliberately broad/generic kernel configuration with extensive hardware, storage, filesystem, networking, input, and platform support. Prefer modules for non-boot-critical hardware where appropriate rather than stripping support merely to minimize kernel size.
- **Boot-critical support:** Keep the storage/filesystem/device-mapper functionality required to reach common BFSOS root configurations available early enough for reliable Dracut boot, including the combinations BFSOS supports such as LUKS/device-mapper, MD RAID, LVM, Btrfs, F2FS, XFS, and common controller/storage drivers.
- **Debian patch source:** Review Debian's patch series for the matching LTS branch and selectively import applicable security fixes, serious bug fixes, hardware quirks, compatibility fixes, and useful backports that are not yet present in the chosen upstream LTS point release.
- **Do not blindly import all Debian patches:** Exclude Debian packaging/infrastructure-only changes and patches whose assumptions/dependencies do not apply to BFSOS. Every downstream patch must be auditable and have its origin/purpose recorded.
- **Patch organization:** Maintain the BFSOS LTS downstream patch series separately from the kernel configuration and document source, upstream/Debian reference, reason for inclusion, dependencies, and removal condition for each patch.
- **Kernel flavors:** Keep the normal/current BFSOS kernel for newer hardware/features while offering the LTS flavor as the conservative, long-support alternative.
- **Installer integration:** Once implemented, expose Current vs LTS through the existing kernel-selection workflow without duplicating the storage/Dracut/bootloader topology logic.
- **Security maintenance:** Treat upstream stable/LTS updates and relevant Debian security backports as ongoing maintenance; do not let the downstream patch set replace normal upstream stable updates.
- **Regression testing:** Boot-test the LTS flavor across the BFSOS storage matrix (plain partitions, LUKS, MD RAID, LVM, Btrfs subvolumes, separate `/usr`/`/opt`/`/home`/`/var` where applicable), verify Dracut/initramfs generation, modules/firmware loading, networking/input, and confirm no downstream patch breaks the Current-kernel boot path.

## r76 tracker update — 2026-08-14
- Added #96: planned BFSOS LTS kernel flavor using an upstream LTS base, broad generic hardware support, prompt stable/security maintenance, and a curated/auditable subset of applicable Debian security/bug-fix/hardware backports.
- LTS kernel implementation is intentionally sequenced after the current GRUB generation regression is resolved so boot-topology logic can be reused rather than debugged simultaneously with a second kernel flavor.


## r77 RC cleanup / font hardening — 2026-08-15
- **Installer:** `install-bfs-menu-v50-r42-font-fix.sh`; passes `bash -n`.
- **#95 closed:** r41 fresh bare-metal install generated all required arbitrary-name LVM/LUKS/MD GRUB arguments and cold-booted untouched.
- **GPM verified:** selected GPM was running automatically after boot.
- **DisplayPort console mode verified:** installer auto-detected `DP-1` and generated `video=DP-1:1920x1080@60`; HDMI/other connector variants remain optional regression coverage.
- **#92 font hardening:** ~20 now prioritizes BFSOS's shipped `LatGrkCyr-12x22`; 16 prioritizes `Lat2-Terminus16`; 32 prioritizes `latarcyrheb-sun32`. Selection now reports the chosen font, installed persistence is logged, and `/etc/vconsole.conf` is validated after writing.
- **Next clean VM bootstrap is especially valuable:** it will finally exercise the newer pkgutils/GCC locale fixes from scratch rather than inheriting the old base archive. During Stages 1-3 watch for `C.UTF-8`/`en_US.UTF-8` regressions, build-work cleanup, single startup time sync, Stage 8 availability/exit behavior, and archive creation checks already listed above.
- **Remaining substantive code item:** #94 true package/download checkpoint resume is still open and is intentionally not marked fixed; most other unchecked pre-1.0 entries are hardware/regression tests or documentation/roadmap work rather than known code defects.


### 97. Core ports / MLFS development refresh and Python package rename
- [x] **IMPLEMENTED FOR FRESH-BUILD REGRESSION:** Audited the supplied `ports/core` tree against the current MLFS development book and the BFSOS pkgutils extension model.
- Renamed the base interpreter port/package from `python` to `python3`; Bootstrap toolchain/base package lists now use `python3`. Keep `/usr/bin/python -> python3` only as a command compatibility symlink.
- Refreshed the current MLFS-facing toolchain/base set where the development instructions clearly changed, including GCC 16.2.0, Binutils 2.47, Glibc 2.44, Python 3.14.7, Linux/header 7.1.8, Gawk 5.4.1, Shadow 4.20.2, Perl 5.44.0, mpdecimal 4.0.1, pkgconf 3.0.5, Meson 1.12.0, SQLite 3.53.4, libffi 3.8.0, Vim 9.2.0954, and related Python build modules.
- Removed obsolete active x32 plumbing from the BFSOS current toolchain/bootstrap to match current MLFS development's m64+m32 model.
- Removed stale duplicate `certs` and malformed duplicate `python3-hatch_fancy_pypi_readme` ports; canonical package names are now unique and match directory names.
- Fixed BFSOS pkgutils extension source handling: correct `source[@]` iteration/archive selection, matching rename index, quoted patch iteration, and modern `.tar.zst`/`.tzst`/`.tar.lz4` recognition.
- Fixed obvious Pkgfile issues found during audit, including malformed Binutils `--enable-*` flags, `python3-pluggy` invoking ambiguous `python`, `python3-arkdown` dependency typo, pkgconf personality-directory creation/build path, and several MLFS build-option deltas.
- [x] Static validation: all modified core Pkgfiles, the pkgutils extension, and updated Bootstrap pass `bash -n`; core package names have no duplicate identities or directory/name mismatches; `REPO` regenerated.
- [ ] **Fresh VM regression:** Run a completely clean Stage 1/2/3 build before promoting the new base archive. Closely verify GCC 16.2 + Glibc 2.44 + Binutils 2.47, Python 3.14.7/OpenSSL 4, pkgconf/Meson bootstrap ordering, `python3` package naming, plain-C locale behavior, 32-bit multilib, and package/archive creation.
- Do not delete the previous known-good base/toolchain archives until this clean build and installer regression have passed.

## r78 core-ports / MLFS refresh — 2026-08-15
- Added #97 documenting the Python -> python3 package rename, current MLFS development refresh, x32 cleanup, pkgutils extension corrections, duplicate-port cleanup, and required clean-build regression.
- This pass intentionally retains BFSOS-specific CRUX/pkgutils, Dracut/systemd, kernel/storage, PAM, and separate Python-module packaging decisions rather than blindly cloning MLFS.

### 98. GCC 16.2 source extraction fails under forced plain-C locale
- [x] **IMPLEMENTED in bootstrap r55/pkgutils release 7; clean Stage 1 regression pending**
- **Area:** Bootstrap Stage 1 / pkgutils source extraction / libarchive `bsdtar` / locale handling
- **Observed on:** 2026-08-15 clean VM Stage 1 using GCC 16.2.0.
- **Observed behavior:** GCC 16.2.0 downloaded successfully, but source extraction failed before configure/compile began:
  ```text
  bsdtar -p -o -C /mnt/bfs-build/BFSOS/ports/core/gcc/work/src -xf /mnt/bfs-build/BFSOS/sources/gcc-16.2.0.tar.xz
  bsdtar: Pathname can't be converted from UTF-8 to current locale
  bsdtar: Pathname can't be converted from UTF-8 to current locale
  bsdtar: Pathname can't be converted from UTF-8 to current locale
  bsdtar: Error exit delayed from previous errors
  ```
- **Failure result:** `gcc-pass1` exited with status 5 while creating `/tmp/lfs-pkg/gcc#16.2.0-1.pkg.tar.gz`.
- **Important distinction:** This is not yet evidence that GCC 16.2 fails to compile. The failure occurs during archive extraction before the GCC build starts.
- **Locale evidence:** The Gentoo live shell itself reports `LANG=C.UTF-8` / `LC_CTYPE=C.UTF-8`, while BFSOS bootstrap/pkgutils intentionally forces the build environment to plain `C`.
- **Likely cause:** GCC 16.2's source archive contains pathname(s) that libarchive/`bsdtar` cannot convert while extraction runs under plain `C`.
- **Upstream/CRUX finding:** Modern CRUX changed `pkgmk` from `LC_ALL=POSIX` to `LC_ALL=C.UTF-8` specifically to avoid the libarchive/`bsdtar` error `Pathname can't be converted from UTF-8 to current locale`.
- **Preferred fix direction:** Follow the modern CRUX approach at the pkgmk/pkgutils layer rather than carrying a BFSOS-specific libarchive patch or permanently special-casing GCC. Use `C.UTF-8` when it is actually available, with a safe plain-`C` fallback for early bootstrap/host environments where `C.UTF-8` does not yet exist.
- **Implementation candidate:** pkgmk/pkgutils should detect whether a usable `C.UTF-8`/`C.utf8` locale is present before selecting it. If present, use it for pkgmk/archive handling; otherwise retain `C`. Keep this logic centralized so all source archives benefit, not only GCC.
- **Libarchive patch policy:** Do not add a libarchive pathname-conversion patch merely to suppress this error unless upstream provides a clearly correct fix that preserves every archive member. Avoid any workaround that can silently skip or discard files with non-ASCII pathnames.
- **Do not regress #97 locale cleanup:** Do not blindly force `C.UTF-8` throughout the entire bootstrap. Early bootstrap must still work on hosts/rootfs environments where `C.UTF-8` is unavailable and must not restore the previous `setlocale` warning flood.
- **Regression test:** On a clean Stage 1, confirm locale detection selects `C.UTF-8` when available, GCC 16.2.0 extracts successfully with no `Pathname can't be converted from UTF-8 to current locale` errors, and GCC configure/compile actually begins. Also test/fallback-review the early-bootstrap path where only plain `C` can be assumed.

### 99. Bootstrap Stage 1 package failure exits parent bootstrap instead of returning to menu
- [x] **IMPLEMENTED in bootstrap r55; deliberate-failure regression pending**
- **Area:** Bootstrap Stage 1 / package failure handling / Dialog navigation
- **Observed on:** 2026-08-15 clean VM Stage 1 when `gcc-pass1` failed during source extraction.
- **Observed behavior:** The GCC package failure caused the Bootstrap UI/process to close/exit instead of showing the normal handled-failure flow and returning to the Bootstrap main menu.
- **Regression:** This violates the previously implemented package/download failure requirement: a failed package operation must remain inside `bootstrap.sh`, present useful failure context, and allow **Continue** back to the main menu.
- **Required behavior:** Catch Stage 1 download/extraction/build/package failures without terminating the parent Bootstrap process. Show package/operation, exit status, useful log context, failed URL when applicable, and preserved log path.
- **Navigation requirement:** Selecting **Continue** after the failure must redraw the Bootstrap main menu directly. It must not exit to the shell and must not require restarting `bootstrap.sh`.
- **Scope:** Audit all Stage 1 failure paths, including failures propagated from `pkgmk`, custom/bootstrap build functions, source extraction, downloads, package creation, verification, and archive creation. The same menu-survival rule should remain consistent for other build stages.
- **Regression test:** Deliberately trigger a Stage 1 package failure, verify the error dialog/text fallback appears, choose Continue, and confirm the Bootstrap main menu remains alive. Then repair the cause and rerun Stage 1 from the same Bootstrap session.

## r79 clean-bootstrap findings — 2026-08-15
- Added #98 for the confirmed GCC 16.2.0 `bsdtar` UTF-8 pathname extraction failure under the forced plain-`C` build locale.
- Added #99 for the confirmed Bootstrap Stage 1 regression where a package failure exits the parent Bootstrap instead of returning to its main menu.
- Keep both issues open until fixes are exercised by the current completely clean VM bootstrap.
- GCC 16.2 remains the intended BFSOS test version; do not classify this extraction failure as a GCC compiler/build failure unless GCC later fails after extraction succeeds.


## r80 tracker clarification — 2026-08-15
- Updated #98 after reviewing the modern CRUX handling of this longstanding libarchive/`bsdtar` UTF-8 pathname issue.
- Preferred BFSOS solution is now CRUX-style `C.UTF-8` use in pkgmk/pkgutils when available, with a safe plain-`C` fallback for early bootstrap environments.
- Explicitly prefer the centralized pkgmk/pkgutils solution over a GCC-only extraction workaround.
- Do not carry a libarchive patch solely to hide the error unless a verified upstream fix preserves all archive members and semantics.

### 100. Update Glibc 2.44 patch set to current MLFS development patches
- [x] **IMPLEMENTED / PATCH FILES VERIFIED; clean-bootstrap regression pending**
- **Area:** `ports/core/glibc` / MLFS development alignment
- **Current MLFS development patch set supplied/verified during audit:**
  - `glibc-2.44-upstream_fix-1.patch`
    - Download: `https://www.linuxfromscratch.org/patches/downloads/glibc/glibc-2.44-upstream_fix-1.patch`
    - MD5: `5d589fb5bf76f3efaa19dcd12d4484a4`
  - `glibc-fhs-1.patch`
    - Download: `https://www.linuxfromscratch.org/patches/downloads/glibc/glibc-fhs-1.patch`
    - MD5: `9a5997c3452909b1769918c759eff8a2`
- **Required action:** Ensure the BFSOS Glibc 2.44 port carries and applies the current `glibc-2.44-upstream_fix-1.patch` and `glibc-fhs-1.patch` according to the current MLFS development build instructions.
- **Do not carry forward:** Do not apply the older Glibc 2.43 Linux-7/upstream-fix patch to Glibc 2.44 merely because stale/indexed MLFS pages still expose it.
- **Patch audit rule:** Verify patch filenames, checksums, application order, strip level, and whether each patch applies in every BFSOS Glibc bootstrap/final-build phase that needs it.
- **Regression test:** During the current clean VM bootstrap, verify both patches apply cleanly to Glibc 2.44 and that all Glibc bootstrap/final build phases complete successfully.
- **Ports-updater note:** Future automatic ports updater should compare the live MLFS development package and patch pages plus patch checksums, so a version bump cannot silently retain a stale version-specific patch.

## r81 tracker update — 2026-08-15
- Added #100 for the current MLFS Glibc 2.44 patch set.
- Recorded exact filenames and MD5 checksums for `glibc-2.44-upstream_fix-1.patch` and `glibc-fhs-1.patch`.
- Added an explicit requirement not to carry the older Glibc 2.43 version-specific fix into the 2.44 port.

### 101. Remove or move temporary-toolchain archive compression status into Dialog UI
- [x] **IMPLEMENTED in bootstrap r55; UI regression pending**
- **Area:** Bootstrap / temporary toolchain archive creation / Dialog output
- **Observed text:** `Compressing verified temporary toolchain archive...`
- **Current behavior:** This status line is printed directly to the terminal during the Dialog-driven Bootstrap workflow.
- **Required cleanup:** Either remove the line entirely if the existing progress/status UI already makes the operation obvious, or display the message inside an appropriate Dialog box/gauge rather than writing it behind/around the Dialog interface.
- **Preferred behavior:** Keep long-running archive compression visibly acknowledged, but make the presentation consistent with the rest of the Bootstrap Dialog UI.
- **Regression test:** Create a verified temporary toolchain archive from the menu and confirm no stray `Compressing verified temporary toolchain archive...` text is left on the terminal outside the Dialog interface.

## r82 tracker update — 2026-08-15
- Added #101 for Bootstrap UI cleanup of the `Compressing verified temporary toolchain archive...` terminal message.
- Track either removal of the redundant line or migration into the Dialog UI, with preference for retaining useful long-operation feedback without stray terminal output.

### 102. Move successful toolchain/archive completion text fully into Dialog UI
- [x] **IMPLEMENTED in bootstrap r55; UI regression pending**
- **Area:** Bootstrap / Stage 1 completion / verified toolchain archive / Dialog output
- **Observed terminal output:**
  ```text
  Toolchain build completed.
  Archive created and verified:
    /mnt/bfs-build/BFSOS/archives/toolchain/bfs-toolchain-0.9.0-20260815.tar.xz

  Operation completed successfully.

  Press Enter to return to the menu...
  ```
- **Current behavior:** Successful Stage 1/toolchain archive completion drops out of the Dialog presentation and prints completion/archive information plus a raw `Press Enter` prompt to the terminal.
- **Required cleanup:** Present the successful toolchain-build/archive result in a Dialog message box (or equivalent existing Bootstrap success dialog) and return directly to the main menu through Dialog navigation.
- **Information to preserve:** Keep the fact that the toolchain build completed, that the archive was created and verified, and the final archive path. These are useful completion details and should not simply be discarded.
- **Remove raw terminal prompt:** `Press Enter to return to the menu...` should not be necessary in the Dialog-driven workflow.
- **Consistency requirement:** Review #101 and #102 together so archive compression progress and archive success/failure all use a consistent Dialog-based presentation rather than alternating between Dialog and terminal output.
- **Regression test:** Complete Stage 1 and archive verification; confirm useful completion details appear in Dialog, no stray completion text/raw Enter prompt remains on the terminal, and dismissing the success dialog returns directly to the Bootstrap main menu.

## r83 tracker update — 2026-08-15
- Added #102 as part of the same Bootstrap archive/UI cleanup identified in r82/#101.
- Successful toolchain/archive completion information should remain visible, but inside Dialog rather than as terminal output followed by a raw Enter prompt.

### 103. Allow pkgutils upgrades to replace only BFSOS release-identity files under `/etc`
- [x] **IMPLEMENTED in pkgutils configuration; upgrade regression pending**
- **Area:** `pkgutils` / `pkgadd` / `aaa_filesystem` upgrades / release metadata
- **Problem:** BFSOS release/version identity files must update when `aaa_filesystem` is upgraded, but normal `/etc` configuration-file protection must remain intact.
- **Explicit distribution-owned replacement allowlist:**
  ```text
  /etc/os-release
  /etc/bfs-release
  /etc/lfs-release
  /etc/issue
  ```
- **Required behavior:** When a package upgrade installs one of the four files above, `pkgadd`/pkgutils should replace the installed copy with the package's new version so BFSOS version and release branding update automatically.
- **Do NOT generalize this exception:** Other files under `/etc` must retain normal configuration-file preservation/replacement safeguards. In particular, this requirement must not cause arbitrary administrator-modified configuration files to be overwritten.
- **Implementation preference:** Use a small explicit pathname allowlist/special case in pkgutils rather than disabling `/etc` protection globally.
- **Package ownership:** These files are generated/owned by `aaa_filesystem`; keep their source-of-truth version/branding content there.
- **Upgrade test:** Install an older `aaa_filesystem`, locally verify the four release files contain the old BFSOS version, then upgrade to a package containing a newer BFSOS version. Confirm all four allowlisted files are replaced automatically while an unrelated modified `/etc` configuration file remains preserved according to normal pkgutils behavior.
- **prt-get test:** Repeat through the normal `prt-get sysup` upgrade path so the behavior is proven in the workflow users will actually use.

## r84 tracker update — 2026-08-15
- Added #103 for narrowly scoped replacement of BFSOS release-identity files during package upgrades.
- The exception is limited to `/etc/os-release`, `/etc/bfs-release`, `/etc/lfs-release`, and `/etc/issue`; normal `/etc` configuration protection must remain unchanged.

### 104. Avoid duplicate raw-text + Dialog presentation for handled Bootstrap failures
- [x] **IMPLEMENTED in bootstrap r52; regression test pending**
- **Area:** Bootstrap failure UI / Dialog cleanup
- **Observed behavior:** When a package/build operation failed, the raw terminal build output remained visible and then the same failure details were shown again inside the Bootstrap failure Dialog, producing a duplicate/raw-text-plus-Dialog presentation.
- **Required behavior:** Preserve live package/build output while the stage is running, but once the failure is being handled by the Bootstrap UI, clear/reset the terminal before drawing the failure Dialog so the final handled error is presented only through Dialog.
- **Text-mode fallback:** If Dialog is unavailable, continue to print the failure summary and pause in text mode.
- **Implementation:** r52 calls the centralized terminal-reset helper immediately before and after the handled failure Dialog.
- **Regression test:** Trigger a package failure under Dialog mode; confirm the handled failure appears cleanly in the Dialog without stale/raw terminal error text remaining behind/around it, then Continue returns to the Bootstrap menu.

### 105. Build Ninja before pkgconf in Stage 2
- [x] **IMPLEMENTED in bootstrap r51/r52; clean-build regression pending**
- **Area:** Bootstrap Stage 2 package ordering
- **Observed behavior:** `pkgconf` 3.0.5 configures through Meson, and Meson failed with `ERROR: Could not detect Ninja v1.8.2 or newer`.
- **Required order:** Build/install `ninja` before `pkgconf`; keep the normal packaged `meson` build later in the base package sequence.
- **Implementation:** Moved `ninja` directly before `pkgconf` and removed its later duplicate entry.
- **Regression test:** Resume/re-run Stage 2 and confirm Ninja builds first, pkgconf's Meson invocation finds Ninja, and pkgconf completes successfully.

## r85 tracker update — 2026-08-15
- Added #104 for the duplicate raw-text plus Dialog failure presentation; implemented in bootstrap r52.
- Added #105 for the newly required Ninja-before-pkgconf Stage 2 ordering; implemented in bootstrap r51/r52.

### 106. Make pkgutils extension apply bootstrap patches automatically
- [x] **IMPLEMENTED in files/pkgmk.bootstrap; clean Stage 1 patch regression pending**
- **Area:** `ports/core/pkgutils/extension` / `pkgmk` bootstrap mode / patch application
- **Problem:** Bootstrap-specific patches currently require package-level/manual handling instead of being applied consistently by the shared pkgutils extension.
- **Required behavior:** Teach the pkgutils extension to detect and apply patches correctly during bootstrap builds, using the same source-array/renames logic and patch ordering rules as normal package builds.
- **Bootstrap scope:** When `BOOTSTRAP=1` is active, any patch listed for the port that is intended for bootstrap must be staged and applied automatically before `bootstrap_build()` runs.
- **Do not double-apply:** Ensure the same patch is not applied once by the extension and again by a Pkgfile's explicit bootstrap logic.
- **Ordering:** Preserve the order patches are listed in `source=()` unless a port explicitly documents another order.
- **Path handling:** Support local patch files and downloaded patch URLs, including renamed sources where `renames=()` is used.
- **Failure behavior:** A patch failure must stop the package build immediately, identify the patch that failed, and be captured in the package log/failure Dialog.
- **Compatibility:** Normal non-bootstrap `pkg_build()` patch handling must remain unchanged.
- **Regression test:** Use at least one Stage 1 package with a real bootstrap patch and verify the extension applies it automatically, the patch is applied exactly once, the package builds, and a deliberately broken patch produces a clean logged failure.

## r86 tracker update — 2026-08-15
- Added #106 to centralize bootstrap patch application in the pkgutils extension.
- Goal is to remove per-port/manual bootstrap patch handling where possible while preventing double application and preserving deterministic patch order.

### 107. Fix LC_ALL=C.UTF-8 in the special Stage 1 pkgutils bootstrap path
- [x] **SUPERSEDED/IMPLEMENTED by #111 dynamic locale selection; clean Stage 1 regression pending**
- **Area:** `bootstrap.sh` temporary-toolchain pkgutils bootstrap
- **Root cause confirmed:** Stage 1 initially installs pkgutils directly from the upstream pkgutils tarball before the normal `ports/core/pkgutils/Pkgfile` can be used. Therefore the locale fix already present in the pkgutils port's `bootstrap_build()` does not affect the first `$TOOLS/bin/pkgmk`.
- **Observed result:** `/tmp/lfs-tools/bin/pkgmk` contains `export LC_ALL=C.UTF-8`. After a Stage 2 restart, pkgmk emits `setlocale: LC_ALL: cannot change locale (C.UTF-8)` because that locale is not guaranteed to exist in the early BFSOS rootfs.
- **Required fix:** In the special Stage 1 pkgutils installation block, after extracting `pkgutils-5.40.12` and before `make`, patch `pkgmk.in`:
  `sed -i 's/^export LC_ALL=C\.UTF-8$/export LC_ALL=C/' /tmp/pkgutils-5.40.12/pkgmk.in`
- **Consistency:** Keep the existing equivalent fixes in `ports/core/pkgutils/Pkgfile` so both the initial bootstrap pkgmk and the later packaged/final pkgmk use a locale guaranteed to exist.
- **Regression test:** On the next completely clean Stage 1, verify:
  - `/tmp/lfs-tools/bin/pkgmk` contains `export LC_ALL=C`
  - no `C.UTF-8` setlocale warning appears when Stage 2 starts or resumes
  - normal pkgutils build later in Stage 2 still installs a pkgmk using the intended locale behavior.
- **Current build:** Do not interrupt the current Stage 2 solely for this warning; it is nonfatal.

### 108. Remove or clearly archive obsolete duplicate bootstrap implementations
- [x] **IMPLEMENTED in consolidated project cleanup**
- **Area:** repository bootstrap-script maintenance
- **Observed duplicates:** `bootstrap.sh`, `files/bootstrap-with-systemd-fixes.sh`, and `scripts/bootstrap.sh`.
- **Risk:** Old copies can receive fixes accidentally or be mistaken for the authoritative bootstrap. The legacy `scripts/bootstrap.sh` still references pkgutils 5.40.10 and older package naming such as `python`.
- **Required action:** Make root `bootstrap.sh` the clearly authoritative implementation. Remove obsolete copies if no longer needed, or move/archive them with unmistakable legacy naming and documentation.
- **Regression check:** Search the repository afterward for stale bootstrap package lists, old pkgutils versions, and old `python` package references.

## r87 tracker update — 2026-08-15
- Added #107 for the confirmed Stage 1 special-pkgutils locale bug that bypasses the existing pkgutils Pkgfile fix.
- Added #108 to clean up obsolete duplicate bootstrap implementations and prevent future fixes from being applied to the wrong script.



### 109. Clean up Stage 5 privilege/compression transition output
- [x] **IMPLEMENTED in bootstrap r55; UI regression pending**
- **Area:** interactive Bootstrap menu / base rootfs archive creation
- **Observed output:** `Stage 5 requires root privileges.`, `Running: sudo ./bootstrap.sh 5`, and `Compressing verified base rootfs archive...`.
- **Desired behavior:** When Stage 5 is launched from the interactive Dialog menu, either keep the compression/status message inside a Dialog/progress-style box or suppress the transition text entirely until the completion/failure Dialog.
- **Privilege escalation:** Hide the raw root-privilege and `sudo` command messages during the normal Dialog-driven menu path.
- **Text-mode/direct invocation:** Preserve useful privilege and compression messages when Dialog is unavailable or Stage 5 is run directly from a shell.
- **Failures:** Do not hide archive creation or verification errors; they must still reach the failure reporting/log mechanism.
- **Regression test:** Launch Stage 5 from the interactive menu and verify there is no unnecessary raw sudo/compression transition text, while direct Stage 5 invocation remains understandable.

## r88 tracker update — 2026-08-15
- Added #109 for Stage 5 Dialog/UI cleanup around sudo privilege escalation and the `Compressing verified base rootfs archive...` status.

### 110. Regenerate bootloader configuration after successful kernel initramfs generation
- [x] **IMPLEMENTED in linux release 2 post-install; kernel-upgrade regression pending**
- **Area:** kernel package install/upgrade hooks
- **Goal:** After a kernel is installed and Dracut successfully creates/updates its initramfs, automatically regenerate the active GRUB configuration so the new kernel is immediately represented in the boot menu.
- **Required order:** kernel/modules install -> Dracut -> bootloader configuration update.
- **GRUB behavior:** If `grub-mkconfig` exists and `/boot/grub` is present, run `grub-mkconfig -o /boot/grub/grub.cfg` only after Dracut succeeds.
- **Failure safety:** If Dracut fails, do not regenerate GRUB as though the kernel installation completed successfully; propagate/report the failure.
- **Old initramfs cleanup:** After the new kernel and its initramfs have been successfully installed and verified, remove obsolete initramfs images from `/boot` that belong to kernel versions no longer installed. Never remove the currently running kernel's initramfs or the newly generated image.
- **Cleanup ordering:** Perform stale initramfs cleanup only after the new Dracut image succeeds, then regenerate GRUB so removed images/obsolete entries are not retained in the final bootloader configuration.
- **Retention safety:** Prefer matching initramfs images against actually installed `/usr/lib/modules/<version>` trees rather than deleting files solely by age/name. Consider retaining one previous known-good kernel/initramfs if BFSOS adopts that recovery policy.

- **Bootloader neutrality:** Keep the hook structured so a future Limine or other bootloader backend can be selected instead of permanently assuming GRUB.
- **Installer compatibility:** The installer already performs its own final Dracut/GRUB setup after constructing the target storage stack and boot parameters. The kernel package hook must therefore be safe when invoked inside the installer/chroot and must not replace the installer's final authoritative GRUB regeneration.
- **Recommended installer handling:** Either suppress/defer the kernel package bootloader hook during installation (for example with an installer environment flag) or allow the early update and still have the installer regenerate Dracut/GRUB at the end. Prefer suppression/deferment to avoid redundant work and premature configs while storage/LUKS/mdadm/LVM setup is incomplete.
- **Regression tests:**
  - normal installed-system kernel upgrade: Dracut succeeds, then GRUB regenerates;
  - Dracut failure: GRUB is not regenerated;
  - fresh BFSOS installer: kernel installation does not leave a premature/broken GRUB config and the installer's final GRUB generation remains authoritative;
  - system without GRUB: hook exits cleanly without attempting `grub-mkconfig`.

## r89 tracker update — 2026-08-15
- Added #110 for automatic GRUB regeneration after successful Dracut/kernel updates, with explicit installer-safe/deferred behavior.


## r90 tracker update — 2026-08-15
- Expanded #110 to include safe cleanup of obsolete `/boot` initramfs images after successful kernel/Dracut updates and before final GRUB regeneration.


### 111. Retune pkgmk locale policy for bootstrap vs installed BFSOS
- [x] **IMPLEMENTED in pkgutils release 7 and bootstrap r55; runtime regression pending**
- **Area:** `pkgmk`, `ports/core/pkgutils/Pkgfile`, special Stage 1 pkgutils bootstrap
- **Confirmed behavior:** On installed BFSOS, forcing `pkgmk` to `LC_ALL=C` causes GCC 16.2.0 extraction to fail in bsdtar with `Pathname can't be converted from UTF-8 to current locale`.
- **Confirmed manual fix:** The bare-metal system provides `C.utf8`; changing `/usr/bin/pkgmk` to `export LC_ALL=C.utf8` allowed GCC extraction to work.
- **Required distinction:** Early Stage 1 may not have a UTF-8 locale and must remain safe there, while normal installed/final BFSOS needs a UTF-8-capable locale for pkgmk.
- **Target policy:** Detect `C.utf8` or `C.UTF-8` when available and use it; fall back to plain `C` only in bootstrap environments where no UTF-8 C locale exists.
- **Do not regress #107:** Keep the special Stage 1 bootstrap safe before locales are generated, but do not propagate the plain-`C` workaround into final `/usr/bin/pkgmk`.
- **Regression tests:** clean Stage 1 without setlocale warnings; Stage 2 restart/resume; installed pkgmk selects UTF-8; GCC 16.2.0 archive extracts successfully; test both `C.utf8` and `C.UTF-8` spellings where practical.

## r91 tracker update — 2026-08-15
- Added #111 after bare-metal testing proved that plain `LC_ALL=C` is appropriate only as an early-bootstrap fallback, while final installed pkgmk needs an available UTF-8 locale for GCC/libarchive extraction.

### 112. Remove stray `/usr/lib/modules/KERNELVERSION` from kernel package
- [x] **SUPERSEDED by #114; helper removed only after post-install no longer depends on it**
- **Area:** BFSOS kernel Pkgfile/install staging
- **Observed on fresh VM install:** `/usr/lib/modules/KERNELVERSION` is installed as a regular 16-byte file containing `7.1.8-BFS-Linux`, alongside the correct `/usr/lib/modules/7.1.8-BFS-Linux/` module directory.
- **Problem:** `KERNELVERSION` is a build/package helper artifact and should not be installed as a file directly under `/usr/lib/modules`.
- **Required fix:** Find the kernel Pkgfile/install step that stages or copies `KERNELVERSION` into the package and prevent it from entering the final package. Do not disturb the real `/usr/lib/modules/$KERNELVERSION/` directory.
- **Upgrade cleanup:** Consider removing a stale `/usr/lib/modules/KERNELVERSION` left by an older BFSOS kernel package during a subsequent kernel upgrade.
- **Current install:** Leave the file untouched until the current VM has completed its first reboot; it appears harmless and the correct versioned module directory is present.
- **Regression test:** Build/install a fresh kernel package and verify `/usr/lib/modules` contains the expected versioned kernel module directory/directories but no regular `KERNELVERSION` file.

## r92 tracker update — 2026-08-15
- Added #112 for the confirmed stray `/usr/lib/modules/KERNELVERSION` kernel packaging artifact found during the fresh VM pre-reboot inspection.

### 113. Build installer-supported md RAID personalities directly into the BFSOS kernel
- [x] **DIAGNOSIS SUPERSEDED by #115/#116: kernel modules were present; Dracut omission was proven**
- **Area:** `ports/core/linux/Pkgfile` / kernel configuration enforcement
- **Confirmed failure:** Fresh VM install using RAID10 reached Dracut with all six RAID members visible, but `/dev/md0` remained inactive. Manual `mdadm --run /dev/md0` failed with `md: personality for level 10 is not loaded`, and `modprobe raid10` failed because no `raid10` module was available in the initramfs.
- **Root cause:** The BFSOS kernel Pkgfile currently forces md RAID personalities such as RAID0/1/10/456 to modules (`=m`). The installer can place root-critical storage behind md RAID, so relying on Dracut to include/load the correct RAID personality is unsafe.
- **Required change:** Force installer-supported md RAID personalities built-in (`=y`) in the kernel Pkgfile:
  - `CONFIG_MD=y`
  - `CONFIG_BLK_DEV_MD=y`
  - `CONFIG_MD_LINEAR=y`
  - `CONFIG_MD_RAID0=y`
  - `CONFIG_MD_RAID1=y`
  - `CONFIG_MD_RAID10=y`
  - `CONFIG_MD_RAID456=y`
- **Verification:** Update the kernel Pkgfile's post-config checks so RAID0, RAID1, RAID10, and RAID456 are explicitly verified as `=y`, not merely present as modules.
- **Installer implication:** No installer storage-layout logic change is required for this specific failure; the generated mdadm/LUKS/LVM/GRUB configuration was correct. Fix the kernel capability so md arrays can assemble before downstream LUKS/LVM activation.
- **Regression tests:** Rebuild kernel and retest at least RAID1 and RAID10 installs with md-backed LUKS/LVM. Confirm `/dev/md*` arrays become active automatically in early boot and Dracut proceeds to unlock downstream LUKS without a missing RAID-personality error.

### 114. Rework kernel `KERNELVERSION` helper handling instead of treating it as a random artifact
- [x] **IMPLEMENTED in linux release 2 post-install; regression pending**
- **Area:** `ports/core/linux/Pkgfile` / `post-install`
- **New finding:** `/usr/lib/modules/KERNELVERSION` is currently used intentionally by the kernel `post-install` script to communicate the newly installed kernel version.
- **Required revision to #112:** Do not simply remove the file without replacing that communication path.
- **Preferred design:** Pass/derive the installed kernel version in a cleaner way (for example from the package build/install environment, the versioned modules directory, or another explicit post-install argument), then stop installing the helper file in the final filesystem.
- **Cleanup:** Once the post-install logic no longer depends on it, remove stale `/usr/lib/modules/KERNELVERSION` during a future kernel upgrade.
- **Regression test:** Kernel post-install still identifies the correct kernel version, runs its Dracut/bootloader work against that version, and the final installed filesystem contains no helper `KERNELVERSION` file.

## r93 tracker update — 2026-08-15
- Added #113 for the confirmed RAID10 early-boot failure caused by md RAID personalities being modular instead of built-in.
- Added #114 to revise the earlier `KERNELVERSION` cleanup item now that the helper file's actual post-install purpose is known.

### 115. Force md RAID personality drivers into initramfs during installer Dracut generation
- [x] **IMPLEMENTED in installer r43; RAID matrix regression pending**
- **Area:** BFSOS installer final Dracut generation
- **Confirmed evidence:** The installed BFSOS kernel contains `raid0.ko`, `raid1.ko`, `raid10.ko`, and `raid456.ko`, but the failed initramfs contained only the mdraid framework, `mdadm`, hooks, and `mdadm.conf`; the RAID personality modules themselves were absent.
- **Manual proof:** Rebuilding the VM initramfs with `dracut --force --add-drivers "raid10"` immediately placed `raid10.ko` into the initramfs.
- **Required installer fix:** When the installer performs the final Dracut build for an installed system using md RAID, explicitly include the supported md RAID personality modules rather than relying solely on host-only auto-detection.
- **Supported driver set:** `linear raid0 raid1 raid10 raid456`.
- **Preferred command behavior:** Use Dracut's explicit driver inclusion mechanism (`--force-drivers` preferred if compatible with the shipped Dracut version; otherwise `--add-drivers`) so the required RAID personalities are guaranteed to exist in the initramfs.
- **Do not remove existing metadata:** Preserve the installer's explicit `rd.md.uuid`, LUKS UUID, and LVM kernel arguments and the generated `/etc/mdadm.conf`.
- **Regression tests:** Fresh installs using RAID0, RAID1, RAID10, RAID5, and RAID6 should boot with the md array active before downstream LUKS/LVM activation.

### 116. Force md RAID personality drivers into initramfs on kernel upgrades
- [x] **IMPLEMENTED in linux release 2 post-install; kernel-upgrade RAID regression pending**
- **Area:** `ports/core/linux/post-install` / kernel upgrade initramfs generation
- **Reason:** Fixing only the installer is insufficient. A later kernel upgrade can regenerate an initramfs without the md RAID personality modules and make an already-working BFSOS installation unbootable; this appears to match the bare-metal regression observed after the kernel update.
- **Required kernel-port fix:** Whenever the kernel post-install hook invokes Dracut, explicitly include `linear raid0 raid1 raid10 raid456` in the newly generated initramfs.
- **Ordering:** Install kernel/modules -> generate initramfs with forced md RAID drivers -> verify success -> clean obsolete initramfs images as defined in #110 -> regenerate GRUB.
- **Failure safety:** If Dracut fails or the required RAID modules are absent from the resulting initramfs, do not proceed as though the kernel update completed successfully and do not regenerate GRUB to a broken boot state.
- **Verification:** After Dracut, inspect the generated image (for example with `lsinitrd`) and confirm the expected md RAID module files are present before finalizing the kernel update.
- **Regression tests:** Upgrade the kernel on systems using RAID1, RAID10, and RAID5/6 and confirm the arrays assemble during early boot without manual intervention.

### 117. Consider central BFSOS Dracut storage policy to avoid duplicated RAID-driver logic
- [x] **IMPLEMENTED as distribution Dracut policy plus explicit safeguards; regression pending**
- **Area:** Dracut configuration
- **Preferred long-term design:** Add a BFSOS-managed Dracut config such as `/etc/dracut.conf.d/bfsos-storage.conf` that guarantees `linear raid0 raid1 raid10 raid456` are included/forced whenever Dracut builds an initramfs.
- **Benefit:** Installer Dracut runs, kernel post-install Dracut runs, and manual administrator Dracut rebuilds all inherit the same safe md RAID policy automatically.
- **Compatibility requirement:** Verify the exact `dracut.conf` syntax supported by the BFSOS-shipped Dracut version before implementing this as the single source of truth.
- **Transition:** Until the centralized config is implemented and proven, keep the explicit safeguards in both the installer and kernel post-install paths.

### Tracker correction to #113
- **Revised diagnosis:** Do **not** switch the md RAID personalities to built-in solely to fix this failure.
- The kernel package already contains the RAID personality modules. The failure was caused by Dracut omitting them from the initramfs.
- Keep RAID personalities modular unless there is another independent reason to build them in.
- Supersede #113's proposed built-in-kernel fix with #115 and #116, while retaining #113 as the historical root-cause investigation record.

## r94 tracker update — 2026-08-15
- Added #115 for forcing md RAID personality modules into installer-generated initramfs images.
- Added #116 for doing the same in the kernel port's post-install Dracut path so kernel upgrades cannot silently break RAID boot.
- Added #117 for a centralized BFSOS Dracut storage-policy file as the preferred long-term design.
- Corrected #113 now that testing proved the kernel contains the RAID modules and Dracut was the component that omitted them.



### Tracker refinement — JBOD/md linear coverage
- **#115 / #116 / #117:** Include the md `linear` personality alongside the RAID personalities because BFSOS supports/needs to remain safe for JBOD-style md linear arrays.
- **Required md driver set:** `linear raid0 raid1 raid10 raid456`.
- **Regression coverage:** Add an md linear/JBOD installer and kernel-upgrade boot test to the RAID regression matrix.

## r95 tracker update — 2026-08-15
- Expanded the Dracut md-driver fixes to include `linear` for JBOD/md-linear configurations.


## r96 consolidated implementation pass — 2026-08-15

This pass applies the currently actionable tracker fixes across the full uploaded BFSOS project. Items that require hardware/runtime/destructive regression testing or are explicitly post-1.0 roadmap work remain open as tests/roadmap rather than being falsely marked complete.

### Bootstrap r55
- Stage 1/2/3 package failures preserve the parent menu flow; active package logs are closed with the real failure status before returning.
- The initial direct pkgutils bootstrap no longer hard-codes a locale. Generated `pkgmk` dynamically selects `C.UTF-8` or `C.utf8` when available and falls back to `C` when neither exists.
- Stage 1 bootstrap patch sources are now applied automatically by `files/pkgmk.bootstrap` before `bootstrap_build()`, respecting `source=()`, `renames=()`, `skip_patch`, and `patch_opt`.
- Glibc no longer manually double-applies bootstrap patches; its source list orders the FHS patch before the Glibc 2.44 upstream-fix patch. Both supplied patch MD5 sums were verified against tracker #100.
- Stage 1 and Stage 5 compression/status output uses the Dialog UI when launched from the interactive menu while preserving text output for direct/text-mode operation.
- Interactive sudo/root transition chatter is suppressed in Dialog mode but preserved for direct/text invocation.
- Removed obsolete `scripts/bootstrap.sh` and `files/bootstrap-with-systemd-fixes.sh`; root `bootstrap.sh` is authoritative.

### pkgutils release 7
- Final installed `pkgmk` dynamically selects `C.UTF-8`/`C.utf8` when available, fixing GCC/libarchive UTF-8 pathname extraction while retaining a plain-C fallback for minimal bootstrap environments.
- `pkgadd.conf` retains normal `/etc` protection but explicitly replaces BFSOS-managed `/etc/pkgmk.conf`, `/etc/pkgadd.conf`, `/etc/os-release`, `/etc/bfs-release`, `/etc/lfs-release`, and `/etc/issue`.

### Linux release 2 / Dracut / GRUB
- Added `/usr/lib/dracut/dracut.conf.d/50-bfsos-storage.conf` with `force_drivers+=" linear raid0 raid1 raid10 raid456 "` so normal/manual Dracut runs inherit the BFSOS md policy.
- Kernel post-install independently uses `--force-drivers "linear raid0 raid1 raid10 raid456"`, verifies the resulting initramfs contains each module, and refuses to finalize a broken image.
- Kernel post-install now derives the new kernel release from the installed `/boot/vmlinuz-*-BFS-Linux` image and no longer requires `/lib/modules/KERNELVERSION`; stale helper files are cleaned after successful processing.
- During installer package transactions, `BFS_INSTALLER_RUNNING=yes` defers kernel post-install Dracut/GRUB work to the installer's final topology-aware pass.
- Normal kernel upgrades regenerate GRUB only after Dracut succeeds, clean initramfs images only when the matching `/lib/modules/<version>` tree is gone, and protect both the new and currently running kernel image.

### Installer r43
- Final Dracut generation explicitly forces `linear raid0 raid1 raid10 raid456` for md-backed installations and verifies all five drivers are present with `lsinitrd`.
- The generated topology-specific Dracut config also records the forced md driver set in addition to required Dracut modules (`mdraid`, `crypt`, `lvm`, `usrmount` as applicable).
- Added explicit retry checkpoints. The base archive is not re-extracted after a package/configuration failure; filesystem actions are changed to `keep`; package transactions rerun `ports -u` until `packages_complete`; configured account passwords are not needlessly re-prompted after their checkpoint; system/bootloader checkpoints are recorded under `/var/lib/bfs-installer`.
- A package failure therefore returns to the installer UI with the mounted target/log intact and a retry resumes against the existing target rather than recreating storage/base contents.

### Documentation / static validation
- Replaced the obsolete BFS-Linux README with a BFSOS-focused 1.0-RC document covering architecture, bootstrap stages, package management, installer/storage capabilities, logs, limitations, and support location.
- Root bootstrap, installer r43, kernel post-install, bootstrap pkgmk extension, and all core Pkgfiles pass `bash -n` in this static pass.
- No stale pkgutils 5.40.10 or old base-package `python` references remain in the active bootstrap/scripts tree after obsolete bootstrap removal.

### Remaining validation/roadmap work
- Runtime tests still required: deliberate Stage 1/package failure, installer failed-download/resume, clean Stage 1/2/3 locale behavior, Stage 5 Dialog behavior, kernel-upgrade GRUB/initramfs cleanup, md linear/RAID0/1/10/5/6 cold boots, alternate display connectors, arbitrary VG/LV names, and remaining hardware-specific items already identified in the tracker.
- #28 full declarative recreation of RAID/LUKS/LVM profiles and #96 LTS kernel flavor remain intentional larger roadmap items rather than being silently implemented as part of this RC bug-fix pass.


### 118. Remove redundant terminal success/Enter prompt after Dialog Continue
- [x] **IMPLEMENTED in r101; runtime UI regression pending**
- **Observed during fresh r96 Stage 1 test:** After the success Dialog is acknowledged with **Continue**, Bootstrap drops to the terminal and prints `Operation completed successfully.` followed by `Press Enter to return to the menu...`.
- **Required behavior:** The Dialog **Continue** action should return directly to the main Bootstrap menu with no second success message and no additional Enter keypress.
- **Scope:** Audit successful Bootstrap stage/menu operations for the same redundant acknowledgement.
- **Failure paths:** Keep useful failure/error acknowledgement; this change applies to successful operations already acknowledged through Dialog.
- **Regression test:** Complete each Bootstrap menu operation and confirm there is exactly one acknowledgement before returning to the main menu.

## r97 tracker update — 2026-08-15
- Added #118 for the redundant post-success terminal Enter prompt.


### 119. Base archive must not default to an ungenerated `en_US.UTF-8` locale
- [x] **IMPLEMENTED in r101; fresh-base Stage 8 regression pending**
- **Observed during fresh r96 Stage 8 chroot test:** Entering the BFS chroot prints `locale: Cannot set LC_CTYPE`, `LC_MESSAGES`, and `LC_ALL` warnings.
- **Confirmed base locales:** `locale -a` contains only `C` and `POSIX`.
- **Stage 8 invocation is already correct:** `_enter_bfs_chroot()` uses `env -i` with `LANG=C`, `LC_ALL=C`, and `LANGUAGE=C`.
- **Root cause:** The login shell subsequently reads the BFSOS profile/locale configuration and changes `LANG` to `en_US.UTF-8` even though that locale has not been generated in the bootstrap base.
- **Required base behavior:** The bootstrap/base archive must default to a locale guaranteed to exist, preferably `LANG=C`.
- **aaa_filesystem fix:** Do not ship an active `en_US.UTF-8` default in `/etc/locale.conf` before that locale exists. Ship a safe base default such as `LANG=C`.
- **Installer responsibility:** After generating the user-selected locale, the installer should write the selected locale to `/etc/locale.conf` (for example `LANG=en_US.UTF-8`).
- **Do not change:** Keep `_enter_bfs_chroot()`'s clean `env -i` locale handling; testing proved that path is already correct.
- **Regression tests:** Stage 8 must enter without locale warnings from a freshly built base; after installation, the configured UTF-8 locale must exist in `locale -a` and be active for a normal login shell.

## r98 tracker update — 2026-08-15
- Added #119 for the Stage 8 locale warnings caused by the base system selecting `en_US.UTF-8` before that locale has been generated.


### 120. Move ZRAM into Partitioning/Storage as an explicit optional feature with size selection
- [x] **IMPLEMENTED in installer r44; install/reboot regression pending**
- **Area:** installer Partitioning/Storage menu / ZRAM configuration
- **Goal:** Treat ZRAM as a storage/memory configuration choice rather than an implicit/default behavior.
- **Required UI:** Add a ZRAM option under the Partitioning/Storage menu with:
  - `Enable ZRAM` / `Disable ZRAM`
  - a configurable ZRAM size when enabled
- **Size selection:** Allow the user to choose a size explicitly rather than hardcoding it. Provide sensible presets plus a custom-size entry.
- **Suggested presets:** percentage-of-RAM choices (for example 50%, 100%, 150%, 200%) and/or fixed sizes where useful.
- **Default behavior:** Do not silently enable ZRAM if the user has not selected it.
- **Persistence:** Store the selected ZRAM state/size in the installer configuration and write the appropriate installed-system configuration so the setting persists across reboots.
- **Review screen:** Show whether ZRAM is enabled and the selected size in the final installation review.
- **Profile support:** Include non-secret ZRAM settings in saved installer configuration profiles.
- **Validation:** Reject invalid/zero/negative sizes and clearly warn about unreasonable values.
- **Regression tests:** Install once with ZRAM disabled, once with a normal preset, and once with a custom size; verify the installed system matches the selected setting after reboot.

## r99 tracker update — 2026-08-15
- Added #120 to make ZRAM an explicit enable/disable option under Partitioning/Storage with user-selectable sizing and persistent installer configuration.

### 121. Add Linux 6.12 LTS kernel option with Debian patches and broad hardware support
- [x] **INITIAL IMPLEMENTATION in r101; kernel build/boot regression pending**
- Track Linux 6.12.y LTS using the current Debian stable/security source package. The r101 implementation uses Debian `linux-source-6.12` 6.12.101-1 (security), including its Debian patch series.
- Apply the applicable Debian 6.12 kernel patch series, while keeping BFSOS-specific patches/configuration separate and auditable.
- Configure broad practical x86_64 support: storage, filesystems, networking, virtualization, USB, input, DRM/graphics, sound, crypto, md RAID, device mapper and other generally useful hardware/features. Prefer modules for non-boot-critical hardware; do not enable incompatible, architecture-specific, or inappropriate debug options merely to claim every CONFIG option.
- Guarantee BFSOS md support for linear, raid0, raid1, raid10 and raid456 and compatibility with the centralized Dracut force-driver policy.
- Use the same BFSOS kernel lifecycle hooks for depmod, Dracut, GRUB regeneration, stable initramfs handling and obsolete-initramfs cleanup.
- Allow coexistence with the normal/current BFSOS kernel where practical so 6.12 LTS can serve as a conservative/fallback kernel.
- Add it to the installer kernel-selection menu.
- Suggested installer label: `Linux 6.12 LTS (Debian patches, broad hardware support included)`.
- Show the selected kernel flavor/version on the final review screen.
- Regression-test fresh boot and kernel upgrades on plain storage and md RAID/LUKS/LVM/Btrfs.

## r100 tracker update — 2026-08-15
- Added #121 for a latest-6.12 LTS kernel flavor with Debian patches, broad practical hardware support, and clearer installer kernel-selection wording.


### 122. Prevent RAID creation from aborting when selected members are already owned by an active storage layer
- [x] **IMPLEMENTED in installer r44; runtime regression pending**
- **Observed:** A previous RAID10 auto-assembled as `/dev/md127`, leaving `/dev/vdb1` busy. `mdadm --create` then failed and the installer's global ERR path terminated the install.
- **Fix:** Before `mdadm --create`, inspect each selected member for mounts and sysfs holders. If a selected partition is held by an active md/dm device, show a Dialog explanation and return to the RAID workflow without creating anything.
- **Failure containment:** `mdadm --create` itself now runs in a handled conditional; a normal creation error displays a RAID failure Dialog instead of escaping through the global fatal trap.
- **Regression test:** Boot a live environment that auto-assembles an old array as `/dev/md127`, select one of its members for a new array, and verify the installer refuses safely and stays in its UI.

## r101 implementation / core LFS-development refresh — 2026-08-15
- Implemented #118 by returning Stage 1 directly to the Bootstrap menu after its own success Dialog, matching the already-clean Stage 2-5 success paths.
- Implemented #119: the base `aaa_filesystem` now ships `LANG=C`; the installer continues to generate the selected locale first and then writes the installed system's `/etc/locale.conf`.
- Implemented #120 in installer r44: ZRAM is disabled unless explicitly enabled under Storage, with 50/100/150/200 percent presets and custom fixed-size input; selection is persisted in profiles and shown in review.
- Implemented #121 as new `ports/core/linux-lts`: Debian-patched Linux 6.12.101, broad x86_64 `allmodconfig` baseline with BFSOS boot/storage requirements, shared Dracut md policy, kernel post-install handling, and installer selection wording.
- Implemented #122 for busy/held RAID-member preflight and handled mdadm create failures.
- Updated all BFSOS core ports that correspond to the current LFS development package list to the current LFS-listed versions. Corrected misleading Bash/Readline package versions to 5.3/8.3 because those ports download the unpatched base tarballs rather than the previously claimed 5.3.15/8.3.1 patch levels.
- Updated current LFS-required patch references for Bzip2, Coreutils, Expect, Glibc, Kbd, Python 3.14.7/OpenSSL 4, SysVinit, and Tar; locally carried patch files were checksum-audited where present.
- Refreshed LFS-derived source URLs to the current development-book canonical upstream locations where applicable. Project-specific/non-LFS core packages were not version-bumped merely because they live in `core`; they require their own upstream/BLFS audit rather than guessing from LFS.
- Fresh r96/r99 runtime evidence already proved the centralized Dracut policy contains `linear raid0 raid1 raid10 raid456` and successfully cold-booted a combined RAID1 + RAID0 -> LUKS -> LVM -> Btrfs installation. Kernel-upgrade regeneration still requires a separate regression test.
- Static validation: root bootstrap, installer r44, Linux/current and Linux-LTS Pkgfiles/post-install scripts, and every `ports/core/*/Pkgfile` pass `bash -n` in this pass.


### r101 Dracut policy ownership refinement
- The fixed `linear raid0 raid1 raid10 raid456` policy is now owned by the `dracut` port at `/usr/lib/dracut/dracut.conf.d/40-bfsos-md-drivers.conf`, rather than by either kernel package. This avoids file-ownership conflicts when `linux` and `linux-lts` coexist and allows package upgrades to replace the distribution policy normally.
- The installer keeps topology-specific Dracut requirements in `/etc/dracut.conf.d/20-bfs-storage.conf`; it no longer competes with the distribution-wide fixed policy file.
- `dracut` release is bumped to 3 and the normal `linux` port to release 3 for the ownership transition.
- The LFS-Bootscripts BFSOS UEFI patch was rebased to the current 20250827 `mountvirtfs` layout instead of retaining the stale 2019 hunk context.


### 122. Audit every remaining non-LFS package in `ports/core`
- [ ] **OPEN — complete core collection audit**
- **Scope:** Audit every package remaining in `ports/core` that was not covered by the LFS development-book alignment pass.
- **Classification:** For each port, identify whether its authoritative maintenance reference should be BLFS development, another appropriate LFS-family book, the upstream project, or BFSOS-specific policy.
- **For every retained port:** Verify current stable/appropriate version, canonical source URL, backup URL where useful, checksums/source naming, patches, dependencies, configure/build/install instructions, and whether it still belongs in `core`.
- **Security/maintenance:** Prefer actively maintained upstream releases and identify abandoned or superseded software.
- **Duplicates/legacy:** Flag duplicate, superseded, compatibility-only, or no-longer-used ports for removal or relocation rather than updating them blindly.
- **Deliverable:** Produce an audit table/report covering every non-LFS `core` port with disposition: KEEP/UPDATE, MOVE, REPLACE, or DELETE.
- **Regression:** After changes, run source-download validation and build/static checks, followed by a clean bootstrap/install regression for packages that affect the base system.

### 123. Removal audit / chop block for obsolete init and initramfs infrastructure
- [ ] **OPEN — candidate deletion set; verify dependencies before removing**
- **Candidates requested for deletion:**
  - `lfs-bootscripts`
  - `sysvinit`
  - `runit`
  - `runit-rc`
  - `mkinitcpio`
  - `mkinitramfs`
- **Rationale:** BFSOS is systemd-based and uses Dracut for initramfs generation, so parallel SysV/runit boot infrastructure and alternate initramfs generators appear redundant.
- **UEFI note:** Current BFSOS boot testing confirms `efivarfs` is already mounted and populated on the systemd boot path, so the old BFSOS LFS-Bootscripts UEFI/efivarfs patch should not be retained merely for UEFI variable access.
- **Safety requirement:** Before deletion, grep the complete project for package dependencies, bootstrap ordering, installer calls, scripts, documentation, package groups, and generated configuration that still reference any candidate.
- **Required cleanup:** Remove dependent references, obsolete patches/files, package-list entries, bootstrap/install logic, and documentation together with any package that is confirmed unused.
- **Do not remove blindly:** If a candidate still provides a required utility or compatibility interface, document that dependency and either replace it with the systemd/Dracut equivalent or retain the minimal required component until the dependency is removed.
- **Regression:** Clean bootstrap, fresh install, Dracut generation, UEFI boot, reboot/shutdown, rescue/recovery path, and kernel-update tests after removal.

## r102 tracker update — 2026-08-15
- Added #122 for a complete audit of all remaining non-LFS `ports/core` packages.
- Added #123 placing `lfs-bootscripts`, `sysvinit`, `runit`, `runit-rc`, `mkinitcpio`, and `mkinitramfs` on the removal/chop-block list, subject to a full dependency/reference audit before deletion.


### 124. Keep the normal/current BFSOS kernel as the default when the LTS compatibility kernel is installed
- [ ] **OPEN — dual-kernel policy / packaging / installer**
- **Default kernel:** The normal/current non-LTS BFSOS kernel remains the default kernel for installation, GRUB boot selection, normal updates, and development.
- **LTS role:** The Linux 6.12 LTS flavor is an optional compatibility/fallback kernel intended for broader x86_64 driver/hardware coverage and recovery from regressions or missing support in the current kernel; installing it must not silently make it the default.
- **`/usr/src/linux` policy:** `/usr/src/linux` must point to the normal/current non-LTS BFSOS kernel source tree. Installing or upgrading `linux-lts` must not take ownership of or replace this symlink.
- **Per-kernel build links:** Each installed kernel must retain its own `/usr/lib/modules/<kernel-release>/build` (and `source` where applicable) link to the correct matching source/build tree so external modules can target either kernel independently.
- **GRUB:** Generate entries for both kernels when both are installed, while keeping the normal/current BFSOS kernel as the default boot choice unless the user explicitly changes GRUB configuration.
- **Coexistence:** Kernel images, initramfs files, module trees, source trees, package ownership, and update hooks must remain version/flavor-specific so `linux` and `linux-lts` can be installed and upgraded side by side.
- **Regression test:** Install the normal kernel plus `linux-lts`; verify `/usr/src/linux` still targets the normal kernel, both module `build` links resolve correctly, both initramfs/kernel pairs exist, GRUB contains both, the normal kernel remains default, and both can boot.

## r103 tracker update — 2026-08-15
- Added #124 defining the dual-kernel policy: the normal/current non-LTS BFSOS kernel remains the default and owns `/usr/src/linux`; the 6.12 LTS kernel remains an optional compatibility/fallback kernel and must coexist without stealing the default symlink or boot selection.


### 125. Add installer hardware inventory and live-environment driver comparison
- [ ] **POST-1.0 / target 1.1 — installer/default-kernel compatibility audit**
- **Goal:** Use the successfully booted live environment as a hardware/driver reference and compare the detected requirements with the normal BFSOS kernel before the first reboot.
- **Inventory:** During installation collect useful hardware information including PCI devices/drivers, USB devices, CPU/platform information, block/storage controllers, networking, graphics, audio, and other relevant hardware.
- **Bound-driver reference:** Record the kernel drivers actually bound to hardware in the live environment (for example `lspci -nnk` / `lspci -k` driver-in-use information), rather than treating the live kernel's entire configuration as the desired BFSOS configuration.
- **BFSOS comparison:** Check whether each relevant live-environment driver is available built-in or as a module in the selected normal BFSOS kernel.
- **Severity classification:** Classify missing support at least as:
  - **BOOT-CRITICAL** — required to reach/root-mount the installed BFSOS system.
  - **IMPORTANT** — important machine functionality such as primary networking/graphics/input.
  - **OPTIONAL** — nonessential peripherals/features.
- **Boot-critical validation:** For modular storage/controller/filesystem support required before root is mounted, also verify that Dracut includes the necessary module/support in the generated initramfs.
- **Installer behavior:** Do not abort an otherwise valid install merely because an optional peripheral driver is missing. Give a prominent pre-reboot warning for boot-critical/important missing support.
- **LTS fallback:** If the normal/current kernel lacks required hardware support but the broad 6.12 LTS compatibility kernel provides it, recommend/install the LTS flavor as an additional fallback without changing the normal kernel's default status unless the user explicitly requests that.
- **Reports:** Preserve the results in the installed system, e.g.:
  - `/var/log/bfsos/hardware-report.txt`
  - `/var/log/bfsos/kernel-driver-audit.txt`
- **Kernel-maintenance feedback:** Repeatedly discovered legitimate x86_64 hardware drivers missing from the normal kernel should be evaluated for permanent inclusion in the normal BFSOS kernel config.
- **Do not generate per-machine kernels:** Keep reproducible BFSOS kernel packages/configurations; hardware detection is an audit/safety mechanism, not a reason to compile a unique kernel for every installation.
- **Regression tests:** Exercise on VM and multiple bare-metal systems and intentionally test at least one missing-module case to verify warning/severity/report behavior.

### 126. Broaden the normal/default BFSOS kernel's x86/x86_64 network support
- [ ] **OPEN — normal kernel configuration policy**
- **Policy:** If a practical network driver/support option is valid for x86/x86_64 and does not introduce a known conflict or unacceptable maintenance/security problem, enable it in the normal BFSOS kernel, generally as a module.
- **Coverage goal:** Broad support for x86/x86_64:
  - PCI/PCIe Ethernet adapters
  - USB Ethernet adapters
  - Wi-Fi adapters/chipsets
  - `cfg80211` / `mac80211` and required wireless infrastructure
  - Bluetooth and relevant networking/support stacks
  - common firmware/PHY/MDIO dependencies required by supported adapters
- **Default kernel:** This broad network coverage belongs in the normal/current BFSOS kernel, not only in the LTS compatibility kernel.
- **Module policy:** Prefer modules for hardware-specific drivers unless a component is genuinely required built-in for reliable boot/platform operation.
- **Architecture scope:** This requirement concerns drivers/support applicable to x86/x86_64. Do not enable unrelated ARM/RISC-V/other-architecture hardware merely to maximize CONFIG counts.
- **Validation:** Audit the current normal-kernel `.config` against the x86/x86_64 network-driver menus and test representative wired, wireless, USB-network and Bluetooth hardware where available.

### 127. Broaden the normal/default BFSOS kernel's x86/x86_64 sound and platform/SoC support
- [ ] **OPEN — normal kernel configuration policy**
- **Policy:** Enable essentially all practical sound/audio and relevant platform/SoC support that is valid for x86/x86_64 and can safely coexist, generally as modules.
- **Audio coverage goal:** Include broad x86/x86_64 support for:
  - ALSA core and normal PCI/PCIe audio drivers
  - Intel/AMD HDA and related codecs
  - USB audio
  - SOF (Sound Open Firmware)
  - SoundWire
  - relevant Intel/AMD x86 audio/platform drivers
  - applicable x86 SoC audio drivers/codecs/machine drivers
  - other practical x86/x86_64 sound hardware support
- **x86 platform/SoC scope:** Enable relevant x86/x86_64 SoC/platform-device support where useful and safe; this does **not** mean enabling ARM, RISC-V, PowerPC, or other architecture-specific SoC drivers.
- **Default kernel:** This broad audio/platform coverage belongs in the normal/current BFSOS kernel as standard compatibility coverage; the LTS kernel remains the still-broader fallback.
- **Module policy:** Prefer modules for hardware-specific drivers unless built-in support is justified.
- **Validation:** Audit the normal kernel `.config` against x86/x86_64 sound, SOF, SoundWire, codec, and platform/SoC menus; build-test for dependency/config conflicts and test representative audio hardware where available.

### 128. Define normal-kernel compatibility policy versus the LTS fallback
- [ ] **OPEN — kernel policy/documentation**
- **Normal/current kernel:** Remains the default BFSOS kernel and should itself have deliberately broad practical x86_64 hardware support, especially network and sound.
- **Hardware audit:** Installer hardware comparison (#125) acts as a safety net for hardware categories that the normal kernel may still miss.
- **LTS compatibility kernel:** Remains an optional broad-driver fallback/rescue kernel for unusual hardware or regressions; it is not a substitute for fixing repeatedly observed omissions in the normal kernel.
- **Promotion rule:** When real hardware testing repeatedly identifies a safe/useful x86_64 driver absent from the normal kernel, evaluate enabling it permanently in the normal kernel configuration.
- **Reproducibility:** Maintain version-controlled normal and LTS kernel configs rather than dynamically altering kernel configuration per installation.

## r104 tracker update — 2026-08-15
- Added #125 for live-environment hardware inventory, bound-driver comparison against the normal BFSOS kernel, severity-based missing-driver warnings, Dracut boot-driver validation, and persistent hardware/kernel audit reports.
- Added #126 requiring broad practical x86/x86_64 Ethernet, Wi-Fi, Bluetooth, USB-network and supporting network-driver coverage in the normal/default kernel.
- Added #127 requiring broad practical x86/x86_64 sound plus applicable x86 SoC/platform audio support in the normal/default kernel.
- Added #128 documenting the intended relationship between the broad normal kernel, hardware-detection safety net, and still-broader optional LTS compatibility/fallback kernel.


### 129. Broaden normal/default BFSOS kernel USB webcam and camera support
- [ ] **OPEN — normal kernel configuration policy**
- **Policy:** Enable broad practical USB webcam/camera support applicable to x86/x86_64 systems in the normal/current BFSOS kernel so common cameras work out of the box without requiring the LTS fallback kernel.
- **Core media support:** Ensure the required Linux media/V4L2 infrastructure is enabled.
- **UVC:** Enable USB Video Class (UVC) support, primarily as modules where appropriate, because it covers the large majority of standards-compliant USB webcams and many integrated laptop cameras.
- **Additional cameras:** Enable practical non-UVC USB webcam/camera drivers that are valid on x86/x86_64 and can safely coexist.
- **Dependencies:** Include the required media-controller, videobuf, USB/media and relevant sensor/bridge dependencies needed by enabled webcam drivers.
- **Integrated cameras:** Include applicable x86 laptop/integrated-camera support where it is part of the Linux media stack and safe for a generic BFSOS kernel.
- **Module policy:** Prefer modules for individual camera/bridge/sensor drivers rather than building all webcam hardware support directly into the kernel image.
- **Architecture scope:** Do not enable unrelated architecture-specific camera/SoC drivers merely to maximize CONFIG counts.
- **Hardware audit integration:** Installer hardware-driver auditing (#125) should report detected camera devices/drivers and flag missing support as optional/important as appropriate, without blocking installation solely because a webcam is unsupported.
- **Validation:** Audit the normal kernel config against applicable x86/x86_64 USB/media/webcam driver menus; build-test configuration dependencies and test representative UVC and non-UVC cameras where hardware is available.

## r105 tracker update — 2026-08-15
- Added #129 requiring broad practical USB webcam/camera support in the normal/default BFSOS kernel, including UVC/V4L2/media infrastructure and applicable non-UVC x86/x86_64 camera drivers, primarily as modules.


### 130. Add a dedicated unprivileged `pkgmk` build user / privilege separation
- [ ] **OPEN — package-build safety / pkgutils hardening**
- **Goal:** Follow the CRUX-style safety principle that package builds should not run arbitrary Pkgfile build commands as root whenever root privileges are unnecessary.
- **Dedicated account:** Add a dedicated system build account (for example `pkgmk`) and, if useful, a matching group for package-building work.
- **Privilege separation:** Run normal `pkgmk` source extraction, patching, configure, compile, staging, and package creation as the dedicated unprivileged build user.
- **Root-only actions:** Reserve root privileges for operations that genuinely require them, such as installing completed packages into `/`, package database updates, ownership/permission operations that cannot be staged safely, and explicitly audited exceptional hooks.
- **Build directories:** Ensure `/var/cache/pkg/sources`, `/var/cache/pkg/packages`, and `/var/cache/pkg/build-work` have ownership/permissions appropriate for the dedicated build account without making them unnecessarily world-writable.
- **Source cache:** Downloads and cached source archives should be writable by the build account while remaining protected against unrelated users modifying trusted build inputs.
- **Package staging:** `$PKG`/DESTDIR staging must remain fully usable by the unprivileged build user; package metadata and final archive ownership should be deterministic.
- **Pkgfile safety:** A malicious or broken Pkgfile must not be able to overwrite arbitrary host-system files merely because `pkgmk` was invoked by root. Audit environment variables and helper functions for paths that could escape the build/staging roots.
- **Bootstrap consideration:** Early bootstrap stages may need a special controlled path before the final BFSOS user database exists. Do not break Stage 1/temporary-toolchain builds; create/use an equivalent non-root build identity where practical, or document the minimum bootstrap exception.
- **Installer/chroot consideration:** Package builds performed during installation or inside the target chroot should use the same dedicated build-user model once the account exists.
- **Compatibility:** Preserve existing `prt-get`/`pkgmk` workflows. If `prt-get` is run as root, it should delegate the build phase to the unprivileged account and only elevate for the install phase.
- **Failure handling:** Privilege transitions must preserve package logs and the existing Bootstrap/installer failure dialogs.
- **Migration:** Audit current package caches/build-work ownership and provide a one-time safe ownership correction for existing BFSOS installations.
- **Regression tests:** Build representative simple, patched, Python, toolchain, kernel, and large packages; verify builds succeed as the dedicated user, packages install correctly, cache ownership remains sane, and a deliberately hostile test Pkgfile cannot write outside permitted build/staging paths.

## r106 tracker update — 2026-08-15
- Added #130 for a dedicated unprivileged `pkgmk` build account and root/build privilege separation so package builds cannot trash the installed system if a Pkgfile is broken or malicious.


### 131. Enable `ccache` by default for normal BFSOS package builds
- [ ] **OPEN — pkgmk/build performance**
- **Goal:** Make `ccache` the default compiler-cache path for normal BFSOS source package builds to accelerate rebuilds and repeated `prt-get sysup`/development work.
- **Default:** Install/configure `ccache` as part of the normal build environment and enable it by default in `pkgmk`.
- **Compiler coverage:** Route supported C/C++ compiler invocations through `ccache` without changing package semantics or hiding the real compiler version from configure/build systems.
- **Dedicated build user integration:** The dedicated `pkgmk` account from #130 should own/use the package-build cache rather than sharing an unsafe root-owned cache.
- **Cache location:** Use a persistent BFSOS package-build cache location with sane ownership and permissions; do not put the cache inside ephemeral per-package build directories.
- **Configuration:** Provide sensible BFSOS defaults for cache size and behavior while allowing administrators to disable `ccache`, change its size/location, or clear the cache.
- **Bootstrap:** Evaluate Stage 1/2/3 separately. Do not enable `ccache` in sensitive temporary/final toolchain bootstrap phases until reproducibility and compiler-path behavior are proven. Normal post-bootstrap package builds should default to enabled.
- **Kernel builds:** Allow normal and LTS kernel builds to benefit from `ccache` where supported, while preserving reproducible kernel configuration/versioning.
- **Fallback:** If `ccache` is unavailable or explicitly disabled, `pkgmk` must transparently use the real compiler and continue normally.
- **Logging:** Make it visible in package/build logs when `ccache` is active; optionally expose `ccache -s` statistics through a maintenance/status command.
- **Regression tests:** Rebuild representative C/C++, Meson/CMake, kernel, and large packages twice and verify cache hits increase on the second build while produced packages remain valid.

## r107 tracker update — 2026-08-15
- Added #131 to install/configure `ccache` and enable it by default for normal BFSOS `pkgmk` builds, integrated with the planned dedicated unprivileged build account.
- Bootstrap toolchain stages remain opt-in/pending validation so compiler caching does not compromise bootstrap correctness or reproducibility.


### 132. Add compiler/build settings menus to both Bootstrap and Installer
- [ ] **OPEN — build configuration UI / pkgmk integration**
- **Goal:** Add a dedicated **Compiler / Build Settings** menu to both `bootstrap.sh` and the BFSOS installer so users can configure parallel build jobs, compiler optimization policy, CPU-specific tuning, and related pkgmk behavior without manually editing configuration files.
- **Bootstrap menu:** Add a settings entry before build stages are started. The chosen settings should be used by applicable Bootstrap package builds and carried into the generated/final BFSOS `pkgmk.conf` where appropriate.
- **Installer menu:** Add a matching settings section that controls the installed system's normal package-build configuration and writes the selected non-secret settings into the target `/etc/pkgmk.conf`.
- **Settings to expose initially:**
  - build job count (`-jN`);
  - automatic job-count detection;
  - compiler optimization/tuning profile;
  - optional CPU-specific tuning based on detected x86/x86_64 CPU capabilities;
  - `ccache` enable/disable and size where #131 is implemented;
  - ability to restore BFSOS safe defaults.
- **Review:** Show the selected compiler/build settings in Bootstrap/Installer review/status screens before they are committed.
- **Persistence:** Settings selected for the installed system must survive reboot and future `pkgmk`/`prt-get` builds through `/etc/pkgmk.conf`.
- **Text fallback:** Provide equivalent text-mode configuration when Dialog is unavailable.

### 133. Add safe automatic parallel-job detection with user override
- [ ] **OPEN — pkgmk/compiler settings**
- **Automatic default:** Detect the available CPU/thread count and propose a sensible `MAKEFLAGS=-jN`/equivalent pkgmk setting rather than requiring manual configuration.
- **User override:** Allow the user to select:
  - `Auto`;
  - a specific number of jobs;
  - conservative presets where useful.
- **Resource awareness:** Do not blindly use all logical CPUs on extremely large systems if that is likely to exhaust RAM or destabilize large package builds. The automatic policy may consider both CPU count and available RAM.
- **Bootstrap sensitivity:** Allow Stage 1/2/3 to use an appropriate build-job policy without changing packages whose build systems require special serialization.
- **pkgmk.conf:** Persist the selected normal-system job setting in `/etc/pkgmk.conf` using the project's existing pkgmk variable conventions rather than appending duplicate/conflicting definitions.
- **Regression:** Test low-core, normal desktop, and very-high-core-count hosts/VMs and confirm user overrides are respected.

### 134. Detect x86/x86_64 CPU capabilities and offer optional native compiler tuning
- [ ] **OPEN — CPU feature detection / compiler settings**
- **Goal:** Detect the target machine's x86/x86_64 CPU capabilities and offer an explicit optimization option based on that hardware.
- **Detection:** Record CPU vendor/model, architecture level/features, and compiler-supported native tuning information using reliable tools such as the compiler's own native-option reporting plus `/proc/cpuinfo`/`lscpu` as supporting data.
- **User choices:** Provide at least:
  - **Portable BFSOS defaults** — normal/default and recommended for packages intended to run on other x86_64 systems;
  - **Optimize for this CPU** — local-machine tuning such as compiler-supported `-march=native`/`-mtune=native` or an equivalent resolved explicit flag set;
  - **Custom flags** — advanced user-provided C/C++ flags with validation/warning.
- **Safety warning:** CPU-specific binaries may not run on older/different x86_64 CPUs. Never silently enable native tuning merely because the current CPU supports it.
- **Bootstrap/toolchain caution:** Keep the initial toolchain/bootstrap portable by default. Native CPU tuning for GCC/glibc/binutils or other foundational toolchain components should only be enabled through an explicit advanced choice and must be regression-tested before being considered supported.
- **Installed-system policy:** For a machine-local BFSOS installation, the user may choose native tuning for normal future ports while leaving the distributed/default BFSOS package/build policy portable.
- **VM awareness:** CPU detection inside a VM reflects the virtual CPU model exposed by the hypervisor. Clearly report that fact where practical; do not assume host-only features are visible.
- **pkgmk.conf:** Persist the selected compiler/tuning flags cleanly in `/etc/pkgmk.conf`, replacing/updating the managed BFSOS compiler settings rather than accumulating duplicate lines.
- **Regression:** Verify portable builds run on generic x86_64 targets; verify native-tuned builds use the intended instruction set and fail safely/clearly if the user selects an incompatible custom policy.

### 135. Make BFSOS-managed `pkgmk.conf` settings idempotent and auditable
- [ ] **OPEN — configuration-file management**
- **Problem:** Bootstrap/installer settings must not repeatedly append duplicate `MAKEFLAGS`, `CFLAGS`, `CXXFLAGS`, `ccache`, or related entries each time settings are revisited.
- **Required behavior:** Manage a clearly marked BFSOS-generated block or canonical variables in `/etc/pkgmk.conf`. Updating settings replaces the previous managed values while preserving unrelated administrator customization where possible.
- **Suggested managed data:** job count, CFLAGS/CXXFLAGS, CPU tuning choice, ccache state/location/size, and other future build-policy settings.
- **Display:** Provide a way to show the effective build configuration from Bootstrap/Installer and on the installed system.
- **Backup:** Before overwriting an existing administrator-modified managed configuration, preserve a timestamped or `.orig` backup when appropriate and clearly report what changed.
- **Regression:** Re-enter the settings UI repeatedly, switch between Auto/native/portable/custom modes, and verify `/etc/pkgmk.conf` remains syntactically valid with one effective definition for each managed setting.

## r108 tracker update — 2026-08-15
- Added #132 for Compiler / Build Settings menus in both Bootstrap and Installer.
- Added #133 for automatic CPU/RAM-aware parallel-job detection with user override.
- Added #134 for x86/x86_64 CPU capability detection and optional local-machine compiler tuning while keeping portable defaults safe.
- Added #135 for idempotent, auditable persistence of the selected build/compiler settings into `pkgmk.conf`.

### 136. Remove generic `/boot` kernel/initramfs symlinks that generate broken GRUB entries
- [ ] **OPEN — kernel post-install / GRUB generation bug**
- **Observed during normal-kernel rebuild/upgrade test:** The kernel package created generic symlinks:
  - `/boot/vmlinuz-BFS-Linux -> vmlinuz-7.1.8-BFS-Linux`
  - `/boot/initramfs-BFS-Linux.img -> initramfs-7.1.8-BFS-Linux.img`
- **GRUB behavior:** `grub-mkconfig` treated `/boot/vmlinuz-BFS-Linux` as an additional kernel and generated default/advanced/recovery entries using `linux /vmlinuz-BFS-Linux ...`, but did **not** associate those entries with `/initramfs-BFS-Linux.img`.
- **Impact:** On RAID/LUKS/LVM root configurations, the generic GRUB entry is effectively unbootable because it lacks the initramfs required for md assembly, LUKS unlock, and LVM activation.
- **Confirmed good path:** The versioned kernel entries correctly use `/vmlinuz-7.1.8-BFS-Linux` with `/initramfs-7.1.8-BFS-Linux.img` and preserve all required `rd.md.uuid=`, `rd.luks.uuid=`, and `rd.lvm.lv=` arguments.
- **Required fix:** Stop creating or maintaining generic `/boot/vmlinuz-BFS-Linux` and `/boot/initramfs-BFS-Linux.img` symlinks in the kernel post-install path.
- **Keep:** Continue using `/usr/src/linux` as the normal/default kernel source-tree convenience symlink.
- **Dual-kernel rationale:** Versioned `/boot` filenames are also the correct model for normal + `linux-lts` coexistence; GRUB should enumerate explicit version/flavor-specific kernel+initramfs pairs rather than ambiguous generic names.
- **Upgrade cleanup:** Remove stale generic BFSOS `/boot` symlinks before running `grub-mkconfig`.
- **Safety ordering:** Verify the versioned kernel and initramfs exist and are valid before deleting old generic symlinks or regenerating GRUB.
- **Regression tests:** Rebuild/update the normal kernel on RAID/LUKS/LVM and confirm GRUB contains only valid versioned entries with matching initramfs lines; then install normal + LTS kernels and confirm both get separate valid GRUB entries without duplicate generic `Linux Linux` entries.

## r109 tracker update — 2026-08-16
- Added #136 for the GRUB regression caused by generic `/boot/vmlinuz-BFS-Linux` and `/boot/initramfs-BFS-Linux.img` symlinks.
- Permanent policy: keep `/usr/src/linux` as the normal-kernel source symlink, but use only versioned/flavor-specific kernel and initramfs filenames in `/boot`.



### 137. `ca-certificates` upgrade can leave owned compatibility CA bundle path missing
- [ ] **OPEN — package upgrade / CA trust-store regression**
- **Observed after `prt-get sysup`:** HTTPS downloads failed with:
  - `curl: (77) error adding trust anchors from file: /etc/ssl/certs/ca-certificates.crt`
- **Filesystem state:** `/etc/ssl/cert.pem` existed and was a valid CA bundle, but `/etc/ssl/certs/ca-certificates.crt` did not exist.
- **Package database inconsistency:** `pkginfo -o` reported both `/etc/ssl/cert.pem` and `/etc/ssl/certs/ca-certificates.crt` as owned by `ca-certificates`, even though the latter path was absent on disk.
- **Manual recovery that worked:** recreate the compatibility symlink:
  - `/etc/ssl/certs/ca-certificates.crt -> ../cert.pem`
- **Impact:** All curl/pkgmk HTTPS source downloads can fail after an otherwise successful system upgrade, preventing package installation/update (observed while attempting `prt-get depinst linux-lts`).
- **Required fix:** Ensure fresh install **and package upgrade** paths always leave the CA compatibility symlink present and correct after `ca-certificates` is installed/upgraded.
- **Ownership/config-file handling:** Audit pkgutils config-file preservation/upgrade semantics so a package-owned symlink cannot be omitted while the package database still records it as installed.
- **make-ca interaction:** Re-verify the previous `make-ca` ownership-conflict fix and make sure neither package deletes or suppresses the compatibility symlink during upgrade.
- **Post-install validation:** The `ca-certificates` package should verify that `/etc/ssl/cert.pem` exists and that `/etc/ssl/certs/ca-certificates.crt` resolves to the active bundle.
- **Regression tests:**
  - Fresh install `ca-certificates` and verify curl HTTPS works.
  - Upgrade from the previous BFSOS `ca-certificates` package through normal `prt-get sysup` and verify the symlink survives/is recreated.
  - Confirm `pkginfo -o` matches the actual filesystem state.
  - Run `curl -Iv https://www.kernel.org/` and a normal `pkgmk` HTTPS download after upgrade.

### 138. `linux-lts` rejects valid base `kernelrelease` before compile
- [ ] **OPEN — linux-lts Pkgfile validation bug**
- **Observed during first `linux-lts` build:** Debian source download and patch application succeeded, kernel configuration completed, and required BFSOS RAID/ZRAM config checks passed.
- **Confirmed config before failure:** `MD_LINEAR=m`, `MD_RAID0=m`, `MD_RAID1=m`, `MD_RAID10=m`, `MD_RAID456=m`, and `ZRAM=m`.
- **Failure point:** `make -s kernelrelease` returned the valid base release `6.12.101`, but the Pkgfile rejected it with:
  - `Unexpected LTS kernel release: 6.12.101`
- **Context:** The Pkgfile sets `LOCALVERSION=-BFS-LTS`, but the validation logic assumes the suffix will already be present in the value returned at that stage.
- **Required fix:** Validate the base upstream/Debian kernel release separately from the final BFSOS flavor release. Do not reject a correct `6.12.101` base release merely because the BFS flavor suffix has not yet been reflected by that check.
- **Final installed release:** Still require the built/installed kernel, modules, source/build links, initramfs, and GRUB entry to use the intended flavor-specific release such as `6.12.101-BFS-LTS`.
- **Do not weaken validation blindly:** Explicitly verify both the expected base version and the final flavored release at the appropriate build/install stages.
- **Regression tests:**
  - Rebuild `linux-lts` and confirm it proceeds past kernelrelease validation into compilation.
  - Verify the final module directory and `/boot` filenames are flavor/version-specific.
  - Verify installing LTS does not replace `/usr/src/linux` or the normal kernel as the default.
  - Verify Dracut contains `linear raid0 raid1 raid10 raid456` and GRUB gets a correct matching initramfs entry.

## r110 tracker update — 2026-08-16
- Added #137 for the exact `ca-certificates` upgrade regression where the package database owns `/etc/ssl/certs/ca-certificates.crt` but the symlink is absent, breaking curl HTTPS with error 77.
- Added #138 for the first `linux-lts` build failure caused by rejecting the valid base `6.12.101` kernelrelease before compilation.


## r111 implementation/audit pass — 2026-08-16

- **Validation policy:** Per maintainer direction, implemented items in this pass remain `[ ]` until they are personally build/install/boot-tested. Implementation notes do not imply regression completion.
- **Core cleanup implemented for testing:** Removed `gcc13`, the obsolete `filesystem` test port, `lfs-bootscripts`, `sysvinit`, `runit`, `runit-rc`, `mkinitcpio`, `mkinitramfs`, and orphaned `mkinitcpio-busybox`. Removed the remaining runit-specific pkgutils upgrade/service-generation rules. Regenerated `ports/core/REPO` and `ports/opt/REPO` after collection changes.
- **Collection cleanup implemented for testing:** Moved obvious non-base/development/compatibility packages from `core` to `opt`, including the non-bootstrap Python helper/module set, `fuse2`, `freetype2`, Git, GPM, SCons, wget/wgetpaste, legacy net-tools/wireless-tools, Syslinux, sysklogd, eudev, dhcpcd, Tcl/Expect, and related optional utilities. Removed duplicate older `opt` copies where the retained package now lives in `core`.
- **Non-LFS core audit policy:** Latest stable upstream is preferred; current BLFS and CRUX are strong integration/reference sources but not absolute version ceilings. Relevant BLFS/CRUX patches or compatibility constraints may justify deviations and must be documented.
- **Non-LFS core refresh implemented for testing:** Refreshed the audited retained core set including current mdadm, nftables/libnftnl, pciutils, GPT fdisk, mtools, Squashfs tools, NASM, libarchive, rsync, Dash and CrackLib references/versions where applicable; replaced encountered legacy SysV service packaging with systemd unit packaging.
- **Normal kernel compatibility implementation for testing:** The normal/default kernel now explicitly enforces broad x86_64 Wi-Fi/network infrastructure, Bluetooth, ALSA/HDA/USB audio, x86 SoC/SOF/SoundWire audio, V4L2/media/UVC webcam support, common USB storage/UAS/virtio block, and representative hardware RAID/HBA/SCSI controller drivers. Existing config already contained broad coverage; the Pkgfile now makes key compatibility classes explicit and validates them after `olddefconfig`.
- **CRUX kernel comparison:** Use CRUX 3.8's x86_64 kernel guidance/config as a sanity-check baseline for boot-critical controller/filesystem support and broad modular hardware coverage, while preserving BFSOS's Dracut, MD/LUKS/LVM, filesystem, networking, audio and webcam policy. Exact BFSOS configuration remains version-controlled rather than copied blindly from CRUX.
- **Hardware detection scope:** Issue #125 is intentionally deferred to post-1.0 / target 1.1. BFSOS 1.0 focuses on broad default x86_64 driver coverage rather than adding a new live-hardware comparison subsystem immediately before release.
- **`pkgmk` privilege separation implementation for testing:** Added the dedicated `pkgmk` system account, package-cache/build-cache ownership, and `prt-get` delegation of package builds through an unprivileged `pkgmk` + `fakeroot` wrapper. Root remains responsible for the final package installation/database operation. Existing installations receive account/directory migration handling rather than requiring the ports tree itself to be owned by `pkgmk`.
- **Ports ownership rule:** `/usr/ports` remains root/admin managed and may be refreshed normally with `ports -u`; the `pkgmk` account only requires read access to ports plus write access to package source/package/work and ccache directories. A ports delete/resync is not required merely because package builds are unprivileged.
- **ccache implementation for testing:** `ccache`, `fmt`, and `xxhash` are included in the base build, installer mandatory build tooling, and normal pkgmk configuration. Default ccache limit is **20 GB when virtualization is detected** and **equal to detected physical RAM in GiB on bare metal**; the user may override it.
- **Bootstrap → installer build-setting inheritance:** Bootstrap compiler/build settings control applicable bootstrap/base builds. If the user changes them, those values are carried into the base and presented as inherited defaults in the installer. If Bootstrap settings are untouched, the installer starts from its BFSOS defaults. Installer changes override inherited values only when explicitly selected. Managed values are written idempotently to `pkgmk.conf`.
- **CA trust regression implementation for testing:** `ca-certificates` owns and repairs `/etc/ssl/certs/ca-certificates.crt -> ../cert.pem` (and the compatibility bundle link) on fresh install and upgrade; `make-ca` does not own the conflicting path.
- **Kernel/GRUB implementation for testing:** Both kernel flavors stop generating generic `/boot/vmlinuz-BFS-*` and generic initramfs symlinks that GRUB can mistake for standalone kernels. `/usr/src/linux` remains owned by the normal/default kernel; LTS uses flavor/version-specific source/module/build links.
- **LTS kernel validation implementation for testing:** Base `6.12.101` and final `6.12.101-BFS-LTS` releases are validated separately so the build is not rejected before compilation merely because the BFSOS suffix is applied through the explicit LTS build path.

### 139. BFSOS 1.0 build/cache and 1.1 hardware-audit release scope
- [ ] **POLICY RECORDED — implementation/regression validation pending**
- **1.0:** Prioritize broad normal-kernel x86_64 NIC/Wi-Fi, sound/x86 audio-SoC, camera/UVC, common storage/SCSI/HBA/hardware-RAID compatibility, reliable package-build privilege separation, ccache defaults, and compiler/build settings.
- **1.1 target:** Implement the live-environment hardware inventory/driver comparison and persistent missing-driver report described in #125 after 1.0 stability.
- **ccache defaults:** 20 GB in detected VMs; on bare metal, default maximum cache size equals detected physical RAM (for example 64 GiB RAM -> 64 GB ccache), always user-overridable.
- **Do not interpret this as RAM allocation:** The ccache value is a disk-cache size limit, not memory reservation.

## r112 completion/reconciliation pass — 2026-08-16

- [ ] **MAINTAINER REGRESSION TESTING REQUIRED — no implementation item is marked complete until Brian personally tests it.**
- Reconciled the tracker against the actual r112 project tree and packaged the implemented changes for testing.
- Removed the approved obsolete ports: `gcc13`, `filesystem`, `lfs-bootscripts`, `sysvinit`, `runit`, `runit-rc`, `mkinitcpio`, `mkinitramfs`, and orphaned `mkinitcpio-busybox`.
- Moved obvious non-base ports from `core` to `opt`: `argon2`, `dejagnu`, `isl`, `fuse2`, `freetype2`, `git`, `gpm`, `scons`, `wget`, `wgetpaste`, `net-tools`, `wireless-tools`, `syslinux`, `sysklogd`, `eudev`, `dhcpcd`, `tcl`, and `expect`. Removed duplicate `opt` copies where a canonical retained package already exists; final core/opt duplicate directory check is empty.
- Added the dedicated `pkgmk` system account (UID/GID 82), pkg cache/ccache ownership, and `bfs-pkgmk` build wrapper. `/usr/ports` remains root/admin managed and does not need to be deleted/re-synced solely because builds become unprivileged.
- Added `ccache` to core/base tooling and refreshed it to 4.13.6 with core `fmt 12.2.0` and `xxhash 0.8.3`. Default ccache maximum is 20G in detected VMs and equal to detected physical RAM (GiB) on bare metal; it is a disk-cache limit and remains user-overridable.
- Added Bootstrap compiler/build settings for job count, portable/native/custom optimization, ccache state and cache size. Customized Bootstrap settings are persisted and applied to applicable base/pkgmk builds.
- Added matching Installer compiler/build settings. `inherited` leaves Bootstrap/base values untouched; explicit installer choices override the installed system's `pkgmk.conf` values.
- Installer mandatory package phase now ensures `fakeroot`, `fmt`, `xxhash`, and `ccache` are installed after the mandatory system upgrade, allowing migration from older base archives.
- Implemented #136 kernel/GRUB fix: normal and LTS post-install paths remove generic `/boot/vmlinuz-BFS-*` and generic initramfs aliases before GRUB regeneration; versioned kernel/initramfs files remain authoritative.
- Implemented #137 CA regression repair: `ca-certificates` post-install recreates `/etc/ssl/certs/ca-certificates.crt -> ../cert.pem` and validates the main bundle exists.
- Implemented #138 LTS release fix: base kernel release validation is separate from the final `6.12.101-BFS-LTS` flavor; LTS build/module installation uses explicit `LOCALVERSION=-BFS-LTS`.
- Refreshed additional retained non-LFS core packages for testing: `mdadm 4.4`, `pciutils 3.15.0`, `gptfdisk 1.0.10`, `mtools 4.0.49`, `squashfs-tools 4.7.5`, `nasm 3.02`, `libarchive 3.8.8`, `dash 0.5.13`, `nftables 1.1.6`, `libnftnl 1.3.1`, and `rsync 3.4.4`. `prt-get` remains 5.19.9 because that is the current CRUX 3.8 package verified in this pass.
- Replaced encountered nftables/rsync SysV service packaging with systemd unit files and removed the remaining runit-specific pkgutils service/config rules.
- CRUX 3.8 kernel guidance remains a comparison baseline, not a configuration to copy blindly. BFSOS keeps its broader Dracut/MD/LUKS/LVM/filesystem and x86_64 hardware-compatibility policy. Full live hardware inventory/diff remains the planned 1.1 feature from #125.
- Regenerated `ports/core/REPO` and `ports/opt/REPO` after moves/removals/edits.
- Static validation: all core/opt Pkgfiles plus Bootstrap, consolidated installer, kernel/CA/ccache post-install scripts and the pkgmk wrapper pass `bash -n`; no core/opt duplicate directory names remain.
- See `BFSOS-r111-core-audit-20260816.md` for the retained-core inventory and maintainer regression-test checklist.
