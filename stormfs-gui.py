#!/usr/bin/env python3
"""
StormFS Linux - Graphical Installer
A PyQt5-based wizard for building, partitioning, and installing StormFS Linux.

Usage:
    sudo python3 stormfs-gui.py

Dependencies are auto-installed on first run if missing.
"""

import sys
import os
import subprocess
import shutil
import signal
import re
import json
import textwrap
import time
import threading
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

###############################################################################
# Dependency bootstrap - install PyQt5 and system tools if missing
###############################################################################

def detect_distro():
    """Detect the host Linux distribution package manager."""
    if shutil.which("pacman"):
        return "arch"
    if shutil.which("apt"):
        return "debian"
    if shutil.which("dnf"):
        return "fedora"
    if shutil.which("zypper"):
        return "opensuse"
    if shutil.which("emerge"):
        return "gentoo"
    if shutil.which("xbps-install"):
        return "void"
    if shutil.which("apk"):
        return "alpine"
    return "unknown"

def ensure_pyqt5():
    """Ensure PyQt5 is available, install if missing."""
    try:
        from PyQt5.QtWidgets import QApplication
        return True
    except ImportError:
        pass

    distro = detect_distro()
    print("[StormFS] PyQt5 not found. Attempting automatic installation...")
    cmds = {
        "arch":    ["sudo", "pacman", "-S", "--noconfirm", "python-pyqt5"],
        "debian":  ["sudo", "apt", "install", "-y", "python3-pyqt5"],
        "fedora":  ["sudo", "dnf", "install", "-y", "python3-qt5"],
        "opensuse":["sudo", "zypper", "install", "-y", "python3-Qt5"],
        "gentoo":  ["sudo", "emerge", "-av", "dev-python/PyQt5"],
        "void":    ["sudo", "xbps-install", "-Sy", "python3-PyQt5"],
        "alpine":  ["sudo", "apk", "add", "py3-qt5"],
    }
    if distro in cmds:
        try:
            subprocess.check_call(cmds[distro])
            return True
        except subprocess.CalledProcessError:
            pass

    # Fallback: pip
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "PyQt5"])
        return True
    except subprocess.CalledProcessError:
        pass

    print("[StormFS] ERROR: Could not install PyQt5 automatically.")
    print("[StormFS] Please install PyQt5 manually for your distribution.")
    return False

def ensure_system_deps():
    """Ensure system tools needed for installation are available."""
    distro = detect_distro()
    needed_tools = {
        "arch":    ["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub", "git", "squashfs-tools", "xorriso"],
        "debian":  ["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub-common", "git", "squashfs-tools", "xorriso"],
        "fedora":  ["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub2-common", "git", "squashfs-tools", "xorriso"],
        "opensuse":["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub2-common", "git", "squashfs-tools", "xorriso"],
        "gentoo":  ["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub", "git", "squashfs-tools", "xorriso"],
        "void":    ["parted", "dosfstools", "e2fsprogs", "btrfs-progs",
                     "lvm2", "grub", "git", "squashfs-tools", "xorriso"],
    }
    if distro in needed_tools:
        print(f"[StormFS] Ensuring system dependencies are installed ({distro})...")
        pkg_cmd = {
            "arch":    ["sudo", "pacman", "-S", "--noconfirm", "--needed"],
            "debian":  ["sudo", "apt", "install", "-y"],
            "fedora":  ["sudo", "dnf", "install", "-y"],
            "opensuse":["sudo", "zypper", "install", "-y"],
            "gentoo":  ["sudo", "emerge", "-av"],
            "void":    ["sudo", "xbps-install", "-Sy"],
        }
        try:
            subprocess.check_call(pkg_cmd[distro] + needed_tools[distro])
        except subprocess.CalledProcessError:
            print("[StormFS] WARNING: Some system dependencies could not be installed.")
            print("[StormFS] The installer may still work for available tools.")

###############################################################################
# Utility helpers
###############################################################################

def run_cmd(cmd, root=None, capture=False):
    """Run a shell command, optionally in a chroot."""
    if root:
        cmd = ["chroot", root, "/usr/bin/env", "-i",
               "HOME=/root", "TERM=linux", "LANG=C", "LC_ALL=C",
               "PATH=/usr/bin:/usr/sbin:/bin:/sbin"] + cmd
    try:
        if capture:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            return result.returncode, result.stdout, result.stderr
        else:
            return subprocess.run(cmd, timeout=600).returncode, "", ""
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"

def get_block_devices():
    """Return list of (name, size, type, model) for block disks."""
    devices = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-prno", "NAME,SIZE,TYPE,MODEL"],
            text=True, timeout=10
        )
        for line in out.strip().splitlines():
            parts = line.split(None, 3)
            if len(parts) >= 3 and parts[2] == "disk":
                name = parts[0]
                size = parts[1]
                model = parts[3] if len(parts) > 3 else ""
                devices.append((name, size, model.strip()))
    except Exception:
        pass
    return devices

def get_partitions(device):
    """Return list of (name, size, fstype, mountpoint) for partitions on a device."""
    parts = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-prno", "NAME,SIZE,FSTYPE,MOUNTPOINT", device],
            text=True, timeout=10
        )
        for line in out.strip().splitlines():
            fields = line.split(None, 3)
            if len(fields) >= 3 and fields[2] in ("part", "lvm", "crypt", "raid"):
                name = fields[0]
                size = fields[1]
                fstype = fields[2] if len(fields) > 2 else ""
                mnt = fields[3] if len(fields) > 3 else ""
                parts.append((name, size, fstype, mnt))
    except Exception:
        pass
    return parts

def detect_boot_mode():
    """Detect UEFI or BIOS boot mode."""
    if os.path.isdir("/sys/firmware/efi"):
        return "uefi"
    return "bios"

def get_timezone_list():
    """Get list of available timezones."""
    tz_path = Path("/usr/share/zoneinfo")
    zones = []
    if tz_path.exists():
        exclude = {"Etc", "posix", "right", "Factory", "US", "Canada",
                    "Brazil", "Argentina", "Indiana", "Kentucky", "North_Dakota",
                    "South_Dakota", "Menominee", "Thunder_Bay", "Vincennes",
                    "Montreal", "Pangnirtung", "Resolute", "Yellowknife"}
        for entry in sorted(tz_path.iterdir()):
            if entry.is_dir() and entry.name not in exclude and not entry.name.startswith("."):
                for sub in sorted(entry.iterdir()):
                    if sub.is_file() and not sub.name.startswith("."):
                        zones.append(f"{entry.name}/{sub.name}")
                    elif sub.is_dir():
                        for subsub in sorted(sub.iterdir()):
                            if subsub.is_file() and not subsub.name.startswith("."):
                                zones.append(f"{entry.name}/{sub.name}/{subsub.name}")
    return zones

def get_locale_list():
    """Get list of available UTF-8 locales."""
    locales = []
    for gen_file in ["/etc/locale.gen", "/etc/locales"]:
        if os.path.exists(gen_file):
            try:
                with open(gen_file) as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "UTF-8" in line:
                            loc = line.split()[0] if line.split() else line.lstrip("#")
                            locales.append(loc)
                        elif line.startswith("#") and "UTF-8" in line:
                            loc = line.lstrip("#").split()[0] if line.lstrip("#").split() else ""
                            if loc:
                                locales.append(loc)
            except Exception:
                pass
            break
    if not locales:
        locales = ["en_US.UTF-8", "en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8",
                    "es_ES.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8", "ja_JP.UTF-8",
                    "zh_CN.UTF-8", "ko_KR.UTF-8", "ru_RU.UTF-8"]
    return sorted(set(locales))

def get_keymap_list():
    """Get available keymaps."""
    keymaps = []
    for kdir in ["/usr/share/keymaps", "/usr/share/kbd/keymaps"]:
        kdir_path = Path(kdir)
        if kdir_path.exists():
            for f in kdir_path.rglob("*.map.gz"):
                keymaps.append(f.stem.replace(".map", ""))
            break
    if not keymaps:
        keymaps = ["us", "uk", "de", "fr", "es", "it", "pt", "jp", "br"]
    return sorted(set(keymaps))

def get_disks():
    """Get available disks for GRUB installation."""
    disks = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-prno", "NAME,SIZE,MODEL", "--type", "disk"],
            text=True, timeout=10
        )
        for line in out.strip().splitlines():
            parts = line.split(None, 2)
            if len(parts) >= 2:
                name = parts[0]
                size = parts[1]
                model = parts[2] if len(parts) > 2 else ""
                disks.append((name, size, model.strip()))
    except Exception:
        pass
    return disks

###############################################################################
# PyQt5 GUI
###############################################################################

def build_app():
    from PyQt5.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QStackedWidget, QLabel, QPushButton, QFrame, QProgressBar,
        QComboBox, QCheckBox, QLineEdit, QSpinBox, QTextEdit, QScrollArea,
        QGroupBox, QRadioButton, QButtonGroup, QSplitter, QMessageBox,
        QGridLayout, QSizePolicy, QTabWidget
    )
    from PyQt5.QtCore import Qt, QThread, pyqtSignal, QSize, QTimer
    from PyQt5.QtGui import QFont, QIcon, QColor, QPalette, QPixmap

    app = QApplication(sys.argv)
    app.setApplicationName("StormFS Installer")
    app.setOrganizationName("StormFS")

    # ── Global stylesheet ──
    app.setStyleSheet("""
        QMainWindow { background: #1e1e2e; }
        QLabel { color: #cdd6f4; font-size: 13px; }
        QPushButton {
            background: #313244; color: #cdd6f4; border: 1px solid #45475a;
            border-radius: 6px; padding: 8px 20px; font-size: 13px; min-width: 100px;
        }
        QPushButton:hover { background: #45475a; }
        QPushButton:pressed { background: #585b70; }
        QPushButton:disabled { background: #1e1e2e; color: #585b70; border-color: #313244; }
        QPushButton#primary {
            background: #89b4fa; color: #1e1e2e; font-weight: bold;
            border: none; padding: 10px 30px; font-size: 14px;
        }
        QPushButton#primary:hover { background: #74c7ec; }
        QPushButton#danger { background: #f38ba8; color: #1e1e2e; }
        QPushButton#danger:hover { background: #eba0ac; }
        QLineEdit {
            background: #313244; color: #cdd6f4; border: 1px solid #45475a;
            border-radius: 4px; padding: 6px 10px; font-size: 13px;
        }
        QLineEdit:focus { border-color: #89b4fa; }
        QComboBox {
            background: #313244; color: #cdd6f4; border: 1px solid #45475a;
            border-radius: 4px; padding: 6px 10px; font-size: 13px;
        }
        QComboBox::drop-down { border: none; }
        QComboBox QAbstractItemView { background: #313244; color: #cdd6f4; selection-background-color: #45475a; }
        QCheckBox { color: #cdd6f4; spacing: 8px; font-size: 13px; }
        QCheckBox::indicator { width: 18px; height: 18px; border: 1px solid #45475a; border-radius: 3px; background: #313244; }
        QCheckBox::indicator:checked { background: #89b4fa; border-color: #89b4fa; }
        QRadioButton { color: #cdd6f4; spacing: 8px; font-size: 13px; }
        QRadioButton::indicator { width: 18px; height: 18px; border: 1px solid #45475a; border-radius: 9px; background: #313244; }
        QRadioButton::indicator:checked { background: #a6e3a1; border-color: #a6e3a1; }
        QTextEdit {
            background: #181825; color: #a6e3a1; border: 1px solid #313244;
            border-radius: 4px; font-family: 'Courier New', monospace; font-size: 12px;
        }
        QGroupBox {
            color: #cdd6f4; border: 1px solid #45475a; border-radius: 6px;
            margin-top: 12px; padding-top: 16px; font-size: 13px; font-weight: bold;
        }
        QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 6px; }
        QProgressBar {
            background: #313244; border: none; border-radius: 4px;
            text-align: center; color: #1e1e2e; font-weight: bold; height: 20px;
        }
        QProgressBar::chunk { background: #a6e3a1; border-radius: 4px; }
        QScrollArea { border: none; background: transparent; }
        QScrollBar:vertical { background: #1e1e2e; width: 10px; border-radius: 5px; }
        QScrollBar::handle:vertical { background: #45475a; border-radius: 5px; min-height: 30px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        QTabWidget::pane { border: 1px solid #45475a; border-radius: 4px; background: #1e1e2e; }
        QTabBar::tab { background: #313244; color: #cdd6f4; padding: 8px 16px;
                       border-top-left-radius: 6px; border-top-right-radius: 6px; margin-right: 2px; }
        QTabBar::tab:selected { background: #45475a; }
        QSpinBox { background: #313244; color: #cdd6f4; border: 1px solid #45475a;
                    border-radius: 4px; padding: 4px 8px; }
    """)

    # ── Colors ──
    BG = "#1e1e2e"
    SURFACE = "#313244"
    TEXT = "#cdd6f4"
    ACCENT = "#89b4fa"
    GREEN = "#a6e3a1"
    RED = "#f38ba8"
    YELLOW = "#f9e2af"
    PEACH = "#fab387"

    # ═══════════════════════════════════════════════════════════════════════
    # Build thread
    # ═══════════════════════════════════════════════════════════════════════
    class BuildThread(QThread):
        log_signal = pyqtSignal(str)
        progress_signal = pyqtSignal(int, str)
        finished_signal = pyqtSignal(bool, str)

        def __init__(self, settings):
            super().__init__()
            self.settings = settings
            self._stop = False

        def stop(self):
            self._stop = True

        def run(self):
            try:
                self._do_build()
            except Exception as e:
                self.finished_signal.emit(False, str(e))

        def _do_build(self):
            s = self.settings
            stages = [
                ("Stage 1: Building temporary toolchain", "1"),
                ("Stage 2: Building base system", "2"),
                ("Stage 3: Rebuilding with final toolchain", "3"),
                ("Stage 4: Verifying base system", "4"),
            ]
            for idx, (label, stage_num) in enumerate(stages):
                if self._stop:
                    self.finished_signal.emit(False, "Build cancelled by user")
                    return
                pct = int((idx / len(stages)) * 100)
                self.progress_signal.emit(pct, label)
                self.log_signal.emit(f"\n{'='*60}\n{label}\n{'='*60}\n")

                cmd = ["sudo", "-E", "./bootstrap.sh", stage_num]
                env = os.environ.copy()
                env["LC_ALL"] = "C"
                env["LANG"] = "C"

                proc = subprocess.Popen(
                    cmd, cwd=str(SCRIPT_DIR),
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, env=env, bufsize=1
                )
                for line in proc.stdout:
                    if self._stop:
                        proc.terminate()
                        self.finished_signal.emit(False, "Build cancelled by user")
                        return
                    self.log_signal.emit(line.rstrip("\n"))
                proc.wait()
                if proc.returncode != 0:
                    self.finished_signal.emit(
                        False, f"Stage {stage_num} failed with exit code {proc.returncode}"
                    )
                    return

            self.progress_signal.emit(100, "Build complete!")
            self.finished_signal.emit(True, "All build stages completed successfully!")

    # ═══════════════════════════════════════════════════════════════════════
    # Install thread
    # ═══════════════════════════════════════════════════════════════════════
    class InstallThread(QThread):
        log_signal = pyqtSignal(str)
        progress_signal = pyqtSignal(int, str)
        finished_signal = pyqtSignal(bool, str)

        def __init__(self, config):
            super().__init__()
            self.config = config
            self._stop = False

        def stop(self):
            self._stop = True

        def run(self):
            try:
                self._do_install()
            except Exception as e:
                self.finished_signal.emit(False, str(e))

        def _do_install(self):
            c = self.config
            root = "/mnt/stormfs"
            steps = [
                ("Formatting partitions", self._format_partitions, 10),
                ("Mounting filesystems", self._mount_filesystems, 15),
                ("Extracting rootfs", self._extract_rootfs, 40),
                ("Configuring system", self._configure_system, 55),
                ("Installing bootloader", self._install_bootloader, 70),
                ("Configuring users", self._configure_users, 80),
                ("Cleaning up", self._cleanup, 95),
            ]
            for label, func, pct in steps:
                if self._stop:
                    self.finished_signal.emit(False, "Installation cancelled")
                    return
                self.progress_signal.emit(pct, label)
                self.log_signal.emit(f"\n>>> {label}...\n")
                func(root)
            self.progress_signal.emit(100, "Installation complete!")
            self.finished_signal.emit(True, "StormFS Linux installed successfully!")

        def _format_partitions(self, root):
            c = self.config
            dev = c["root_device"]
            fs = c["root_fs"]
            self.log_signal.emit(f"  Formatting {dev} as {fs}...")
            fmt_cmds = {
                "ext4": ["mkfs.ext4", "-F", dev],
                "ext3": ["mkfs.ext3", "-F", dev],
                "ext2": ["mkfs.ext2", "-F", dev],
                "btrfs": ["mkfs.btrfs", "-f", dev],
                "xfs": ["mkfs.xfs", "-f", "-m", "crc=0", dev],
            }
            if fs in fmt_cmds:
                subprocess.check_call(fmt_cmds[fs])

            if c.get("swap_device") and c.get("swap_format"):
                self.log_signal.emit(f"  Setting up swap on {c['swap_device']}...")
                subprocess.check_call(["mkswap", c["swap_device"]])

            if c.get("efi_device") and c.get("boot_mode") == "uefi":
                self.log_signal.emit(f"  Formatting EFI partition {c['efi_device']} as FAT32...")
                subprocess.check_call(["mkfs.vfat", "-F32", c["efi_device"]])

            if c.get("home_device") and c.get("home_fs"):
                hfs = c["home_fs"]
                hdev = c["home_device"]
                self.log_signal.emit(f"  Formatting {hdev} as {hfs}...")
                fmt_h = {
                    "ext4": ["mkfs.ext4", "-F", "-L", "Home", hdev],
                    "btrfs": ["mkfs.btrfs", "-f", "-L", "Home", hdev],
                    "xfs": ["mkfs.xfs", "-f", "-m", "crc=0", "-L", "Home", hdev],
                }
                if hfs in fmt_h:
                    subprocess.check_call(fmt_h[hfs])

        def _mount_filesystems(self, root):
            c = self.config
            subprocess.check_call(["mkdir", "-p", root])
            subprocess.check_call(["mount", c["root_device"], root])

            if c.get("home_device"):
                subprocess.check_call(["mkdir", "-p", f"{root}/home"])
                subprocess.check_call(["mount", c["home_device"], f"{root}/home"])

            if c.get("efi_device") and c.get("boot_mode") == "uefi":
                subprocess.check_call(["mkdir", "-p", f"{root}/boot/efi"])
                subprocess.check_call(["mount", c["efi_device"], f"{root}/boot/efi"])

            if c.get("swap_device") and c.get("swap_format"):
                subprocess.check_call(["swapon", c["swap_device"]])

        def _extract_rootfs(self, root):
            import tarfile, lzma
            archive_dir = SCRIPT_DIR / "archives" / "base"
            archives = sorted(archive_dir.glob("bfs-rootfs-*.tar.xz"), reverse=True)
            if not archives:
                raise FileNotFoundError("No rootfs archive found in archives/base/")
            archive = archives[0]
            self.log_signal.emit(f"  Extracting {archive.name}...")
            subprocess.check_call(
                ["tar", "xJpf", str(archive), "-C", root]
            )
            for d in ["bin", "lib", "sbin"]:
                link = Path(root) / d
                usr_link = Path(root) / "usr" / d
                if not link.exists() and usr_link.exists():
                    os.symlink(f"usr/{d}", str(link))

        def _configure_system(self, root):
            c = self.config
            # fstab
            self.log_signal.emit("  Generating /etc/fstab...")
            fstab_lines = ["# <device> <dir> <type> <options> <dump> <fsck>"]
            if c.get("efi_device") and c.get("boot_mode") == "uefi":
                uuid = self._get_uuid(c["efi_device"])
                fstab_lines.append(f"UUID={uuid} /boot/efi vfat defaults 0 2")
            if c.get("swap_device"):
                uuid = self._get_uuid(c["swap_device"])
                fstab_lines.append(f"UUID={uuid} swap swap pri=1 0 0")
            root_uuid = self._get_uuid(c["root_device"])
            fstab_lines.append(f"UUID={root_uuid} / {c['root_fs']} defaults 1 1")
            if c.get("home_device") and c.get("home_fs"):
                uuid = self._get_uuid(c["home_device"])
                fstab_lines.append(f"UUID={uuid} /home {c['home_fs']} defaults 0 0")
            fstab_lines.extend([
                "proc /proc proc defaults 0 0",
                "sysfs /sys sysfs defaults 0 0",
                "tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0",
            ])
            fstab_path = Path(root) / "etc" / "fstab"
            fstab_path.parent.mkdir(parents=True, exist_ok=True)
            fstab_path.write_text("\n".join(fstab_lines) + "\n")

            # hostname
            self.log_signal.emit(f"  Setting hostname: {c['hostname']}...")
            hostname_path = Path(root) / "etc" / "hostname"
            hostname_path.write_text(c["hostname"] + "\n")
            hosts_path = Path(root) / "etc" / "hosts"
            hosts_path.write_text(
                f"127.0.0.1 localhost\n127.0.1.1 {c['hostname']}\n::1 localhost\n"
            )

            # timezone
            self.log_signal.emit(f"  Setting timezone: {c['timezone']}...")
            tz = Path(root) / "etc" / "localtime"
            tz_target = f"/usr/share/zoneinfo/{c['timezone']}"
            if tz.exists() or tz.is_symlink():
                os.remove(str(tz))
            os.symlink(tz_target, str(tz))
            tz_data = Path(root) / "etc" / "timezone"
            tz_data.write_text(c["timezone"] + "\n")
            vconf = Path(root) / "etc" / "vconsole.conf"
            vconf.write_text(f"KEYMAP={c['keymap']}\n")

            # locale
            self.log_signal.emit(f"  Setting locale: {c['locale']}...")
            locale_conf = Path(root) / "etc" / "locale.conf"
            locale_conf.write_text(f"LANG={c['locale']}\n")
            locale_gen = Path(root) / "etc" / "locale.gen"
            if locale_gen.exists():
                content = locale_gen.read_text()
                loc_base = c["locale"].replace(".UTF-8", "")
                content = content.replace(f"# {loc_base}.UTF-8", f"{loc_base}.UTF-8")
                locale_gen.write_text(content)

        def _install_bootloader(self, root):
            c = self.config
            self.log_signal.emit("  Installing GRUB bootloader...")

            # Add GRUB_DISABLE_OS_PROBER
            grub_default = Path(root) / "etc" / "default" / "grub"
            if grub_default.exists():
                content = grub_default.read_text()
                if "GRUB_DISABLE_OS_PROBER" not in content:
                    content += "\nGRUB_DISABLE_OS_PROBER=false\n"
                    grub_default.write_text(content)

            if c.get("boot_mode") == "uefi" and c.get("efi_device"):
                subprocess.check_call([
                    "chroot", root, "grub-install",
                    "--target=x86_64-efi",
                    "--efi-directory=/boot/efi",
                    "--bootloader-id=StormFS",
                    "--recheck",
                    c["root_device"]
                ])
            else:
                subprocess.check_call([
                    "chroot", root, "grub-install",
                    "--target=i386-pc",
                    "--recheck",
                    c["root_device"]
                ])

            subprocess.check_call(["chroot", root, "grub-mkconfig", "-o", "/boot/grub/grub.cfg"])

        def _configure_users(self, root):
            c = self.config
            self.log_signal.emit(f"  Creating user: {c['username']}...")

            subprocess.check_call([
                "chroot", root, "useradd",
                "-m", "-G", "users,wheel,audio,video",
                "-s", "/bin/bash", c["username"]
            ])
            self._set_password(root, c["username"], c["user_password"])
            self._set_password(root, "root", c["root_password"])

            # sudoers
            sudoers = Path(root) / "etc" / "sudoers.d" / "stormfs"
            sudoers.parent.mkdir(parents=True, exist_ok=True)
            sudoers.write_text(f"{c['username']} ALL=(ALL) NOPASSWD:ALL\n")
            sudoers.chmod(0o440)

            # enable services
            self.log_signal.emit("  Enabling systemd services...")
            for svc in ["dbus", "NetworkManager", "sshd"]:
                try:
                    subprocess.check_call(
                        ["chroot", root, "systemctl", "enable", svc],
                        timeout=30
                    )
                except Exception:
                    self.log_signal.emit(f"  WARNING: Could not enable {svc}")

        def _cleanup(self, root):
            c = self.config
            self.log_signal.emit("  Cleaning up...")
            # Remove installer artifacts from installed system
            for f in ["/root/live_script.sh", "/root/post-install.sh",
                       "/root/post-extract.sh", "/usr/bin/stormfs-installer"]:
                p = Path(root) + f if not f.startswith(root) else f
                full = Path(root) / f.lstrip("/")
                if full.exists():
                    full.unlink()
            desktop = Path(root) / "home" / c["username"] / "Desktop" / "Install StormFS.desktop"
            if desktop.exists():
                desktop.unlink()

            # unmount
            subprocess.run(["swapoff", c.get("swap_device", "")],
                           capture_output=True, timeout=30)
            for mnt in ["/boot/efi", "/home", "/"]:
                full_mnt = root if mnt == "/" else root + mnt
                subprocess.run(["umount", full_mnt], capture_output=True, timeout=30)

        def _get_uuid(self, device):
            try:
                out = subprocess.check_output(
                    ["blkid", "-o", "value", "-s", "UUID", device],
                    text=True, timeout=10
                )
                return out.strip()
            except Exception:
                return "UNKNOWN"

        def _set_password(self, root, user, password):
            proc = subprocess.Popen(
                ["chroot", root, "chpasswd"],
                stdin=subprocess.PIPE, timeout=30
            )
            proc.communicate(input=f"{user}:{password}\n".encode())
            if proc.returncode != 0:
                raise RuntimeError(f"Failed to set password for {user}")

    # ═══════════════════════════════════════════════════════════════════════
    # Main window
    # ═══════════════════════════════════════════════════════════════════════
    class StormFSInstaller(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle("StormFS Linux Installer")
            self.setMinimumSize(900, 650)
            self.resize(1000, 700)

            self.config = {
                "build_jobs": "auto",
                "build_opt": "portable",
                "ccache": True,
                "boot_mode": detect_boot_mode(),
                "hostname": "stormfs",
                "timezone": "America/New_York",
                "locale": "en_US.UTF-8",
                "keymap": "us",
                "root_fs": "ext4",
            }
            self.build_thread = None
            self.install_thread = None

            central = QWidget()
            self.setCentralWidget(central)
            main_layout = QVBoxLayout(central)
            main_layout.setContentsMargins(0, 0, 0, 0)
            main_layout.setSpacing(0)

            # Header
            header = QFrame()
            header.setFixedHeight(60)
            header.setStyleSheet(f"background: {SURFACE}; border-bottom: 1px solid #45475a;")
            header_layout = QHBoxLayout(header)
            title = QLabel("StormFS Linux Installer")
            title.setStyleSheet(f"font-size: 20px; font-weight: bold; color: {ACCENT};")
            header_layout.addWidget(title)
            header_layout.addStretch()
            self.step_label = QLabel("Step 1/9")
            self.step_label.setStyleSheet(f"font-size: 13px; color: {TEXT};")
            header_layout.addWidget(self.step_label)
            main_layout.addWidget(header)

            # Stacked pages
            self.pages = QStackedWidget()
            main_layout.addWidget(self.pages)

            # Footer with navigation
            footer = QFrame()
            footer.setFixedHeight(60)
            footer.setStyleSheet(f"background: {SURFACE}; border-top: 1px solid #45475a;")
            footer_layout = QHBoxLayout(footer)
            footer_layout.setContentsMargins(20, 10, 20, 10)

            self.btn_back = QPushButton("  Back  ")
            self.btn_back.clicked.connect(self.go_back)
            footer_layout.addWidget(self.btn_back)
            footer_layout.addStretch()
            self.btn_next = QPushButton("  Next  ")
            self.btn_next.setObjectName("primary")
            self.btn_next.clicked.connect(self.go_next)
            footer_layout.addWidget(self.btn_next)
            main_layout.addWidget(footer)

            # Build pages
            self.page_names = []
            self._build_welcome_page()
            self._build_settings_page()
            self._build_build_page()
            self._build_disk_page()
            self._build_partition_page()
            self._build_system_page()
            self._build_user_page()
            self._build_desktop_page()
            self._build_complete_page()

            self.current_page = 0
            self._update_nav()

        # ── Navigation ──
        def go_next(self):
            if self.current_page < self.pages.count() - 1:
                if self._validate_page(self.current_page):
                    self.current_page += 1
                    self._update_nav()
                    self._on_page_enter(self.current_page)

        def go_back(self):
            if self.current_page > 0:
                self.current_page -= 1
                self._update_nav()

        def _update_nav(self):
            self.pages.setCurrentIndex(self.current_page)
            self.step_label.setText(f"Step {self.current_page + 1}/{self.pages.count()}")
            self.btn_back.setVisible(self.current_page > 0)
            if self.current_page == self.pages.count() - 1:
                self.btn_next.setText("  Finish  ")
                self.btn_next.clicked.disconnect()
                self.btn_next.clicked.connect(self.close)
            else:
                self.btn_next.setText("  Next  ")
                try:
                    self.btn_next.clicked.disconnect()
                except TypeError:
                    pass
                self.btn_next.clicked.connect(self.go_next)

        def _validate_page(self, idx):
            return True

        def _on_page_enter(self, idx):
            pass

        # ── Page 0: Welcome ──
        def _build_welcome_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setAlignment(Qt.AlignCenter)
            layout.setSpacing(20)

            icon_label = QLabel("\u26a1")
            icon_label.setStyleSheet(f"font-size: 64px; color: {ACCENT};")
            icon_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(icon_label)

            name = QLabel("StormFS Linux")
            name.setStyleSheet(f"font-size: 32px; font-weight: bold; color: {ACCENT};")
            name.setAlignment(Qt.AlignCenter)
            layout.addWidget(name)

            subtitle = QLabel("Graphical Installer")
            subtitle.setStyleSheet(f"font-size: 16px; color: {TEXT};")
            subtitle.setAlignment(Qt.AlignCenter)
            layout.addWidget(subtitle)

            desc = QLabel(
                "This wizard will guide you through:\n\n"
                "  1. Building the StormFS toolchain and base system\n"
                "  2. Partitioning your target disk\n"
                "  3. Installing StormFS Linux\n"
                "  4. Configuring your desktop environment\n\n"
                "Click Next to begin."
            )
            desc.setStyleSheet(f"font-size: 13px; color: {TEXT}; line-height: 1.6;")
            desc.setAlignment(Qt.AlignCenter)
            layout.addWidget(desc)

            boot_info = QLabel(f"Detected boot mode: {self.config['boot_mode'].upper()}")
            boot_info.setStyleSheet(f"font-size: 12px; color: {YELLOW};")
            boot_info.setAlignment(Qt.AlignCenter)
            layout.addWidget(boot_info)

            self.pages.addWidget(page)
            self.page_names.append("Welcome")

        # ── Page 1: Build Settings ──
        def _build_settings_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Build Settings")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            desc = QLabel("Configure the compiler and build options for the StormFS toolchain and base system.")
            desc.setWordWrap(True)
            layout.addWidget(desc)

            # Build jobs
            g1 = QGroupBox("Build Parallelism")
            g1l = QHBoxLayout(g1)
            g1l.addWidget(QLabel("Make jobs:"))
            self.spin_jobs = QSpinBox()
            self.spin_jobs.setRange(1, 128)
            self.spin_jobs.setValue(os.cpu_count() or 4)
            self.spin_jobs.setSpecialValueText("auto")
            g1l.addWidget(self.spin_jobs)
            g1l.addStretch()
            layout.addWidget(g1)

            # Optimization
            g2 = QGroupBox("Optimization Level")
            g2l = QVBoxLayout(g2)
            self.opt_group = QButtonGroup()
            for i, (label, val) in enumerate([
                ("Portable (x86-64) - Recommended", "portable"),
                ("Native (-march=native) - Best for this machine only", "native"),
            ]):
                rb = QRadioButton(label)
                rb.setProperty("value", val)
                if val == "portable":
                    rb.setChecked(True)
                self.opt_group.addButton(rb, i)
                g2l.addWidget(rb)
            layout.addWidget(g2)

            # ccache
            g3 = QGroupBox("Compiler Cache")
            g3l = QVBoxLayout(g3)
            self.chk_ccache = QCheckBox("Enable ccache (speeds up rebuilds)")
            self.chk_ccache.setChecked(True)
            g3l.addWidget(self.chk_ccache)
            layout.addWidget(g3)

            # Skip build option
            g4 = QGroupBox("Build Options")
            g4l = QVBoxLayout(g4)
            self.chk_skip_build = QCheckBox("Skip build - use existing rootfs archive (if available)")
            g4l.addWidget(self.chk_skip_build)
            self.chk_rebuild = QCheckBox("Run full rebuild (stages 1-3) even if archive exists")
            g4l.addWidget(self.chk_rebuild)
            layout.addWidget(g4)

            layout.addStretch()
            self.pages.addWidget(page)
            self.page_names.append("Build Settings")

        # ── Page 2: Build Progress ──
        def _build_build_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Building StormFS")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            self.build_progress = QProgressBar()
            self.build_progress.setValue(0)
            layout.addWidget(self.build_progress)

            self.build_status = QLabel("Ready to build...")
            self.build_status.setStyleSheet(f"font-size: 13px; color: {YELLOW};")
            layout.addWidget(self.build_status)

            self.build_log = QTextEdit()
            self.build_log.setReadOnly(True)
            layout.addWidget(self.build_log)

            btn_row = QHBoxLayout()
            self.btn_start_build = QPushButton("  Start Build  ")
            self.btn_start_build.setObjectName("primary")
            self.btn_start_build.clicked.connect(self._start_build)
            btn_row.addWidget(self.btn_start_build)
            btn_row.addStretch()
            self.btn_stop_build = QPushButton("  Cancel  ")
            self.btn_stop_build.setObjectName("danger")
            self.btn_stop_build.setEnabled(False)
            self.btn_stop_build.clicked.connect(self._stop_build)
            btn_row.addWidget(self.btn_stop_build)
            layout.addLayout(btn_row)

            self.pages.addWidget(page)
            self.page_names.append("Build")

        def _start_build(self):
            self.config["build_jobs"] = self.spin_jobs.value()
            self.config["build_opt"] = self.opt_group.checkedButton().property("value") if self.opt_group.checkedButton() else "portable"
            self.config["ccache"] = self.chk_ccache.isChecked()

            self.btn_start_build.setEnabled(False)
            self.btn_stop_build.setEnabled(True)
            self.build_log.clear()

            if self.chk_skip_build.isChecked():
                self.build_status.setText("Skipping build, using existing archive...")
                QTimer.singleShot(1000, self._on_build_done_skip)
                return

            self.build_thread = BuildThread(self.config)
            self.build_thread.log_signal.connect(self._append_build_log)
            self.build_thread.progress_signal.connect(self._update_build_progress)
            self.build_thread.finished_signal.connect(self._on_build_finished)
            self.build_thread.start()

        def _on_build_done_skip(self):
            self.build_progress.setValue(100)
            self.build_status.setText("Build skipped - using existing rootfs archive")
            self.btn_next.setEnabled(True)

        def _stop_build(self):
            if self.build_thread and self.build_thread.isRunning():
                self.build_thread.stop()

        def _append_build_log(self, text):
            self.build_log.append(text)
            sb = self.build_log.verticalScrollBar()
            sb.setValue(sb.maximum())

        def _update_build_progress(self, pct, status):
            self.build_progress.setValue(pct)
            self.build_status.setText(status)

        def _on_build_finished(self, success, message):
            self.btn_start_build.setEnabled(True)
            self.btn_stop_build.setEnabled(False)
            if success:
                self.build_status.setText(f"\u2714 {message}")
                self.build_status.setStyleSheet(f"font-size: 13px; color: {GREEN};")
            else:
                self.build_status.setText(f"\u2718 {message}")
                self.build_status.setStyleSheet(f"font-size: 13px; color: {RED};")

        # ── Page 3: Disk Selection ──
        def _build_disk_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Select Target Disk")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            desc = QLabel("Choose the disk where StormFS Linux will be installed. WARNING: This will erase all data on the selected disk.")
            desc.setWordWrap(True)
            desc.setStyleSheet(f"color: {YELLOW};")
            layout.addWidget(desc)

            self.disk_combo = QComboBox()
            self.disk_combo.setMinimumHeight(40)
            self._refresh_disks_btn = QPushButton("  Refresh  ")
            self._refresh_disks_btn.clicked.connect(self._refresh_disks)
            disk_row = QHBoxLayout()
            disk_row.addWidget(self.disk_combo, 1)
            disk_row.addWidget(self._refresh_disks_btn)
            layout.addLayout(disk_row)

            self.disk_info = QLabel("")
            self.disk_info.setStyleSheet(f"font-size: 12px; color: {TEXT};")
            layout.addWidget(self.disk_info)

            self.disk_combo.currentIndexChanged.connect(self._on_disk_changed)

            layout.addStretch()
            self.pages.addWidget(page)
            self.page_names.append("Disk")
            self._refresh_disks()

        def _refresh_disks(self):
            self.disk_combo.clear()
            for name, size, model in get_block_devices():
                label = f"{name}  ({size})"
                if model:
                    label += f"  -  {model}"
                self.disk_combo.addItem(label, name)

        def _on_disk_changed(self, idx):
            if idx >= 0:
                dev = self.disk_combo.currentData()
                if dev:
                    parts = get_partitions(dev)
                    info = f"Device: {dev}"
                    if parts:
                        info += f"  |  {len(parts)} partition(s) found"
                    self.disk_info.setText(info)

        def _validate_page(self, idx):
            if idx == 3:  # disk page
                if self.disk_combo.count() == 0:
                    QMessageBox.warning(self, "No Disks", "No disks detected. Please insert a disk and click Refresh.")
                    return False
                self.config["target_disk"] = self.disk_combo.currentData()
            return True

        # ── Page 4: Partition Layout ──
        def _build_partition_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Partition Layout")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            tabs = QTabWidget()

            # ── Root tab ──
            root_tab = QWidget()
            root_layout = QVBoxLayout(root_tab)

            rg = QGroupBox("Root Partition (/)")
            rgl = QGridLayout(rg)
            rgl.addWidget(QLabel("Filesystem:"), 0, 0)
            self.combo_root_fs = QComboBox()
            self.combo_root_fs.addItems(["ext4", "ext3", "ext2", "btrfs", "xfs"])
            rgl.addWidget(self.combo_root_fs, 0, 1)
            root_layout.addWidget(rg)
            tabs.addTab(root_tab, "Root (/)")

            # ── Boot/EFI tab ──
            boot_tab = QWidget()
            boot_layout = QVBoxLayout(boot_tab)
            bg = QGroupBox("Boot Partition")
            bgl = QVBoxLayout(bg)

            self.chk_use_efi = QCheckBox("Create EFI System Partition (UEFI mode)")
            self.chk_use_efi.setChecked(self.config["boot_mode"] == "uefi")
            bgl.addWidget(self.chk_use_efi)

            efi_row = QHBoxLayout()
            efi_row.addWidget(QLabel("Size (MB):"))
            self.spin_efi_size = QSpinBox()
            self.spin_efi_size.setRange(100, 2048)
            self.spin_efi_size.setValue(512)
            efi_row.addWidget(self.spin_efi_size)
            efi_row.addStretch()
            bgl.addLayout(efi_row)

            self.chk_use_bios_boot = QCheckBox("Create BIOS boot partition (1MB, for GPT + BIOS)")
            self.chk_use_bios_boot.setChecked(self.config["boot_mode"] == "bios")
            bgl.addWidget(self.chk_use_bios_boot)

            boot_layout.addWidget(bg)
            tabs.addTab(boot_tab, "Boot")

            # ── Swap tab ──
            swap_tab = QWidget()
            swap_layout = QVBoxLayout(swap_tab)
            sg = QGroupBox("Swap")
            sgl = QVBoxLayout(sg)
            self.chk_use_swap = QCheckBox("Create swap partition")
            self.chk_use_swap.setChecked(True)
            sgl.addWidget(self.chk_use_swap)

            swap_row = QHBoxLayout()
            swap_row.addWidget(QLabel("Size (MB):"))
            self.spin_swap_size = QSpinBox()
            self.spin_swap_size.setRange(256, 32768)
            self.spin_swap_size.setValue(4096)
            swap_row.addWidget(self.spin_swap_size)
            swap_row.addWidget(QLabel("(0 = same as RAM)"))
            swap_row.addStretch()
            sgl.addLayout(swap_row)

            swap_layout.addWidget(sg)
            tabs.addTab(swap_tab, "Swap")

            # ── Home tab ──
            home_tab = QWidget()
            home_layout = QVBoxLayout(home_tab)
            hg = QGroupBox("Home Partition (/home)")
            hgl = QVBoxLayout(hg)
            self.chk_use_home = QCheckBox("Create separate /home partition")
            hgl.addWidget(self.chk_use_home)

            home_fs_row = QHBoxLayout()
            home_fs_row.addWidget(QLabel("Filesystem:"))
            self.combo_home_fs = QComboBox()
            self.combo_home_fs.addItems(["ext4", "btrfs", "xfs", "ext3", "ext2"])
            home_fs_row.addWidget(self.combo_home_fs)
            home_fs_row.addStretch()
            hgl.addLayout(home_fs_row)

            home_layout.addWidget(hg)
            tabs.addTab(home_tab, "Home")

            layout.addWidget(tabs)

            # Partitioning mode
            mode_group = QGroupBox("Partitioning Mode")
            mode_layout = QVBoxLayout(mode_group)
            self.radio_auto = QRadioButton("Automatic - let the installer partition the disk")
            self.radio_auto.setChecked(True)
            mode_layout.addWidget(self.radio_auto)
            self.radio_manual = QRadioButton("Manual - I will partition the disk myself before proceeding")
            mode_layout.addWidget(self.radio_manual)
            layout.addWidget(mode_group)

            layout.addStretch()
            self.pages.addWidget(page)
            self.page_names.append("Partition")

        # ── Page 5: System Config ──
        def _build_system_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("System Configuration")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            form = QGridLayout()
            form.setSpacing(12)

            form.addWidget(QLabel("Hostname:"), 0, 0)
            self.edit_hostname = QLineEdit("stormfs")
            form.addWidget(self.edit_hostname, 0, 1)

            form.addWidget(QLabel("Timezone:"), 1, 0)
            self.combo_tz = QComboBox()
            self.combo_tz.setEditable(True)
            tz_list = get_timezone_list()
            self.combo_tz.addItems(tz_list)
            idx = tz_list.index("America/New_York") if "America/New_York" in tz_list else 0
            self.combo_tz.setCurrentIndex(idx)
            form.addWidget(self.combo_tz, 1, 1)

            form.addWidget(QLabel("Locale:"), 2, 0)
            self.combo_locale = QComboBox()
            locale_list = get_locale_list()
            self.combo_locale.addItems(locale_list)
            idx = locale_list.index("en_US.UTF-8") if "en_US.UTF-8" in locale_list else 0
            self.combo_locale.setCurrentIndex(idx)
            form.addWidget(self.combo_locale, 2, 1)

            form.addWidget(QLabel("Keymap:"), 3, 0)
            self.combo_keymap = QComboBox()
            self.combo_keymap.setEditable(True)
            km_list = get_keymap_list()
            self.combo_keymap.addItems(km_list)
            idx = km_list.index("us") if "us" in km_list else 0
            self.combo_keymap.setCurrentIndex(idx)
            form.addWidget(self.combo_keymap, 3, 1)

            layout.addLayout(form)
            layout.addStretch()

            self.pages.addWidget(page)
            self.page_names.append("System")

        # ── Page 6: User Setup ──
        def _build_user_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("User Account")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            form = QGridLayout()
            form.setSpacing(12)

            form.addWidget(QLabel("Username:"), 0, 0)
            self.edit_username = QLineEdit()
            self.edit_username.setPlaceholderText("e.g. storm")
            form.addWidget(self.edit_username, 0, 1)

            form.addWidget(QLabel("Password:"), 1, 0)
            self.edit_password = QLineEdit()
            self.edit_password.setEchoMode(QLineEdit.Password)
            form.addWidget(self.edit_password, 1, 1)

            form.addWidget(QLabel("Confirm password:"), 2, 0)
            self.edit_password2 = QLineEdit()
            self.edit_password2.setEchoMode(QLineEdit.Password)
            form.addWidget(self.edit_password2, 2, 1)

            form.addWidget(QLabel("Root password:"), 3, 0)
            self.edit_rootpw = QLineEdit()
            self.edit_rootpw.setEchoMode(QLineEdit.Password)
            form.addWidget(self.edit_rootpw, 3, 1)

            form.addWidget(QLabel("Confirm root password:"), 4, 0)
            self.edit_rootpw2 = QLineEdit()
            self.edit_rootpw2.setEchoMode(QLineEdit.Password)
            form.addWidget(self.edit_rootpw2, 4, 1)

            layout.addLayout(form)
            layout.addStretch()

            self.pages.addWidget(page)
            self.page_names.append("User")

        def _validate_page(self, idx):
            if idx == 6:  # user page
                if not self.edit_username.text().strip():
                    QMessageBox.warning(self, "Missing Username", "Please enter a username.")
                    return False
                if self.edit_password.text() != self.edit_password2.text():
                    QMessageBox.warning(self, "Password Mismatch", "User passwords do not match.")
                    return False
                if len(self.edit_password.text()) < 1:
                    QMessageBox.warning(self, "Empty Password", "Please set a user password.")
                    return False
                if self.edit_rootpw.text() != self.edit_rootpw2.text():
                    QMessageBox.warning(self, "Password Mismatch", "Root passwords do not match.")
                    return False
                if len(self.edit_rootpw.text()) < 1:
                    QMessageBox.warning(self, "Empty Password", "Please set a root password.")
                    return False
            return True

        # ── Page 7: Desktop Selection ──
        def _build_desktop_page(self):
            page = QWidget()
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            inner = QWidget()
            layout = QVBoxLayout(inner)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Desktop Environment & Software")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            # Display Server
            ds_group = QGroupBox("Display Server")
            ds_layout = QVBoxLayout(ds_group)
            self.ds_group = QButtonGroup()
            for i, (label, val) in enumerate([
                ("Xorg - Traditional X11 display server", "xorg"),
                ("Wayland - Modern display protocol", "wayland"),
                ("Both Xorg and Wayland", "both"),
            ]):
                rb = QRadioButton(label)
                rb.setProperty("value", val)
                if val == "both":
                    rb.setChecked(True)
                self.ds_group.addButton(rb, i)
                ds_layout.addWidget(rb)
            layout.addWidget(ds_group)

            # Desktop Environment / Window Manager
            de_group = QGroupBox("Desktop Environment / Window Manager (select all desired)")
            de_layout = QVBoxLayout(de_group)
            self.de_checks = {}
            de_options = [
                ("XFCE - Lightweight, full desktop", "xfce", True),
                ("GNOME - Modern, feature-rich desktop", "gnome", False),
                ("KDE Plasma - Powerful, customizable desktop", "plasma", False),
                ("LXQt - Lightweight Qt desktop", "lxqt", False),
                ("Sway - i3-compatible Wayland compositor", "sway", False),
                ("i3 - Tiling window manager", "i3", False),
                ("Hyprland - Dynamic tiling Wayland compositor", "hyprland", False),
                ("Openbox - Stacking window manager", "openbox", False),
                ("Awesome - Window manager framework", "awesome", False),
                ("Bspwm - Tiling window manager", "bspwm", False),
                ("Cinnamon - Traditional desktop (Linux Mint)", "cinnamon", False),
                ("MATE - GNOME 2 fork desktop", "mate", False),
            ]
            for label, val, default in de_options:
                cb = QCheckBox(label)
                cb.setChecked(default)
                self.de_checks[val] = cb
                de_layout.addWidget(cb)
            layout.addWidget(de_group)

            # Audio
            audio_group = QGroupBox("Audio Server")
            audio_layout = QVBoxLayout(audio_group)
            self.audio_group = QButtonGroup()
            for i, (label, val) in enumerate([
                ("PipeWire - Modern audio server (Recommended)", "pipewire"),
                ("PulseAudio - Traditional audio server", "pulseaudio"),
            ]):
                rb = QRadioButton(label)
                rb.setProperty("value", val)
                if val == "pipewire":
                    rb.setChecked(True)
                self.audio_group.addButton(rb, i)
                audio_layout.addWidget(rb)
            layout.addWidget(audio_group)

            # GPU Drivers
            gpu_group = QGroupBox("GPU Drivers")
            gpu_layout = QVBoxLayout(gpu_group)
            self.gpu_checks = {}
            gpu_options = [
                ("Mesa (AMD/Intel - open source)", "mesa", True),
                ("NVIDIA (proprietary driver)", "nvidia", False),
                ("NVIDIA (open-source Nouveau)", "nouveau", False),
                ("VirtualBox guest additions", "virtualbox", False),
                ("VMware guest tools", "vmware", False),
            ]
            for label, val, default in gpu_options:
                cb = QCheckBox(label)
                cb.setChecked(default)
                self.gpu_checks[val] = cb
                gpu_layout.addWidget(cb)
            layout.addWidget(gpu_group)

            # Themes
            theme_group = QGroupBox("Themes & Appearance")
            theme_layout = QVBoxLayout(theme_group)
            self.theme_checks = {}
            theme_options = [
                ("adw-gtk3 - GTK theme (from submodule)", "adw-gtk3", True),
                ("Tela icon theme (from submodule)", "tela-icons", True),
                ("Tela Circle icon theme (from submodule)", "tela-circle-icons", False),
                ("oh-my-bash shell config (from submodule)", "oh-my-bash", True),
                ("StormFS GRUB bootloader theme", "stormfs-grub", True),
                ("LightDM GTK Greeter", "lightdm-gtk", True),
            ]
            for label, val, default in theme_options:
                cb = QCheckBox(label)
                cb.setChecked(default)
                self.theme_checks[val] = cb
                theme_layout.addWidget(cb)
            layout.addWidget(theme_group)

            # Additional Software
            extra_group = QGroupBox("Additional Software")
            extra_layout = QVBoxLayout(extra_group)
            self.extra_checks = {}
            extra_options = [
                ("Git - Version control", "git", True),
                ("Sudo - Root privilege management", "sudo", True),
                ("OpenSSH - Remote access", "openssh", True),
                ("NetworkManager - Network management", "networkmanager", True),
                ("Firefox - Web browser", "firefox", True),
                ("HTOP - Process monitor", "htop", False),
                ("Neofetch - System info display", "neofetch", False),
                ("Vim - Text editor", "vim", True),
                ("Nano - Text editor", "nano", True),
                ("Curl - URL transfer tool", "curl", True),
                ("Wget - Network downloader", "wget", True),
                ("GPM - Console mouse support", "gpm", False),
            ]
            for label, val, default in extra_options:
                cb = QCheckBox(label)
                cb.setChecked(default)
                self.extra_checks[val] = cb
                extra_layout.addWidget(cb)
            layout.addWidget(extra_group)

            layout.addStretch()
            scroll.setWidget(inner)
            page_layout = QVBoxLayout(page)
            page_layout.setContentsMargins(0, 0, 0, 0)
            page_layout.addWidget(scroll)
            self.pages.addWidget(page)
            self.page_names.append("Desktop")

        # ── Page 8: Complete ──
        def _build_complete_page(self):
            page = QWidget()
            layout = QVBoxLayout(page)
            layout.setContentsMargins(40, 30, 40, 30)
            layout.setSpacing(16)

            heading = QLabel("Install StormFS Linux")
            heading.setStyleSheet(f"font-size: 22px; font-weight: bold; color: {ACCENT};")
            layout.addWidget(heading)

            summary_scroll = QScrollArea()
            summary_scroll.setWidgetResizable(True)
            self.summary_label = QLabel()
            self.summary_label.setWordWrap(True)
            self.summary_label.setStyleSheet(f"font-size: 13px; color: {TEXT}; line-height: 1.5;")
            summary_scroll.setWidget(self.summary_label)
            layout.addWidget(summary_scroll)

            self.install_progress = QProgressBar()
            self.install_progress.setValue(0)
            layout.addWidget(self.install_progress)

            self.install_status = QLabel("Ready to install.")
            self.install_status.setStyleSheet(f"font-size: 13px; color: {YELLOW};")
            layout.addWidget(self.install_status)

            self.install_log = QTextEdit()
            self.install_log.setReadOnly(True)
            self.install_log.setMaximumHeight(200)
            layout.addWidget(self.install_log)

            btn_row = QHBoxLayout()
            self.btn_install = QPushButton("  Install Now  ")
            self.btn_install.setObjectName("primary")
            self.btn_install.clicked.connect(self._start_install)
            btn_row.addWidget(self.btn_install)
            btn_row.addStretch()
            self.btn_stop_install = QPushButton("  Cancel  ")
            self.btn_stop_install.setObjectName("danger")
            self.btn_stop_install.setEnabled(False)
            self.btn_stop_install.clicked.connect(self._stop_install)
            btn_row.addWidget(self.btn_stop_install)
            layout.addLayout(btn_row)

            self.pages.addWidget(page)
            self.page_names.append("Install")

        def _on_page_enter(self, idx):
            if idx == 7:
                self._update_summary()
                self.btn_next.setEnabled(False)
            elif idx == 2:
                self.btn_next.setEnabled(True)

        def _update_summary(self):
            # Collect all settings
            self.config["hostname"] = self.edit_hostname.text().strip() or "stormfs"
            self.config["timezone"] = self.combo_tz.currentText()
            self.config["locale"] = self.combo_locale.currentText()
            self.config["keymap"] = self.combo_keymap.currentText()
            self.config["username"] = self.edit_username.text().strip()
            self.config["user_password"] = self.edit_password.text()
            self.config["root_password"] = self.edit_rootpw.text()
            self.config["root_fs"] = self.combo_root_fs.currentText()
            self.config["use_efi"] = self.chk_use_efi.isChecked()
            self.config["use_swap"] = self.chk_use_swap.isChecked()
            self.config["use_home"] = self.chk_use_home.isChecked()
            self.config["auto_partition"] = self.radio_auto.isChecked()

            # Desktop selections
            self.config["display_server"] = self.ds_group.checkedButton().property("value") if self.ds_group.checkedButton() else "both"
            self.config["desktops"] = [v for v, cb in self.de_checks.items() if cb.isChecked()]
            self.config["audio"] = self.audio_group.checkedButton().property("value") if self.audio_group.checkedButton() else "pipewire"
            self.config["gpu_drivers"] = [v for v, cb in self.gpu_checks.items() if cb.isChecked()]
            self.config["themes"] = [v for v, cb in self.theme_checks.items() if cb.isChecked()]
            self.config["extra_software"] = [v for v, cb in self.extra_checks.items() if cb.isChecked()]

            # Build summary text
            lines = [
                f"<b>Target Disk:</b> {self.config.get('target_disk', 'Not selected')}",
                f"<b>Root Filesystem:</b> {self.config['root_fs']}",
                f"<b>Boot Mode:</b> {self.config['boot_mode'].upper()}",
                f"<b>EFI Partition:</b> {'Yes' if self.config.get('use_efi') else 'No'}",
                f"<b>Swap:</b> {'Yes' if self.config.get('use_swap') else 'No'}",
                f"<b>Separate /home:</b> {'Yes' if self.config.get('use_home') else 'No'}",
                "",
                f"<b>Hostname:</b> {self.config['hostname']}",
                f"<b>Timezone:</b> {self.config['timezone']}",
                f"<b>Locale:</b> {self.config['locale']}",
                f"<b>Keymap:</b> {self.config['keymap']}",
                f"<b>Username:</b> {self.config['username']}",
                "",
                f"<b>Display Server:</b> {self.config['display_server']}",
                f"<b>Desktop(s):</b> {', '.join(self.config['desktops']) or 'None'}",
                f"<b>Audio:</b> {self.config['audio']}",
                f"<b>GPU Drivers:</b> {', '.join(self.config['gpu_drivers']) or 'None'}",
                f"<b>Themes:</b> {', '.join(self.config['themes']) or 'None'}",
                f"<b>Extra Software:</b> {', '.join(self.config['extra_software']) or 'None'}",
                "",
                "<b style='color: #f38ba8;'>WARNING: All data on the target disk will be erased!</b>",
            ]
            self.summary_label.setText("<br>".join(lines))

        def _start_install(self):
            reply = QMessageBox.question(
                self, "Confirm Installation",
                "All data on the selected disk will be PERMANENTLY ERASED.\n\n"
                "Are you sure you want to continue?",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No
            )
            if reply != QMessageBox.Yes:
                return

            self.btn_install.setEnabled(False)
            self.btn_stop_install.setEnabled(True)
            self.install_log.clear()

            self.install_thread = InstallThread(self.config)
            self.install_thread.log_signal.connect(self._append_install_log)
            self.install_thread.progress_signal.connect(self._update_install_progress)
            self.install_thread.finished_signal.connect(self._on_install_finished)
            self.install_thread.start()

        def _stop_install(self):
            if self.install_thread and self.install_thread.isRunning():
                self.install_thread.stop()

        def _append_install_log(self, text):
            self.install_log.append(text)
            sb = self.install_log.verticalScrollBar()
            sb.setValue(sb.maximum())

        def _update_install_progress(self, pct, status):
            self.install_progress.setValue(pct)
            self.install_status.setText(status)

        def _on_install_finished(self, success, message):
            self.btn_install.setEnabled(False)
            self.btn_stop_install.setEnabled(False)
            if success:
                self.install_status.setText(f"\u2714 {message}")
                self.install_status.setStyleSheet(f"font-size: 13px; color: {GREEN};")
                self.btn_next.setEnabled(True)
                QMessageBox.information(
                    self, "Installation Complete",
                    "StormFS Linux has been installed successfully!\n\n"
                    "You can now reboot into your new system.\n"
                    "On first login, the desktop software selector will appear."
                )
            else:
                self.install_status.setText(f"\u2718 {message}")
                self.install_status.setStyleSheet(f"font-size: 13px; color: {RED};")
                QMessageBox.critical(self, "Installation Failed", message)

    # ═══════════════════════════════════════════════════════════════════════
    # Create and show
    # ═══════════════════════════════════════════════════════════════════════
    window = StormFSInstaller()
    window.show()
    return app, window

###############################################################################
# Main entry point
###############################################################################

def main():
    # Ensure we have root for installation operations
    if os.geteuid() != 0:
        print("[StormFS] Installer requires root. Re-launching with sudo...")
        try:
            subprocess.check_call(
                ["sudo", sys.executable] + sys.argv
            )
            sys.exit(0)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("[StormFS] Failed to obtain root. Please run with sudo.")
            sys.exit(1)

    if not ensure_pyqt5():
        sys.exit(1)

    ensure_system_deps()

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app, window = build_app()
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
