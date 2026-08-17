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
- The same pkgutils port also patches the packaged `/usr/bin/pkgmk` in `post_build()` so the installed BFSOS pkgutils package consistently uses the universally available `C` locale.
- The GCC port was also found to force `LANG=en_US.UTF-8`; `ports/core/gcc/Pkgfile` was changed to use `LANG=C` for bootstrap/build consistency.
- Keep the global bootstrap environment on `LANG=C`, `LC_ALL=C`, and `LANGUAGE=C`.
- [ ] **Verification pending on next clean bootstrap/RC run:** confirm Stage 1/2/3 no longer produce the previous flood of `setlocale: LC_ALL: cannot change locale (C.UTF-8)` warnings.
- If isolated locale warnings remain after a clean rebuild, capture the exact package/log and investigate only that package rather than changing the global locale policy again.
- These locale fixes should be pushed to both the main BFSOS project and the separate ports repository so the bootstrap and port trees remain consistent.

### Bootstrap Stage 3 locale regression check
- [ ] During the next clean Stage 3 rebuild, verify that `pkgmk`, GCC, and shell subprocesses inherit plain `C` and that no build-generated environment reintroduces `C.UTF-8` or `en_US.UTF-8`.
- Check the newly installed temporary-toolchain `pkgmk` with `grep -nE 'LC_ALL|LANG' .../pkgmk` as a regression check after pkgutils is rebuilt.



### Bootstrap Stage 3 time synchronization
- [x] **FIX IMPLEMENTED in bootstrap r45; regression test pending:** Remove the redundant time synchronization step from Bootstrap Stage 3.
- Time is already synchronized when `bootstrap.sh` is initially launched, so Stage 3 should not perform another automatic time sync before rebuilding the base system with the final toolchain.
- Preserve the initial bootstrap startup time synchronization; this change applies specifically to the extra Stage 3 sync.



### Pre-1.0 optional software and console usability checks
- [x] **Installer support implemented in r37; port availability/build regression pending:** GPM is now selectable from Optional Software and included in the package plan when selected.
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
- [ ] **1.0 release/public launch preparation:** After the 1.0 release-candidate storage/RAID/configuration validation is complete and no release-blocking core issues remain, clean up and rewrite the public `README.md` and supporting documentation for the BFSOS 1.0 release.
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

### 90. Bare-metal complex-storage install reached successful completion; first-boot validation pending
- [x] **BARE-METAL FIRST BOOT PASSED:** complex UEFI + separate `/boot` + LUKS + LVM + Btrfs + MD RAID0 + second LUKS/LVM booted successfully; all intended subvolumes mounted, RAID assembled, SSH/sudo worked, and `systemctl --failed` reported zero failed units.
- The installer completed without an installation-stage failure on the tested UEFI + separate `/boot` + LUKS + LVM + Btrfs + MD RAID0 + second LUKS/LVM configuration.
- Post-install inspection confirmed the intended Btrfs subvolumes, RAID/LUKS/LVM layers, EFI files, kernel, initramfs, and `fstab` after the manual GRUB correction.
- The remaining release-candidate gate for this specific run is the **first bare-metal boot**.
- If the system boots cleanly, record this complex storage scenario as passed while keeping issues 84-89 as installer/usability fixes or regression work.
- If first boot fails, treat the boot failure as a 1.0-rc blocker and capture the exact Dracut/GRUB/systemd failure before making additional changes.


### 91. Default text-console resolution for high-DPI displays
- [x] **IMPLEMENTED in installer r40; regression test pending on additional connector types:** installer detects the connected DRM connector and adds a deduplicated 1920x1080@60 console `video=` argument to generated GRUB defaults when a connector is detected.
- **Bare-metal result:** On the tested 3840x2160 DisplayPort monitor, the console font became very small after the DRM console switched to the native 4K mode.
- Manually adding `video=DP-1:1920x1080@60` produced a comfortable console size with the 32-pixel font and remained readable after the graphics/DRM handoff.
- **Planned default:** Add a 1920x1080 text-console video mode to the BFSOS GRUB defaults/GRUB port so new installs do not default to an excessively tiny 4K virtual console.
- Do not blindly duplicate the argument if it is already present; GRUB command-line generation should deduplicate persistent video arguments.
- Consider hardware/output-name portability before finalizing the implementation: the tested connector is `DP-1`, so the permanent mechanism should avoid assuming every machine uses that connector name if GRUB/kernel syntax allows a safer generic/default approach.
- [ ] **Regression test:** Verify 1920x1080 console mode on bare metal, HDMI/DP variants where available, and confirm it does not interfere with later graphical desktop resolution selection.

### 92. Installer console font choices: retain normal sizes and add 32-pixel option
- [x] **IMPLEMENTED in installer r40; regression test pending:** retained 16 and ~20 choices, added 32-pixel Extra Large using `latarcyrheb-sun32`, and added 19/22-pixel fallbacks for the ~20 choice.
- Keep the existing **16-pixel** and approximately **20-pixel** console-font choices.
- Add a new **32-pixel / Extra Large** console-font choice to the installer.
- **Bare-metal result:** `latarcyrheb-sun32.psfu.gz` is installed, loads successfully with `setfont`, and is much more usable on a 4K physical display when paired with a 1920x1080 text-console resolution.
- The earlier 22-pixel test (`LatGrkCyr-12x22`) was still effectively microscopic at native 3840x2160, so font size alone is not sufficient on high-DPI consoles.
- The installer should write the selected persistent font to `/etc/vconsole.conf`.
- If the Extra Large option is selected, consider pairing it with the installer/GRUB high-DPI console-resolution option rather than changing graphical desktop resolution.
- [ ] **Regression test:** Test 16, ~20, and 32-pixel choices on bare metal and confirm each persists after reboot and remains readable after the DRM console handoff.


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

