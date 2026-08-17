#!/usr/bin/env python3
"""StormFS Port Manager - A PyQt5 GUI frontend for prt-get package management."""

import os
import sys
import subprocess
import re
import glob as globmod
from pathlib import Path

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QTableWidget, QTableWidgetItem, QHeaderView, QPushButton,
    QLineEdit, QLabel, QTextEdit, QProgressBar, QStatusBar, QTreeWidget,
    QTreeWidgetItem, QSplitter, QDialog, QFormLayout, QGroupBox,
    QMessageBox, QToolBar, QAction, QComboBox, QCheckBox, QFrame,
    QPlainTextEdit, QSizePolicy, QAbstractItemView, QSpinBox,
)
from PyQt5.QtCore import (
    Qt, QThread, pyqtSignal, pyqtSlot, QSize, QTimer, QProcess,
)
from PyQt5.QtGui import (
    QFont, QIcon, QColor, QPalette, QPixmap, QPainter,
)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

STORMFS_VERSION = "1.0"
REPO_BASE = "/usr/ports"
REPO_CATEGORIES = [
    "core", "opt", "contrib", "xorg", "xfce",
    "gnome", "plasma", "lxqt", "compiz",
]

STYLESHEET = """
QMainWindow, QDialog {
    background-color: #1e1e2e;
}
QWidget {
    background-color: #1e1e2e;
    color: #cdd6f4;
    font-family: "Segoe UI", "Noto Sans", sans-serif;
    font-size: 13px;
}
QTabWidget::pane {
    border: 1px solid #313244;
    border-radius: 6px;
    background-color: #1e1e2e;
    top: -1px;
}
QTabBar::tab {
    background-color: #181825;
    color: #a6adc8;
    padding: 10px 22px;
    margin-right: 2px;
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    border: 1px solid #313244;
    border-bottom: none;
    min-width: 100px;
}
QTabBar::tab:selected {
    background-color: #1e1e2e;
    color: #89b4fa;
    border-bottom: 2px solid #89b4fa;
}
QTabBar::tab:hover:!selected {
    background-color: #313244;
    color: #cdd6f4;
}
QTableWidget {
    background-color: #181825;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
    gridline-color: #313244;
    selection-background-color: #45475a;
    selection-color: #cdd6f4;
    font-size: 13px;
}
QTableWidget::item {
    padding: 6px 8px;
    border: none;
}
QTableWidget::item:selected {
    background-color: #45475a;
}
QHeaderView::section {
    background-color: #181825;
    color: #a6adc8;
    padding: 8px 12px;
    border: none;
    border-right: 1px solid #313244;
    border-bottom: 2px solid #313244;
    font-weight: bold;
    font-size: 13px;
}
QPushButton {
    background-color: #89b4fa;
    color: #1e1e2e;
    border: none;
    border-radius: 6px;
    padding: 8px 18px;
    font-weight: bold;
    font-size: 13px;
    min-height: 18px;
}
QPushButton:hover {
    background-color: #b4d0fb;
}
QPushButton:pressed {
    background-color: #74a8f7;
}
QPushButton:disabled {
    background-color: #45475a;
    color: #6c7086;
}
QPushButton#dangerBtn {
    background-color: #f38ba8;
}
QPushButton#dangerBtn:hover {
    background-color: #f5a0bc;
}
QPushButton#secondaryBtn {
    background-color: #313244;
    color: #cdd6f4;
}
QPushButton#secondaryBtn:hover {
    background-color: #45475a;
}
QLineEdit {
    background-color: #181825;
    color: #cdd6f4;
    border: 2px solid #313244;
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 14px;
    selection-background-color: #45475a;
}
QLineEdit:focus {
    border: 2px solid #89b4fa;
}
QLineEdit::placeholder {
    color: #6c7086;
}
QPlainTextEdit, QTextEdit {
    background-color: #11111b;
    color: #a6e3a1;
    border: 1px solid #313244;
    border-radius: 6px;
    padding: 8px;
    font-family: "Cascadia Code", "Fira Code", "Consolas", monospace;
    font-size: 13px;
    selection-background-color: #45475a;
}
QProgressBar {
    background-color: #313244;
    border: none;
    border-radius: 4px;
    text-align: center;
    color: #cdd6f4;
    font-weight: bold;
    min-height: 8px;
    max-height: 8px;
}
QProgressBar::chunk {
    background-color: #89b4fa;
    border-radius: 4px;
}
QTreeWidget {
    background-color: #181825;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
    padding: 4px;
    font-size: 13px;
    outline: none;
}
QTreeWidget::item {
    padding: 5px 6px;
    border: none;
}
QTreeWidget::item:selected {
    background-color: #45475a;
    color: #cdd6f4;
}
QTreeWidget::item:hover:!selected {
    background-color: #313244;
}
QTreeWidget::branch {
    background-color: #181825;
}
QStatusBar {
    background-color: #181825;
    color: #a6adc8;
    border-top: 1px solid #313244;
    font-size: 12px;
    padding: 4px 10px;
}
QToolBar {
    background-color: #11111b;
    border-bottom: 1px solid #313244;
    spacing: 6px;
    padding: 6px;
}
QToolBar QToolButton {
    background-color: #313244;
    color: #cdd6f4;
    border: none;
    border-radius: 6px;
    padding: 8px 14px;
    font-weight: bold;
    font-size: 12px;
}
QToolBar QToolButton:hover {
    background-color: #45475a;
}
QToolBar QToolButton:pressed {
    background-color: #89b4fa;
    color: #1e1e2e;
}
QComboBox {
    background-color: #181825;
    color: #cdd6f4;
    border: 2px solid #313244;
    border-radius: 6px;
    padding: 6px 10px;
    font-size: 13px;
    min-width: 120px;
}
QComboBox:hover {
    border: 2px solid #45475a;
}
QComboBox::drop-down {
    border: none;
    width: 24px;
}
QComboBox QAbstractItemView {
    background-color: #181825;
    color: #cdd6f4;
    border: 1px solid #313244;
    selection-background-color: #45475a;
    padding: 4px;
}
QCheckBox {
    spacing: 8px;
    font-size: 13px;
    color: #cdd6f4;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
    border: 2px solid #45475a;
    border-radius: 4px;
    background-color: #181825;
}
QCheckBox::indicator:checked {
    background-color: #89b4fa;
    border-color: #89b4fa;
}
QCheckBox::indicator:hover {
    border-color: #89b4fa;
}
QGroupBox {
    border: 1px solid #313244;
    border-radius: 8px;
    margin-top: 14px;
    padding: 16px 12px 12px 12px;
    font-weight: bold;
    color: #a6adc8;
}
QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    padding: 2px 10px;
    color: #89b4fa;
}
QLabel#titleLabel {
    font-size: 16px;
    font-weight: bold;
    color: #89b4fa;
}
QLabel#headerLabel {
    font-size: 20px;
    font-weight: bold;
    color: #cdd6f4;
}
QLabel#installedLabel {
    color: #a6e3a1;
    font-weight: bold;
}
QLabel#notInstalledLabel {
    color: #f38ba8;
    font-weight: bold;
}
QSplitter::handle {
    background-color: #313244;
    height: 2px;
}
QScrollBar:vertical {
    background-color: #181825;
    width: 10px;
    border-radius: 5px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background-color: #45475a;
    border-radius: 5px;
    min-height: 30px;
}
QScrollBar::handle:vertical:hover {
    background-color: #585b70;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
}
QScrollBar:horizontal {
    background-color: #181825;
    height: 10px;
    border-radius: 5px;
}
QScrollBar::handle:horizontal {
    background-color: #45475a;
    border-radius: 5px;
    min-width: 30px;
}
QScrollBar::handle:horizontal:hover {
    background-color: #585b70;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
    width: 0px;
}
QMessageBox {
    background-color: #1e1e2e;
}
QMessageBox QLabel {
    color: #cdd6f4;
}
"""


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def run_cmd(cmd, timeout=30):
    """Run a command and return (stdout, stderr, returncode)."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout,
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Command timed out", -1
    except Exception as e:
        return "", str(e), -1


def is_package_installed(name):
    """Check if a package is installed via pkginfo."""
    out, _, rc = run_cmd(f"pkginfo -i {name} 2>/dev/null")
    return rc == 0 and "not installed" not in out.lower()


def get_installed_packages():
    """Return a dict of {name: version} for installed packages."""
    pkgs = {}
    out, _, rc = run_cmd("pkginfo -i 2>/dev/null")
    if rc != 0:
        return pkgs
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        # pkginfo -i output: "package-version"
        if "-" in line:
            # package names can have hyphens, version is after last hyphen
            # Actually pkginfo -i gives "name version" or "name-version"
            parts = line.rsplit("-", 1)
            if len(parts) == 2:
                pkgs[parts[0]] = parts[1]
    return pkgs


def parse_repo_ports(repo_base=REPO_BASE):
    """Parse REPO files from all categories and return a list of port dicts."""
    ports = []
    for cat in REPO_CATEGORIES:
        repo_file = os.path.join(repo_base, cat, "REPO")
        if not os.path.isfile(repo_file):
            continue
        current = None
        with open(repo_file, "r", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("#") or not line.strip():
                    continue
                if line.startswith(" ") or line.startswith("\t"):
                    # continuation of previous field
                    if current is not None:
                        key = line.strip().split(":")[0] if ":" in line.strip() else ""
                        if key == "desc" or (current and "description" not in current):
                            pass
                # Format: key: value
                if ":" in line:
                    key, _, val = line.partition(":")
                    key = key.strip().lower()
                    val = val.strip()
                    if key == "ver" or key == "version":
                        if current is None:
                            current = {}
                        current["version"] = val
                        current.setdefault("category", cat)
                    elif key == "desc" or key == "description":
                        if current is None:
                            current = {}
                        current["description"] = val
                    elif key == "url":
                        if current is None:
                            current = {}
                        current["url"] = val
                    elif key == "depend" or key == "deps":
                        if current is None:
                            current = {}
                        current.setdefault("dependencies", [])
                        if val:
                            current["dependencies"].append(val)
                else:
                    # No colon — this is the port name line (first non-empty, non-comment line)
                    if current is not None and "name" not in current:
                        current["name"] = val if val else line.strip()
                    if current is not None and "name" in current:
                        ports.append(current)
                        current = None
                    name = line.strip()
                    if name:
                        current = {"name": name, "category": cat}
            # flush last entry in file
            if current is not None and "name" in current:
                ports.append(current)
    return ports


def parse_repo_ports_simple(repo_base=REPO_DIR if False else REPO_BASE):
    """Simpler REPO parser that handles StormFS REPO format.

    Each REPO file is a flat list of entries. Each entry is a block:
        package_name
        ver: version
        desc: description
        url: url
        depend: dep1
        depend: dep2

    Blank lines separate entries.
    """
    ports = []
    for cat in REPO_CATEGORIES:
        repo_file = os.path.join(REPO_BASE, cat, "REPO")
        if not os.path.isfile(repo_file):
            continue
        with open(repo_file, "r", errors="replace") as f:
            content = f.read()
        blocks = re.split(r"\n\n+", content)
        for block in blocks:
            block = block.strip()
            if not block or block.startswith("#"):
                continue
            lines = block.splitlines()
            port = {"category": cat, "dependencies": []}
            first = True
            for ln in lines:
                ln = ln.rstrip()
                if ln.startswith("#"):
                    continue
                m = re.match(r"^(\w[\w-]*)\s*:\s*(.*)$", ln)
                if m:
                    key = m.group(1).lower()
                    val = m.group(2).strip()
                    if key in ("ver", "version"):
                        port["version"] = val
                    elif key in ("desc", "description"):
                        port["description"] = val
                    elif key == "url":
                        port["url"] = val
                    elif key in ("depend", "deps"):
                        if val:
                            port["dependencies"].append(val)
                elif first:
                    name = ln.strip()
                    if name:
                        port["name"] = name
                        first = False
            if "name" in port:
                ports.append(port)
    return ports


# We expose a single function to use
def get_port_database():
    """Get the full port database, trying simple parser first."""
    ports = parse_repo_ports_simple()
    if not ports:
        ports = parse_repo_ports()
    return ports


# ---------------------------------------------------------------------------
# Worker threads
# ---------------------------------------------------------------------------

class CommandWorker(QThread):
    """Run a single shell command in a background thread."""
    output = pyqtSignal(str)
    error = pyqtSignal(str)
    finished = pyqtSignal(int, str, str)  # returncode, stdout, stderr
    progress = pyqtSignal(int)

    def __init__(self, cmd, timeout=600, parent=None):
        super().__init__(parent)
        self.cmd = cmd
        self.timeout = timeout
        self._process = None
        self._cancelled = False

    def run(self):
        self.output.emit(f"$ {self.cmd}\n")
        try:
            self._process = subprocess.Popen(
                self.cmd, shell=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True,
            )
            buf = []
            while True:
                if self._cancelled:
                    self._process.kill()
                    self.error.emit("\n[Operation cancelled]\n")
                    self.finished.emit(-1, "", "cancelled")
                    return
                line = self._process.stdout.readline()
                if not line and self._process.poll() is not None:
                    break
                if line:
                    buf.append(line)
                    self.output.emit(line)
            rc = self._process.wait(timeout=self.timeout)
            stdout = "".join(buf)
            self.finished.emit(rc, stdout, "")
        except subprocess.TimeoutExpired:
            if self._process:
                self._process.kill()
            self.error.emit("\n[Timed out]\n")
            self.finished.emit(-1, "", "timed out")
        except Exception as e:
            self.error.emit(f"\n[Error: {e}]\n")
            self.finished.emit(-1, "", str(e))

    def cancel(self):
        self._cancelled = True


class LoadPortsWorker(QThread):
    """Load the port database in a background thread."""
    portsLoaded = pyqtSignal(list)
    progress = pyqtSignal(str)

    def run(self):
        self.progress.emit("Scanning ports database...")
        ports = get_port_database()
        self.progress.emit(f"Found {len(ports)} ports")
        self.portsLoaded.emit(ports)


class LoadInstalledWorker(QThread):
    """Load installed packages in a background thread."""
    loaded = pyqtSignal(dict)
    progress = pyqtSignal(str)

    def run(self):
        self.progress.emit("Loading installed packages...")
        pkgs = get_installed_packages()
        self.progress.emit(f"{len(pkgs)} packages installed")
        self.loaded.emit(pkgs)


class SyncWorker(QThread):
    """Sync the ports tree database."""
    output = pyqtSignal(str)
    finished = pyqtSignal(int)

    def run(self):
        self.output.emit("Syncing ports database...\n")
        proc = subprocess.Popen(
            "prt-get update 2>&1 || true", shell=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        while True:
            line = proc.stdout.readline()
            if not line and proc.poll() is not None:
                break
            if line:
                self.output.emit(line)
        rc = proc.wait()
        self.output.emit("\nSync complete.\n")
        self.finished.emit(rc)


# ---------------------------------------------------------------------------
# Details dialog
# ---------------------------------------------------------------------------

class PortDetailsDialog(QDialog):
    """Dialog showing detailed information about a port."""

    def __init__(self, port_info, installed_map, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"Port Details — {port_info.get('name', 'Unknown')}")
        self.setMinimumSize(600, 500)
        self.setModal(True)
        self.port = port_info
        self.installed_map = installed_map
        self._build_ui()
        self._populate()

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(20, 20, 20, 20)

        self.name_label = QLabel()
        self.name_label.setObjectName("headerLabel")
        layout.addWidget(self.name_label)

        info_group = QGroupBox("Information")
        info_layout = QFormLayout()
        self.ver_label = QLabel()
        self.cat_label = QLabel()
        self.url_label = QLabel()
        self.status_label = QLabel()
        self.desc_label = QLabel()
        self.desc_label.setWordWrap(True)
        info_layout.addRow("Name:", self.ver_label)
        info_layout.addRow("Category:", self.cat_label)
        info_layout.addRow("URL:", self.url_label)
        info_layout.addRow("Status:", self.status_label)
        info_layout.addRow("Description:", self.desc_label)
        info_group.setLayout(info_layout)
        layout.addWidget(info_group)

        deps_group = QGroupBox("Dependencies")
        deps_layout = QVBoxLayout()
        self.deps_text = QPlainTextEdit()
        self.deps_text.setReadOnly(True)
        self.deps_text.setMaximumHeight(120)
        deps_layout.addWidget(self.deps_text)
        deps_group.setLayout(deps_layout)
        layout.addWidget(deps_group)

        files_group = QGroupBox("Installed Files (if applicable)")
        files_layout = QVBoxLayout()
        self.files_text = QPlainTextEdit()
        self.files_text.setReadOnly(True)
        self.files_text.setMaximumHeight(150)
        files_layout.addWidget(self.files_text)
        files_group.setLayout(files_layout)
        layout.addWidget(files_group)

        btn_layout = QHBoxLayout()
        self.install_btn = QPushButton("Build && Install")
        self.remove_btn = QPushButton("Remove")
        self.remove_btn.setObjectName("dangerBtn")
        self.update_btn = QPushButton("Update")
        self.close_btn = QPushButton("Close")
        self.close_btn.setObjectName("secondaryBtn")
        btn_layout.addWidget(self.install_btn)
        btn_layout.addWidget(self.remove_btn)
        btn_layout.addWidget(self.update_btn)
        btn_layout.addStretch()
        btn_layout.addWidget(self.close_btn)
        layout.addLayout(btn_layout)

        self.close_btn.clicked.connect(self.accept)

    def _populate(self):
        p = self.port
        name = p.get("name", "?")
        self.name_label.setText(f"  {name}")
        self.ver_label.setText(p.get("version", "N/A"))
        self.cat_label.setText(p.get("category", "N/A"))
        url = p.get("url", "N/A")
        self.url_label.setText(url)
        if url != "N/A":
            self.url_label.setOpenExternalLinks(True)
            self.url_label.setText(f'<a href="{url}" style="color:#89b4fa">{url}</a>')
        self.desc_label.setText(p.get("description", ""))
        installed = name in self.installed_map
        if installed:
            self.status_label.setText(f"Installed (v{self.installed_map.get(name, '?')})")
            self.status_label.setObjectName("installedLabel")
        else:
            self.status_label.setText("Not installed")
            self.status_label.setObjectName("notInstalledLabel")
        self.status_label.setStyleSheet("")
        self.status_label.style().unpolish(self.status_label)
        self.status_label.style().polish(self.status_label)

        deps = p.get("dependencies", [])
        self.deps_text.setPlainText("\n".join(deps) if deps else "No dependencies listed")

        if installed:
            self.files_text.setPlainText("Loading file list...")
            self._load_files(name)
        else:
            self.files_text.setPlainText("Package not installed — no file list available.")

    def _load_files(self, name):
        out, err, rc = run_cmd(f"pkginfo -li {name} 2>/dev/null", timeout=15)
        if rc == 0 and out:
            self.files_text.setPlainText(out)
        else:
            self.files_text.setPlainText("Could not retrieve file list.")


# ---------------------------------------------------------------------------
# Main Window
# ---------------------------------------------------------------------------

class PortManagerWindow(QMainWindow):

    def __init__(self):
        super().__init__()
        self.setWindowTitle("StormFS Port Manager")
        self.setMinimumSize(1000, 700)
        self.resize(1100, 750)

        self._set_icon()
        self.ports_db = []
        self.installed_map = {}
        self._workers = []
        self._cmd_worker = None

        self._build_ui()
        self._load_data()

    # ---- icon ----

    def _set_icon(self):
        """Try to load a system package icon, fallback to built-in."""
        icon_paths = [
            "/usr/share/icons/hicolor/48x48/apps/package-x-generic.png",
            "/usr/share/icons/hicolor/48x48/apps/system-software-install.png",
            "/usr/share/pixmaps/package-x-generic.png",
            "/usr/share/icons/Adwaita/48x48/devices/drive-multidisk.png",
        ]
        for p in icon_paths:
            if os.path.isfile(p):
                self.setWindowIcon(QIcon(p))
                return
        # Create a tiny pixmap icon as fallback
        pm = QPixmap(48, 48)
        pm.fill(QColor("#89b4fa"))
        painter = QPainter(pm)
        painter.setPen(QColor("#1e1e2e"))
        painter.setFont(QFont("Arial", 20, QFont.Bold))
        painter.drawText(pm.rect(), Qt.AlignCenter, "P")
        painter.end()
        self.setWindowIcon(QIcon(pm))

    # ---- UI ----

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Toolbar
        self._build_toolbar(main_layout)

        # Tab widget
        self.tabs = QTabWidget()
        self.tabs.setTabPosition(QTabWidget.North)
        main_layout.addWidget(self.tabs)

        self._build_search_tab()
        self._build_browse_tab()
        self._build_installed_tab()
        self._build_log_tab()

        # Status bar
        self.statusBar().showMessage("Ready")
        self.progress_bar = QProgressBar()
        self.progress_bar.setMaximumWidth(200)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.hide()
        self.statusBar().addPermanentWidget(self.progress_bar)

    def _build_toolbar(self, parent_layout):
        toolbar = QToolBar()
        toolbar.setIconSize(QSize(20, 20))
        toolbar.setMovable(False)

        def add_action(text, slot, tooltip=""):
            a = QAction(text, self)
            a.triggered.connect(slot)
            if tooltip:
                a.setToolTip(tooltip)
            toolbar.addAction(a)

        add_action("⟳ Sync", self._sync_ports, "Sync ports database")
        add_action("⬆ Sysup", self._sysup, "System update")
        add_action("⬇ Install", self._install_selected, "Install selected port(s)")
        add_action("✕ Remove", self._remove_selected, "Remove selected port(s)")
        add_action("↑ Update", self._update_selected, "Update selected port(s)")
        add_action("⟳ Update All", self._update_all, "Update all installed packages")
        add_action("⚠ Orphans", self._find_orphans, "Search for orphan packages")
        add_action("清扫 Clean", self._clean_cache, "Clean package cache")

        parent_layout.addWidget(toolbar)

    # ---- Search Tab ----

    def _build_search_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(16, 12, 16, 12)
        layout.setSpacing(10)

        row = QHBoxLayout()
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Search ports by name or description...")
        self.search_input.returnPressed.connect(self._do_search)
        search_btn = QPushButton("Search")
        search_btn.clicked.connect(self._do_search)
        row.addWidget(self.search_input)
        row.addWidget(search_btn)
        layout.addLayout(row)

        self.search_table = QTableWidget()
        self.search_table.setColumnCount(4)
        self.search_table.setHorizontalHeaderLabels(["Name", "Version", "Description", "Installed"])
        self.search_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.search_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.search_table.horizontalHeader().setSectionResizeMode(2, QHeaderView.Stretch)
        self.search_table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.search_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.search_table.setAlternatingRowColors(False)
        self.search_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.search_table.doubleClicked.connect(self._search_double_click)
        layout.addWidget(self.search_table)

        self.tabs.addTab(tab, "🔍 Search")

    # ---- Browse Tab ----

    def _build_browse_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(16, 12, 16, 12)
        layout.setSpacing(10)

        row = QHBoxLayout()
        row.addWidget(QLabel("Filter:"))
        self.browse_filter = QLineEdit()
        self.browse_filter.setPlaceholderText("Filter ports...")
        self.browse_filter.textChanged.connect(self._filter_browse)
        row.addWidget(self.browse_filter)
        self.browse_category = QComboBox()
        self.browse_category.addItem("All Categories")
        for cat in REPO_CATEGORIES:
            self.browse_category.addItem(cat)
        self.browse_category.currentTextChanged.connect(self._filter_browse)
        row.addWidget(self.browse_category)
        layout.addLayout(row)

        self.browse_tree = QTreeWidget()
        self.browse_tree.setHeaderLabels(["Name", "Version", "Description", "Category"])
        self.browse_tree.setRootIsDecorated(True)
        self.browse_tree.setColumnCount(4)
        self.browse_tree.header().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.browse_tree.header().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.browse_tree.header().setSectionResizeMode(2, QHeaderView.Stretch)
        self.browse_tree.header().setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.browse_tree.setAlternatingRowColors(False)
        self.browse_tree.itemDoubleClicked.connect(self._browse_double_click)
        layout.addWidget(self.browse_tree)

        self.tabs.addTab(tab, "📂 Browse")

    # ---- Installed Tab ----

    def _build_installed_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(16, 12, 16, 12)
        layout.setSpacing(10)

        row = QHBoxLayout()
        self.installed_filter = QLineEdit()
        self.installed_filter.setPlaceholderText("Filter installed packages...")
        self.installed_filter.textChanged.connect(self._filter_installed)
        row.addWidget(self.installed_filter)
        refresh_btn = QPushButton("Refresh")
        refresh_btn.setObjectName("secondaryBtn")
        refresh_btn.clicked.connect(self._load_installed)
        row.addWidget(refresh_btn)
        layout.addLayout(row)

        self.installed_table = QTableWidget()
        self.installed_table.setColumnCount(3)
        self.installed_table.setHorizontalHeaderLabels(["Name", "Version", "Remove?"])
        self.installed_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.installed_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.installed_table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeToContents)
        self.installed_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.installed_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.installed_table.doubleClicked.connect(self._installed_double_click)
        layout.addWidget(self.installed_table)

        self.tabs.addTab(tab, "📦 Installed")

    # ---- Log / Terminal Tab ----

    def _build_log_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(16, 12, 16, 12)
        layout.setSpacing(10)

        row = QHBoxLayout()
        self.cmd_input = QLineEdit()
        self.cmd_input.setPlaceholderText("Run a custom command (e.g. prt-get search foo)...")
        self.cmd_input.returnPressed.connect(self._run_custom_cmd)
        run_btn = QPushButton("Run")
        run_btn.clicked.connect(self._run_custom_cmd)
        clear_btn = QPushButton("Clear")
        clear_btn.setObjectName("secondaryBtn")
        clear_btn.clicked.connect(lambda: self.log_output.clear())
        row.addWidget(self.cmd_input)
        row.addWidget(run_btn)
        row.addWidget(clear_btn)
        layout.addLayout(row)

        self.log_output = QPlainTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setMaximumBlockCount(10000)
        layout.addWidget(self.log_output)

        cancel_row = QHBoxLayout()
        self.cancel_btn = QPushButton("Cancel Operation")
        self.cancel_btn.setObjectName("dangerBtn")
        self.cancel_btn.setEnabled(False)
        self.cancel_btn.clicked.connect(self._cancel_operation)
        cancel_row.addStretch()
        cancel_row.addWidget(self.cancel_btn)
        layout.addLayout(cancel_row)

        self.tabs.addTab(tab, "🖥 Terminal")

    # ---- Data Loading ----

    def _load_data(self):
        self._load_ports_db()
        self._load_installed()

    def _load_ports_db(self):
        self.statusBar().showMessage("Loading ports database...")
        self.progress_bar.show()
        self.progress_bar.setRange(0, 0)  # indeterminate

        self._ports_worker = LoadPortsWorker()
        self._ports_worker.portsLoaded.connect(self._on_ports_loaded)
        self._ports_worker.progress.connect(lambda m: self.statusBar().showMessage(m))
        self._ports_worker.start()
        self._workers.append(self._ports_worker)

    def _on_ports_loaded(self, ports):
        self.ports_db = ports
        self.progress_bar.hide()
        self.statusBar().showMessage(f"Loaded {len(ports)} ports")
        self._populate_browse_tree()
        self._check_installed_for_search()

    def _load_installed(self):
        self.statusBar().showMessage("Loading installed packages...")
        self._inst_worker = LoadInstalledWorker()
        self._inst_worker.loaded.connect(self._on_installed_loaded)
        self._inst_worker.start()
        self._workers.append(self._inst_worker)

    def _on_installed_loaded(self, pkgs):
        self.installed_map = pkgs
        self._populate_installed_table()
        self._check_installed_for_search()
        self.statusBar().showMessage(f"{len(pkgs)} packages installed")

    def _check_installed_for_search(self):
        """Re-check installed status in search results if both datasets loaded."""
        if self.ports_db and self.installed_map:
            self._refresh_search_installed_col()

    # ---- Search ----

    def _do_search(self):
        term = self.search_input.text().strip().lower()
        if not term:
            return
        results = []
        for p in self.ports_db:
            name = p.get("name", "").lower()
            desc = p.get("description", "").lower()
            cat = p.get("category", "").lower()
            if term in name or term in desc or term in cat:
                results.append(p)
        self._populate_search_table(results)

    def _populate_search_table(self, results):
        self.search_table.setRowCount(len(results))
        for i, p in enumerate(results):
            name = p.get("name", "?")
            ver = p.get("version", "?")
            desc = p.get("description", "")
            installed = name in self.installed_map
            self.search_table.setItem(i, 0, QTableWidgetItem(name))
            self.search_table.setItem(i, 1, QTableWidgetItem(ver))
            self.search_table.setItem(i, 2, QTableWidgetItem(desc))
            inst_item = QTableWidgetItem("Yes" if installed else "No")
            if installed:
                inst_item.setForeground(QColor("#a6e3a1"))
            else:
                inst_item.setForeground(QColor("#6c7086"))
            self.search_table.setItem(i, 3, inst_item)
        self.statusBar().showMessage(f"Found {len(results)} ports matching search")

    def _refresh_search_installed_col(self):
        for i in range(self.search_table.rowCount()):
            name_item = self.search_table.item(i, 0)
            if name_item:
                name = name_item.text()
                installed = name in self.installed_map
                inst_item = QTableWidgetItem("Yes" if installed else "No")
                if installed:
                    inst_item.setForeground(QColor("#a6e3a1"))
                else:
                    inst_item.setForeground(QColor("#6c7086"))
                self.search_table.setItem(i, 3, inst_item)

    def _search_double_click(self, index):
        row = index.row()
        name_item = self.search_table.item(row, 0)
        if not name_item:
            return
        name = name_item.text()
        self._show_port_details(name)

    # ---- Browse ----

    def _populate_browse_tree(self):
        self.browse_tree.clear()
        cat_items = {}
        for cat in REPO_CATEGORIES:
            item = QTreeWidgetItem(self.browse_tree, [cat, "", "", ""])
            item.setFlags(item.flags() & ~Qt.ItemIsSelectable)
            font = item.font(0)
            font.setBold(True)
            item.setFont(0, font)
            item.setForeground(0, QColor("#89b4fa"))
            cat_items[cat] = item

        for p in self.ports_db:
            cat = p.get("category", "")
            parent = cat_items.get(cat)
            if parent is None:
                parent = QTreeWidgetItem(self.browse_tree, [cat, "", "", ""])
                cat_items[cat] = parent
            name = p.get("name", "?")
            ver = p.get("version", "?")
            desc = p.get("description", "")
            item = QTreeWidgetItem(parent, [name, ver, desc, cat])
            item.setData(0, Qt.UserRole, p)

        self.browse_tree.expandAll()

    def _filter_browse(self):
        filter_text = self.browse_filter.text().strip().lower()
        cat_filter = self.browse_category.currentText()
        if cat_filter == "All Categories":
            cat_filter = ""

        for i in range(self.browse_tree.topLevelItemCount()):
            cat_item = self.browse_tree.topLevelItem(i)
            cat_name = cat_item.text(0)
            cat_visible = (not cat_filter or cat_name == cat_filter)
            any_child_visible = False
            for j in range(cat_item.childCount()):
                child = cat_item.child(j)
                name = child.text(0).lower()
                desc = child.text(2).lower()
                match = (not filter_text or filter_text in name or filter_text in desc)
                child.setHidden(not match)
                if match:
                    any_child_visible = True
            cat_item.setHidden(not (cat_visible and any_child_visible))

    def _browse_double_click(self, item, col):
        port_data = item.data(0, Qt.UserRole)
        if port_data:
            self._show_port_details(port_data.get("name", ""))

    # ---- Installed ----

    def _populate_installed_table(self):
        sorted_pkgs = sorted(self.installed_map.items(), key=lambda x: x[0].lower())
        self.installed_table.setRowCount(len(sorted_pkgs))
        for i, (name, ver) in enumerate(sorted_pkgs):
            self.installed_table.setItem(i, 0, QTableWidgetItem(name))
            self.installed_table.setItem(i, 1, QTableWidgetItem(ver))
            cb = QTableWidgetItem()
            cb.setFlags(Qt.ItemIsUserCheckable | Qt.ItemIsEnabled)
            cb.setCheckState(Qt.Unchecked)
            self.installed_table.setItem(i, 2, cb)
        self.statusBar().showMessage(f"{len(sorted_pkgs)} packages installed")

    def _filter_installed(self):
        term = self.installed_filter.text().strip().lower()
        for i in range(self.installed_table.rowCount()):
            name_item = self.installed_table.item(i, 0)
            if name_item:
                match = not term or term in name_item.text().lower()
                self.installed_table.setRowHidden(i, not match)

    def _installed_double_click(self, index):
        row = index.row()
        name_item = self.installed_table.item(row, 0)
        if name_item:
            self._show_port_details(name_item.text())

    def _get_selected_installed(self):
        """Return list of package names checked in the installed table."""
        selected = []
        for i in range(self.installed_table.rowCount()):
            cb = self.installed_table.item(i, 2)
            name_item = self.installed_table.item(i, 0)
            if cb and name_item and cb.checkState() == Qt.Checked:
                selected.append(name_item.text())
        return selected

    # ---- Port Details ----

    def _show_port_details(self, name):
        port_info = None
        for p in self.ports_db:
            if p.get("name") == name:
                port_info = p
                break
        if port_info is None:
            port_info = {"name": name, "version": "?", "description": "Port info not available in local database."}
        dlg = PortDetailsDialog(port_info, self.installed_map, self)
        dlg.exec_()

    # ---- Commands / Actions ----

    def _run_command(self, cmd, tab_focus=True):
        """Run a command in the log tab."""
        if tab_focus:
            self.tabs.setCurrentIndex(3)  # Log tab
        self._append_log(f"\n{'='*60}\n")
        worker = CommandWorker(cmd)
        worker.output.connect(self._append_log)
        worker.error.connect(self._append_log)
        worker.finished.connect(self._on_command_finished)
        self._cmd_worker = worker
        self.cancel_btn.setEnabled(True)
        self.progress_bar.show()
        self.progress_bar.setRange(0, 0)
        self.statusBar().showMessage(f"Running: {cmd}")
        worker.start()
        self._workers.append(worker)

    def _on_command_finished(self, rc, stdout, stderr):
        self.cancel_btn.setEnabled(False)
        self.progress_bar.hide()
        if rc == 0:
            self.statusBar().showMessage("Command completed successfully")
        elif rc == -1 and stderr == "cancelled":
            self.statusBar().showMessage("Operation cancelled")
        else:
            self.statusBar().showMessage(f"Command finished with exit code {rc}")

    def _append_log(self, text):
        self.log_output.appendPlainText(text.rstrip())
        sb = self.log_output.verticalScrollBar()
        sb.setValue(sb.maximum())

    def _cancel_operation(self):
        if self._cmd_worker and self._cmd_worker.isRunning():
            self._cmd_worker.cancel()
            self._append_log("[Cancelling...]\n")

    def _run_custom_cmd(self):
        cmd = self.cmd_input.text().strip()
        if not cmd:
            return
        self.cmd_input.clear()
        self._run_command(cmd)

    def _sync_ports(self):
        self.tabs.setCurrentIndex(3)
        self._append_log("\n" + "="*60 + "\n")
        self._append_log("Syncing ports tree...\n")
        worker = SyncWorker()
        worker.output.connect(self._append_log)
        worker.finished.connect(lambda rc: self._on_sync_done(rc))
        self._cmd_worker = worker
        self.cancel_btn.setEnabled(True)
        self.progress_bar.show()
        self.progress_bar.setRange(0, 0)
        self.statusBar().showMessage("Syncing ports tree...")
        worker.start()
        self._workers.append(worker)

    def _on_sync_done(self, rc):
        self.cancel_btn.setEnabled(False)
        self.progress_bar.hide()
        self.statusBar().showMessage("Sync complete — reloading database")
        self._load_ports_db()

    def _sysup(self):
        reply = QMessageBox.question(
            self, "System Update",
            "Run prt-get sysup to update all installed packages?\nThis may take a while.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            self._run_command("prt-get sysup")

    def _install_selected(self):
        names = self._get_selected_search_or_browse()
        if not names:
            QMessageBox.information(self, "No Selection", "Select port(s) to install from the Search or Browse tab.")
            return
        reply = QMessageBox.question(
            self, "Install",
            f"Build and install {len(names)} package(s)?\n\n" + "\n".join(names[:20]),
            QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes,
        )
        if reply == QMessageBox.Yes:
            for name in names:
                self._run_command(f"prt-get install {name}", tab_focus=True)

    def _remove_selected(self):
        names = self._get_selected_installed()
        if not names:
            QMessageBox.information(self, "No Selection", "Check packages in the Installed tab to remove.")
            return
        reply = QMessageBox.warning(
            self, "Remove Packages",
            f"Remove {len(names)} package(s)?\n\n" + "\n".join(names[:20]),
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            for name in names:
                self._run_command(f"prt-get remove {name}", tab_focus=True)

    def _update_selected(self):
        names = self._get_selected_search_or_browse()
        if not names:
            names = self._get_selected_installed()
        if not names:
            QMessageBox.information(self, "No Selection", "Select package(s) to update.")
            return
        for name in names:
            self._run_command(f"prt-get update {name}", tab_focus=True)

    def _update_all(self):
        reply = QMessageBox.question(
            self, "Update All",
            "Update all installed packages?\nThis may take a very long time.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            self._run_command("prt-get sysup")

    def _get_selected_search_or_browse(self):
        """Get selected package names from search table or browse tree."""
        names = []
        # Check search table
        for idx in self.search_table.selectionModel().selectedRows():
            name_item = self.search_table.item(idx.row(), 0)
            if name_item:
                names.append(name_item.text())
        # Check browse tree
        for item in self.browse_tree.selectedItems():
            port_data = item.data(0, Qt.UserRole)
            if port_data:
                names.append(port_data.get("name", ""))
            elif item.parent() is None:
                # Category header, skip
                continue
        return list(dict.fromkeys(names))  # dedupe, preserve order

    def _find_orphans(self):
        self.tabs.setCurrentIndex(3)
        self._append_log("\n" + "="*60 + "\n")
        self._append_log("Searching for orphan packages...\n")
        self._run_command(
            "comm -23 <(pkginfo -i 2>/dev/null | awk '{print $1}' | sort) "
            "<(prt-get list 2>/dev/null | sort) 2>/dev/null || "
            "echo 'Could not determine orphans (bash required)'",
            tab_focus=True,
        )

    def _clean_cache(self):
        reply = QMessageBox.question(
            self, "Clean Cache",
            "Clean the package cache?\nThis removes downloaded tarballs from /var/cache/prt-get.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            self._run_command("rm -f /var/cache/prt-get/packages/*.tar.* && echo 'Cache cleaned.'")

    # ---- Cleanup ----

    def closeEvent(self, event):
        for w in self._workers:
            if w.isRunning():
                w.cancel()
                w.wait(2000)
        event.accept()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLESHEET)
    app.setFont(QFont("Segoe UI", 10))

    window = PortManagerWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
