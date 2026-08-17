#!/usr/bin/env pwsh
# import-venomlinux.ps1
# Converts venomlinux/scratchpkg spkgbuild ports to CRUX/prt-get Pkgfile format
# and imports new ports into StormFS

$ErrorActionPreference = "Continue"

# Paths
$VENOMCORE = "C:\Users\ben\Desktop\StormFS-Linux\iso-builder\work\venomcore"
$VENOMEXTRA = "C:\Users\ben\Desktop\StormFS-Linux\iso-builder\work\venomextra"
$STORMFS_PORTS = "C:\Users\ben\Desktop\StormFS-Linux\ports"

$STORMFS_CATEGORIES = @('core','opt','contrib','xorg','xfce','gnome','plasma','lxqt','compiz','compat-32','files')

# Category overrides - build as array of pairs then convert to hashtable
$overridesData = @(
    # Xorg/X11
    'xorg','xorg'; 'xorg-server','xorg'; 'xorg-libraries','xorg'; 'xorg-applications','xorg'
    'xorg-fonts','xorg'; 'xorg-video-drivers','xorg'; 'xorgproto','xorg'
    'libxcb','xorg'; 'libx11','xorg'; 'libxau','xorg'; 'libxdmcp','xorg'
    'libxext','xorg'; 'libxfixes','xorg'; 'libxrender','xorg'; 'libxrandr','xorg'
    'libxinerama','xorg'; 'libxcursor','xorg'; 'libxcomposite','xorg'; 'libxdamage','xorg'
    'libxft','xorg'; 'libxfont2','xorg'; 'libxfont','xorg'; 'libxkbcommon','xorg'
    'libxkbfile','xorg'; 'libxklavier','xorg'; 'libxi','xorg'; 'libxmu','xorg'
    'libxpm','xorg'; 'libxaw','xorg'; 'libxt','xorg'; 'libxv','xorg'
    'libxvmc','xorg'; 'libxxf86vm','xorg'; 'libxshmfence','xorg'
    'libxscrnsaver','xorg'; 'libxpresent','xorg'; 'libxres','xorg'
    'xtrans','xorg'; 'xbitmaps','xorg'; 'xkeyboard-config','xorg'; 'xauth','xorg'
    'xinit','xorg'; 'xset','xorg'; 'xsetroot','xorg'; 'xprop','xorg'
    'xrandr','xorg'; 'xrdb','xorg'; 'xdpyinfo','xorg'; 'xdriinfo','xorg'
    'xev','xorg'; 'xkill','xorg'; 'xlsatoms','xorg'; 'xlsclients','xorg'
    'xlsfonts','xorg'; 'xman','xorg'; 'xmessage','xorg'; 'xmore','xorg'
    'xpr','xorg'; 'xrefresh','xorg'; 'xwd','xorg'; 'xwininfo','xorg'
    'xwud','xorg'; 'xfontsel','xorg'; 'xinput','xorg'; 'xmodmap','xorg'
    'xcmsdb','xorg'; 'xgamma','xorg'; 'xhost','xorg'; 'xclock','xorg'
    'xterm','xorg'; 'x11perf','xorg'; 'xwayland','xorg'; 'setxkbmap','xorg'
    'mkfontscale','xorg'; 'xcursorgen','xorg'; 'xcursor-themes','xorg'
    'xclip','xorg'; 'xdotool','xorg'; 'xdo','xorg'; 'xsel','xorg'
    'xtitle','xorg'; 'xwallpaper','xorg'; 'xcompmgr','xorg'; 'xbacklight','xorg'
    'xbindkeys','xorg'; 'xbanish','xorg'; 'xautolock','xorg'; 'xkbevd','xorg'
    'suckless-tools','xorg'; 'scrot','xorg'; 'sxiv','xorg'; 'nsxiv','xorg'
    'imake','xorg'; 'sessreg','xorg'; 'luit','xorg'
    'xf86-input-evdev','xorg'; 'xf86-input-libinput','xorg'; 'xf86-input-synaptics','xorg'
    'xf86-input-vmmouse','xorg'; 'xf86-input-wacom','xorg'
    'xf86-video-amdgpu','xorg'; 'xf86-video-ati','xorg'; 'xf86-video-fbdev','xorg'
    'xf86-video-intel','xorg'; 'xf86-video-nouveau','xorg'; 'xf86-video-qxl','xorg'
    'xf86-video-vesa','xorg'; 'xf86-video-vmware','xorg'
    'xdg-desktop-portal','xorg'; 'xdg-desktop-portal-wlr','xorg'
    'libglvnd','xorg'; 'libdrm','xorg'; 'mesa','xorg'
    # XFCE
    'xfce4-panel','xfce'; 'xfce4-settings','xfce'; 'xfce4-session','xfce'
    'xfce4-power-manager','xfce'; 'xfce4-appfinder','xfce'; 'xfce4-terminal','xfce'
    'xfce4-notifyd','xfce'; 'xfce4-screensaver','xfce'; 'xfce4-pulseaudio-plugin','xfce'
    'xfce4-whiskermenu-plugin','xfce'; 'xfce4-taskmanager','xfce'
    'thunar','xfce'; 'thunar-volman','xfce'; 'tumbler','xfce'; 'ristretto','xfce'
    'mousepad','xfce'; 'xfburn','xfce'; 'xfconf','xfce'
    'libxfce4ui','xfce'; 'libxfce4util','xfce'; 'libxfcegui4','xfce'
    'garcon','xfce'; 'exo','xfce'; 'libmanette','xfce'
    # GNOME
    'gnome-shell','gnome'; 'gnome-session','gnome'; 'gnome-settings-daemon','gnome'
    'gnome-control-center','gnome'; 'gnome-terminal','gnome'; 'gnome-calculator','gnome'
    'gnome-text-editor','gnome'; 'gnome-characters','gnome'; 'gnome-clocks','gnome'
    'gnome-font-viewer','gnome'; 'gnome-screenshot','gnome'; 'gnome-system-monitor','gnome'
    'gnome-tweaks','gnome'; 'gnome-disk-utility','gnome'; 'gnome-keyring','gnome'
    'gnome-menus','gnome'; 'gnome-desktop','gnome'; 'gnome-backgrounds','gnome'
    'gnome-icon-theme','gnome'; 'gnome-themes-extra','gnome'; 'gnome-common','gnome'
    'gdm','gnome'; 'mutter','gnome'; 'nautilus','gnome'; 'eye-of-gnome','gnome'
    'eog','gnome'; 'file-roller','gnome'; 'evince','gnome'; 'totem','gnome'
    'cheese','gnome'; 'libgnomekbd','gnome'; 'gvfs','gnome'
    'gedit','gnome'; 'gedit-plugins','gnome'; 'gcr','gnome'
    'dconf','gnome'; 'dconf-editor','gnome'; 'gjs','gnome'; 'gnome-autoar','gnome'
    'gcr-4','gnome'; 'libgnome-games-support','gnome'; 'simple-scan','gnome'
    # KDE Plasma
    'plasma-desktop','plasma'; 'plasma-workspace','plasma'; 'plasma-nm','plasma'
    'plasma-pa','plasma'; 'kwin','plasma'; 'sddm','plasma'; 'dolphin','plasma'
    'konsole','plasma'; 'kate','plasma'; 'systemsettings','plasma'; 'powerdevil','plasma'
    'kget','plasma'; 'ark','plasma'; 'gwenview','plasma'; 'okular','plasma'
    'spectacle','plasma'; 'kdeconnect','plasma'; 'plasma-discover','plasma'
    'discover','plasma'; 'breeze','plasma'; 'breeze-gtk','plasma'; 'breeze-icons','plasma'
    'oxygen','plasma'; 'oxygen-icons5','plasma'
    'kio','plasma'; 'ki18n','plasma'; 'kconfig','plasma'; 'kcoreaddons','plasma'
    'kwidgetsaddons','plasma'; 'kpackage','plasma'; 'kimageformats','plasma'
    'solid','plasma'; 'sonnet','plasma'; 'threadweaver','plasma'; 'kparts','plasma'
    'kwindowsystem','plasma'; 'kidletime','plasma'; 'kitemviews','plasma'
    'kitemmodels','plasma'; 'kjobwidgets','plasma'; 'kcodecs','plasma'
    'kservice','plasma'; 'kauth','plasma'; 'kdoctools','plasma'; 'kdnssd','plasma'
    'kcrash','plasma'; 'kplotting','plasma'; 'attica','plasma'; 'purpose','plasma'
    'baloo','plasma'; 'frameworkintegration','plasma'; 'kcmutils','plasma'
    'kirigami','plasma'; 'knotifications','plasma'; 'plasma-framework','plasma'
    'plasma-integration','plasma'; 'qqc2-desktop-style','plasma'; 'syndication','plasma'
    'kcolorscheme','plasma'; 'kconfigwidgets','plasma'; 'kiconthemes','plasma'
    'kcompletion','plasma'; 'ktextwidgets','plasma'; 'kxmlgui','plasma'
    'kbookmarks','plasma'; 'kglobalaccel','plasma'; 'kstatusnotifieritem','plasma'
    'modemmanager-qt','plasma'; 'networkmanager-qt','plasma'; 'bluez-qt','plasma'
    'plasma-browser-integration','plasma'; 'plasma-activities','plasma'
    'plasma-activities-stats','plasma'
    # LXQt
    'lxqt-panel','lxqt'; 'lxqt-session','lxqt'; 'lxqt-config','lxqt'
    'lxqt-qtplugin','lxqt'; 'pcmanfm-qt','lxqt'; 'qterminal','lxqt'
    'qps','lxqt'; 'screengrab','lxqt'; 'obconf-qt','lxqt'
    'libfm-qt','lxqt'; 'liblxqt','lxqt'; 'libsysstat','lxqt'
    'libqtxdg','lxqt'; 'lxqt-openssh-askpass','lxqt'; 'lxqt-sudo','lxqt'
    'lxqt-archiver','lxqt'; 'featherpad','lxqt'; 'pulseaudio-qt','lxqt'
    # Compiz
    'compiz','compiz'; 'ccsm','compiz'; 'fusion-icon','compiz'
)
$CATEGORY_OVERRIDES = @{}
for ($i = 0; $i -lt $overridesData.Count; $i += 2) {
    $CATEGORY_OVERRIDES[$overridesData[$i]] = $overridesData[$i+1]
}

# Skip list
$SKIP_PORTS = @(
    'scratchpkg','scratch','venom-zram','venom-java-manager'
    'linux-libre','linux-libre-bin','linux-rc','linux-rc-bin'
    'linux-lts','linux-lts-bin','linux-bin'
    'syslinux','limine','refind'
    'make','sed','tar','grep','findutils','which','patch','diffutils'
    'bison','flex','gettext','texinfo'
    'runit','runit-rc','sinit','s6','s6-rc','mdev','mdev-daemon','eudev'
    'lsb-release','os-prober'
    'linux','linux-api-headers'
    'libreoffice-bin-es'
)

# Priority ports
$PRIORITY_PORTS = @(
    'neovim','kitty','foot','go','rust','zig','hyprland','sway','waybar',
    'wofi','fuzzel','gimp','obs-studio','handbrake','libreoffice-bin',
    'picom','bspwm','dwm','openvpn','wireguard-tools','tailscale',
    'retroarch','darktable','inkscape','swaybg','swaylock','swayidle',
    'wlroots','wlroots20','wl-clipboard','wlr-randr','wf-recorder',
    'mako','wlogout','swaync','swww','wbg','wlsunset','kanshi',
    'hyprpaper','hyprshot','grim','slurp','jq','polkit','seatd','udisks2',
    'pipewire','wireplumber','pamixer','playerctl',
    'starship','fzf','fd','bat','eza','yazi',
    'neomutt','notmuch','hugo','rclone','yt-dlp','mpv',
    'qbittorrent','transmission-gtk','keepassxc',
    'docker','podman','containerd',
    'mangohud','vulkan-tools','vulkan-icd-loader',
    'v4l-utils','sshfs-fuse','nfs-utils',
    'btop','nvtop','lm_sensors',
    'firejail','ufw',
    'cmake','ninja','meson','scdoc'
)

Write-Host "=== Venom Linux to StormFS Port Importer ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build existing port map
Write-Host "Building map of existing StormFS ports..." -ForegroundColor Yellow
$existingPorts = @{}
foreach ($cat in $STORMFS_CATEGORIES) {
    $catDir = Join-Path $STORMFS_PORTS $cat
    if (Test-Path $catDir) {
        Get-ChildItem -Path $catDir -Directory | ForEach-Object {
            $existingPorts[$_.Name] = $cat
        }
    }
}
Write-Host "  Found $($existingPorts.Count) existing ports" -ForegroundColor Gray

# Step 2: Scan venomlinux repos
Write-Host "Scanning venomlinux repos..." -ForegroundColor Yellow
$venomPorts = @{}

$repos = @(
    @{Name='venomcore'; Path=$VENOMCORE; DefaultCategory='core'},
    @{Name='venomextra'; Path=$VENOMEXTRA; DefaultCategory='opt'}
)

foreach ($repo in $repos) {
    if (-not (Test-Path $repo.Path)) {
        Write-Host "  WARNING: $($repo.Path) not found" -ForegroundColor Red
        continue
    }
    Get-ChildItem -Path $repo.Path -Directory | ForEach-Object {
        $spkgbuild = Join-Path $_.FullName "spkgbuild"
        if (Test-Path $spkgbuild) {
            $patches = Get-ChildItem $_.FullName -File | Where-Object {
                $_.Name -match '\.(patch|diff)$' -and $_.Name -notmatch '^\.'
            }
            $extras = Get-ChildItem $_.FullName -File | Where-Object {
                $_.Name -notin @('spkgbuild','depends','.checksums','.pkgfiles') -and
                $_.Name -notmatch '\.(patch|diff)$'
            }
            $venomPorts[$_.Name] = @{
                Name = $_.Name
                Path = $_.FullName
                Repo = $repo.Name
                DefaultCategory = $repo.DefaultCategory
                HasPatches = ($patches | Measure-Object).Count -gt 0
                ExtraFiles = @($extras | ForEach-Object { $_.Name })
            }
        }
    }
}
Write-Host "  Found $($venomPorts.Count) venomlinux ports" -ForegroundColor Gray

# Step 3: Determine target category
function Get-TargetCategory {
    param([string]$PortName, [string]$DefaultCategory)

    if ($CATEGORY_OVERRIDES.ContainsKey($PortName)) {
        return $CATEGORY_OVERRIDES[$PortName]
    }

    if ($PortName -match '^xorg-') { return 'xorg' }
    if ($PortName -match '^(xfce|thunar|garcon|mousepad|ristretto|tumbler|xfburn)') { return 'xfce' }
    if ($PortName -match '^(gnome|gdm|mutter|nautilus|evince|eog|gvfs|gcr|gjs|gedit)') { return 'gnome' }
    if ($PortName -match '^(plasma|kwin|sddm|dolphin|konsole|kate|systemsettings|powerdevil|breeze|oxygen|ark|gwenview|okular|spectacle|kdeconnect)') { return 'plasma' }
    if ($PortName -match '^(lxqt|pcmanfm-qt|qterminal|featherpad|libfm-qt|liblxqt)') { return 'lxqt' }
    if ($PortName -match 'ttf-|^font-') { return 'opt' }
    if ($PortName -match '^python3-') { return 'opt' }
    if ($PortName -match '^perl-') { return 'opt' }
    if ($PortName -match '^ruby-') { return 'opt' }

    return 'opt'
}

# Step 4: Convert spkgbuild to Pkgfile
function Convert-SpkgbuildToPkgfile {
    param([string]$PortDir, [string]$PortName)

    $spkgbuildPath = Join-Path $PortDir "spkgbuild"
    $dependsPath = Join-Path $PortDir "depends"

    $lines = Get-Content $spkgbuildPath
    $content = Get-Content $spkgbuildPath -Raw

    # Extract metadata
    $description = ""; $homepage = ""; $maintainer = ""
    if ($content -match 'description\s*=\s*"([^"]*)"') { $description = $Matches[1].Trim() }
    if ($content -match 'homepage\s*=\s*"([^"]*)"') { $homepage = $Matches[1].Trim() }
    if ($content -match 'maintainer\s*=\s*"([^"]*)"') { $maintainer = $Matches[1].Trim() }

    $name = ""; $version = ""; $release = ""
    if ($content -match '(?m)^name\s*=\s*(.+)$') { $name = $Matches[1].Trim() }
    if ($content -match '(?m)^version\s*=\s*(.+)$') { $version = $Matches[1].Trim() }
    if ($content -match '(?m)^release\s*=\s*(.+)$') { $release = $Matches[1].Trim() }

    # Extract dependencies
    $deps = @()
    if (Test-Path $dependsPath) {
        $deps = @(Get-Content $dependsPath | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
    }

    # Extract source block (multi-line with tab indentation)
    $sourceLines = @()
    $inSource = $false
    $sourceAccum = ""
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^source\s*=\s*"') {
            $inSource = $true
            $afterEq = $trimmed -replace '^source\s*=\s*"', ''
            if ($afterEq.EndsWith('"') -and $afterEq.Length -gt 0) {
                $sourceLines += $afterEq.TrimEnd('"')
                $inSource = $false
            } elseif ($afterEq.Length -eq 0) {
                $sourceAccum = ""
            } else {
                $sourceAccum = $afterEq
            }
        } elseif ($inSource) {
            if ($trimmed.EndsWith('"')) {
                $val = $trimmed.TrimEnd('"').Trim()
                if ($val.Length -gt 0) { $sourceAccum += " " + $val }
                if ($sourceAccum.Length -gt 0) { $sourceLines += $sourceAccum }
                $sourceAccum = ""
                $inSource = $false
            } else {
                $val = $trimmed.Trim()
                if ($val.Length -gt 0) {
                    if ($sourceAccum.Length -gt 0) { $sourceAccum += " " + $val }
                    else { $sourceAccum = $val }
                }
            }
        }
    }

    # Extract noextract block
    $noextractLines = @()
    $inNoextract = $false
    $noextractAccum = ""
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^noextract\s*=\s*"') {
            $inNoextract = $true
            $afterEq = $trimmed -replace '^noextract\s*=\s*"', ''
            if ($afterEq.EndsWith('"') -and $afterEq.Length -gt 0) {
                $noextractLines += $afterEq.TrimEnd('"')
                $inNoextract = $false
            } elseif ($afterEq.Length -eq 0) {
                $noextractAccum = ""
            } else {
                $noextractAccum = $afterEq
            }
        } elseif ($inNoextract) {
            if ($trimmed.EndsWith('"')) {
                $val = $trimmed.TrimEnd('"').Trim()
                if ($val.Length -gt 0) { $noextractAccum += " " + $val }
                if ($noextractAccum.Length -gt 0) { $noextractLines += $noextractAccum }
                $noextractAccum = ""
                $inNoextract = $false
            } else {
                $val = $trimmed.Trim()
                if ($val.Length -gt 0) {
                    if ($noextractAccum.Length -gt 0) { $noextractAccum += " " + $val }
                    else { $noextractAccum = $val }
                }
            }
        }
    }

    # Extract build() function
    $inBuild = $false
    $braceCount = 0
    $buildLines = @()
    foreach ($line in $lines) {
        if (-not $inBuild -and $line -match '^\s*build\(\)\s*\{') {
            $inBuild = $true
            $braceCount = 0
            foreach ($ch in $line.ToCharArray()) {
                if ($ch -eq '{') { $braceCount++ }
                elseif ($ch -eq '}') { $braceCount-- }
            }
            $buildLines += $line
            if ($braceCount -le 0) { $inBuild = $false }
            continue
        }
        if ($inBuild) {
            foreach ($ch in $line.ToCharArray()) {
                if ($ch -eq '{') { $braceCount++ }
                elseif ($ch -eq '}') { $braceCount-- }
            }
            $buildLines += $line
            if ($braceCount -le 0) { break }
        }
    }

    # Convert venom-specific patterns
    $buildFunc = $buildLines -join "`n"

    # Replace venom-meson calls: venom-meson <src> <builddir> [args]
    $buildFunc = $buildFunc -replace 'venom-meson\s+\S+\s+build', 'meson setup $name-$version build'
    # Replace scratch isinstalled
    $buildFunc = $buildFunc -replace 'scratch isinstalled (\S+) &&\s*\{', 'prt-get isinst $1 && {'
    $buildFunc = $buildFunc -replace 'scratch isinstalled (\S+)', 'prt-get isinst $1'
    # Remove cbuild_options and cbuild_restore lines
    $buildFunc = $buildFunc -replace '(?m)^\s*cbuild_options\s+"[^"]*"\s*$', ''
    $buildFunc = $buildFunc -replace '(?m)^\s*cbuild_restore\s+"[^"]*"\s*\|\|\s*.*$', ''
    # Remove _portdir line
    $buildFunc = $buildFunc -replace '(?m)^\s*_portdir=\$PWD\s*$', ''
    # Fix $SOURCE_DIR
    $buildFunc = $buildFunc -replace '\$SOURCE_DIR', '$SRC'

    # Build Pkgfile
    $pkgfile = @()
    $pkgfile += "# Description: $description"
    $pkgfile += "# URL: $homepage"
    $pkgfile += "# Maintainer: $maintainer"
    if ($deps.Count -gt 0) {
        $pkgfile += "# Depends on: $($deps -join ' ')"
    }
    $pkgfile += ""
    $pkgfile += "name=$name"
    $pkgfile += "version=$version"
    $pkgfile += "release=$release"

    # Source array
    if ($sourceLines.Count -gt 0) {
        $pkgfile += "source=($($sourceLines[0]))"
        for ($i = 1; $i -lt $sourceLines.Count; $i++) {
            $pkgfile += "    $($sourceLines[$i])"
        }
    } else {
        $pkgfile += "source=()"
    }

    if ($noextractLines.Count -gt 0) {
        $pkgfile += "noextract=($($noextractLines -join ' '))"
    }

    $pkgfile += ""
    $pkgfile += $buildFunc

    return ($pkgfile -join "`n")
}

# Step 5: Import
Write-Host ""
Write-Host "Processing ports for import..." -ForegroundColor Yellow
Write-Host ""

$importedCount = 0
$skippedExisting = 0
$skippedUseless = 0
$failedPorts = @()
$importedByCategory = @{}

# Sort: priority non-complex first
$sortedPorts = $venomPorts.GetEnumerator() | Sort-Object { $_.Key }

foreach ($port in $sortedPorts) {
    $portName = $port.Key
    $portInfo = $port.Value

    if ($existingPorts.ContainsKey($portName)) { $skippedExisting++; continue }
    if ($portName -in $SKIP_PORTS) { $skippedUseless++; continue }

    $targetCategory = Get-TargetCategory -PortName $portName -DefaultCategory $portInfo.DefaultCategory
    $targetDir = Join-Path (Join-Path $STORMFS_PORTS $targetCategory) $portName

    if (Test-Path $targetDir) { $skippedExisting++; continue }

    try {
        $pkgfileContent = Convert-SpkgbuildToPkgfile -PortDir $portInfo.Path -PortName $portName
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

        $pkgfilePath = Join-Path $targetDir "Pkgfile"
        [System.IO.File]::WriteAllText($pkgfilePath, $pkgfileContent, [System.Text.UTF8Encoding]::new($false))

        # Copy extra files
        $sourceFiles = Get-ChildItem $portInfo.Path -File | Where-Object {
            $_.Name -notin @('spkgbuild','depends','.checksums','.pkgfiles')
        }
        foreach ($srcFile in $sourceFiles) {
            Copy-Item $srcFile.FullName (Join-Path $targetDir $srcFile.Name)
        }

        $importedCount++
        if (-not $importedByCategory.ContainsKey($targetCategory)) {
            $importedByCategory[$targetCategory] = [System.Collections.ArrayList]@()
        }
        [void]$importedByCategory[$targetCategory].Add($portName)

        $isPriority = if ($portName -in $PRIORITY_PORTS) { " [PRIORITY]" } else { "" }
        Write-Host "  IMPORTED: $portName -> $targetCategory$isPriority" -ForegroundColor Green
    }
    catch {
        $failedPorts += $portName
        Write-Host "  FAILED: $portName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Summary
Write-Host ""
Write-Host "=== IMPORT SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Total venomlinux ports scanned: $($venomPorts.Count)"
Write-Host "  Ports imported: $importedCount" -ForegroundColor Green
Write-Host "  Ports skipped (already exist): $skippedExisting" -ForegroundColor Yellow
Write-Host "  Ports skipped (not useful): $skippedUseless" -ForegroundColor Gray
if ($failedPorts.Count -gt 0) {
    Write-Host "  Ports failed: $($failedPorts.Count)" -ForegroundColor Red
    Write-Host "    $($failedPorts -join ', ')" -ForegroundColor Red
}

Write-Host ""
Write-Host "Imports by category:" -ForegroundColor Cyan
foreach ($cat in ($importedByCategory.Keys | Sort-Object)) {
    $ports = $importedByCategory[$cat]
    Write-Host "  $cat ($($ports.Count)): $($ports -join ', ')" -ForegroundColor White
}

Write-Host ""
Write-Host "Priority ports imported:" -ForegroundColor Cyan
$prioritiesImported = @()
foreach ($cat in $importedByCategory.Values) {
    foreach ($p in $cat) {
        if ($p -in $PRIORITY_PORTS) { $prioritiesImported += $p }
    }
}
$prioritiesNotImported = @()
foreach ($p in $PRIORITY_PORTS) {
    $found = $false
    foreach ($cat in $importedByCategory.Values) {
        if ($cat -contains $p) { $found = $true; break }
    }
    if (-not $found) { $prioritiesNotImported += $p }
}
if ($prioritiesImported.Count -gt 0) {
    Write-Host "  Imported ($($prioritiesImported.Count)): $($prioritiesImported -join ', ')" -ForegroundColor Green
}
if ($prioritiesNotImported.Count -gt 0) {
    Write-Host "  Not in venomlinux repos ($($prioritiesNotImported.Count)): $($prioritiesNotImported -join ', ')" -ForegroundColor Yellow
}
