# StormFS-Linux

This repo contain scripts to automate StormFS-Linux  (Linux From Scratch) build, manage, updates, rolling and etc. Yeah its bunch of scripts. Its basically almost whole tools to maintain a Linux distribution. These what I use on my main system as daily use on my main computer. If you want to use StormFS as main OS and be able to maintain it, you can use it. But keep in mind, these scripts do not 100% follow LFS, because thats the main point of StormFS, you build it yourself and customize it as you want. Your distro your rules, but this one follow my rules.

Heres is important point of `StormFS Linux` that follow my rules;

- bootstrap using [LFS v9.1](https://linuxfromscratch.org/lfs/view/9.1/) way.
- multilib. all 32bit libraries is thrown into `/lib32` directory.
- using [CRUX's pkgutils](https://crux.nu/gitweb/?p=tools/pkgutils.git) to build packages from ports + Emmett's extension script.
- using [CRUX's prt-get](https://crux.nu/gitweb/?p=tools/prt-get.git) to manage packages and dependencies.
- writing port is damn easy, a very minimal port only required url to source tarball, compiling is automatically handled.
- dependencies handled by prt-get.
- `/usr/libexec/` not use, use `/usr/lib/` instead.
- use `systemd` as main init by default.


So there, my rules. If you encounter error or bugs when using `lfs-scripts`, open issue here, dont report to LFS dev, they just gonna ignore you.
#Getting started
I recommend using the Gentoo live GUI iso located at https://www.gentoo.org/downloads/
After writing to media and booting perfom the below setps.
git clone https://codeberg.org/bmadonnaster/StormFS-Linux-install
cd StormFS-Linux-install

# bunch of scripts
So i will explain most of these scripts does, else you have to read on top of each script of what it does and how to use it.

## bootstrap.sh
Like its name, this script is to bootstrap main system of StormFS. Theres a few stages to bootsrap base system:
```
1 - build temporary toolchain
2 - build base system (using temporary toolchain)
3 - rebuild base system (without depending on temporary toolchain)
4 - compress base rootfs
```

Stage 1 need to run as regular user to build temporary toolchain. Temporary toolchain is build inside `/tmp` directory so, when reboot, your system might wipe completely the toolchain. But dont worry, at the end of stage 1 the temporary toolchain will get compress as backup incase you wanna reuse it.
```
$ ./bootstrap.sh 1
```

Stage 2 need to run as root to build base LFS system. You can use `sudo` or `doas`. Also, base LFS system is build inside `/tmp` directory, and also, you can compress LFS base system to use it anytime you want without bootstrap again.
```
# ./bootstrap.sh 2
```

Stage 3 also need to run as root to rebuild base system. This stage is completely optional if you wanna skip it. This stage is rebuild base without using temporary toolchain that build on stage 1, but it use its own toolchain instead. Its not in any LFS book but this is my way to make sure my base system is working completely. So if everything is rebuild fine, then i'm assure you that your LFS system is working 100%.
```
# ./bootstrap.sh 3
```

Stage 4 is for compressing your base system into `lfs-rootfs.tar.xz` file, temporary toolchain is excluded. See installing from existing tarball below.
```
$ ./bootstrap.sh 4
```

Okay thats all for bootstrapping StormFS  base. Just keep `lfs-rootfs.tar.xz` to reuse in the future or share with your friends.
```
# install to disk
First thing to do is making partition and mount it but i will not teach it here, i assume you already know if you come for LFS stuff. I assume you mount the partition into `/mnt/lfs` directory.
# Example partition layout
mkfs.vfat -F 32 /dev/nvme0n1p1 /boot/efi
mkfs.ext2  /dev/nvme0n1p2 /boot
mkswap /dev/nvme0n1p3 swap
mkfs.ext4  /dev/nvme0n1p4 / (root filesystem)
mkdir /mnt/StormFS
mount /dev/nvme0n1p4 /mnt/StormFS (root)
mkdir -p /mnt/StormFS/boot/
mount /dev/nvme0n1p2 /mnt/StormFS/boot (boot)
mkdir -p /mnt/StormFS/boot/efi
mount /dev/nvme0n1p1 /mnt/StormFS/boot/efi/ (EFI)
# mount other partitions
mkdir /mnt/StormFS/home
mount /dev/md127 /mnt/StormFS/home/
```
Extract compressed base file system into `/mnt/lfs`
```
# tar -xvf lfs-rootfs.tar.xz -C /mnt/StormFS
```

Chroot into new extracted system
```
# mount --bind /dev /mnt/StormFS/dev
# mount -t devpts devpts /mnt/StormFS/dev/pts -o gid=5,mode=620
# mount -t proc proc /mnt/StormFS/proc
# mount -t sysfs sysfs /mnt/StormFS/sys
# mount -t tmpfs tmpfs /mnt/StormFS/run
# test -h /mnt/StormFS/dev/shm && mkdir -p /mnt/StormFS/$(readlink /mnt/StormFS/dev/shm)
(UEFI)
# mkdir -p /mnt/StormFS/boot/efi
# mount /dev/<efi partition> /mnt/StormFS/boot/efi
# mount --bind /sys/firmware/efi/efivars /mnt/StormFS/sys/firmware/efi/efivars
(GENFSTAB Before chroot)
genfstab -U /mnt/StormFS >> /mnt/StormFS/etc/fstab

# chroot /mnt/StormFS env PS1="(chroot)# " /bin/bash
```

Setting hostname
```
# echo myhostname > /etc/hostname
```

Setting timezone (change XXX and YYY to your choice of timezone)
```
# ln -svf /usr/share/zoneinfo/XXX/YYY /etc/localtime
```

Setting user, root  and password
```
# useradd -m -G users,wheel,audio,video -s /bin/bash <your user>
# passwd <your user>
# passwd root
```

Setting locales
```
# vim /etc/locales
# echo "C.UTF-8 UTF-8" >> /etc/locales
# genlocales
# echo "LANG=xx_YY.UTF-8" > /etc/locale.conf

```

Setting /etc/fstab
Double check /etc/fstab to verify it looks correct from earlier.
```
# echo '/dev/sdXY / ext4 defaults 0 1' >> /etc/fstab
# echo '/dev/sdXY swap swap defaults 0 0' >> /etc/fstab
```

Sync ports
```
# ports -u
```
```
Install kernel from kernel.org or ports
# prt-get depinst linux
```

Install grub
```
(BIOS)
# prt-get depinst grub (installed already)
# grub-install /dev/sdX

(UEFI)
# prt-get depinst grub-efi (installed already)
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=StormFS-GRUB

# grub-mkconfig -o /boot/grub/grub.cfg
```
Configure Systemd
```
# systemd-machine-id-setup
# systemctl preset-all
Optional
systemctl disable systemd-networkd-wait-online

Mask udev's .link file for the default policy: 
ln -s /dev/null /etc/systemd/network/99-default.link
Name Network Card
cat > /etc/systemd/network/10-ether0.link << "EOF"
[Match]
# Change the MAC address as appropriate for your network device
MACAddress=12:34:45:78:90:AB

[Link]
Name=ether0
EOF
Static IP Configuration
cat > /etc/systemd/network/10-eth-static.network << "EOF"
[Match]
Name=<network-device-name>

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
Domains=<Your Domain Name>
EOF
DHCP Configuration
cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=<network-device-name>

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF
Optional
# systemctl disable systemd-resolved

cat > /etc/resolv.conf << "EOF"
# Begin /etc/resolv.conf

domain <Your Domain Name>
nameserver <IP address of your primary nameserver>
nameserver <IP address of your secondary nameserver>

# End /etc/resolv.conf
EOF
```
```
Configure /etc/hosts
cat > /etc/hosts << "EOF"
# Begin /etc/hosts

<192.168.0.2> <FQDN> [alias1] [alias2] ...
::1       ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF
If Clock Set to Local
cat > /etc/adjtime << "EOF"
0.0 0 0.0
0
LOCAL
EOF
Change Time
# timedatectl set-time YYYY-MM-DD HH:MM:SS
# timedatectl set-timezone TIMEZONE
# timedatectl list-timezones
Vconsole
# echo FONT=Lat2-Terminus16 > /etc/vconsole.conf
Creating the /etc/inputrc File 

cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF
Disabling Screen Clear
mkdir -pv /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << EOF
[Service]
TTYVTDisallocate=no
EOF

Change Default Dump Size
mkdir -pv /etc/systemd/coredump.conf.d

cat > /etc/systemd/coredump.conf.d/maxuse.conf << EOF
[Coredump]
MaxUse=5G
EOF
```
You might wanna install packages before rebooting to your installed lfs like 'xorg', 'networkmanager'?
```
# prt-get depinst xorg-server openssh dhcpcd networkmanager
```



You can run 'prt-get' to see the options on how to use it
```
# prt-get help
```

You can reboot now
```
# exit
# reboot
```

# Writing Ports
Writing ports is so damn easy, you can learn from existing ports or use `gentemplate.sh` script to generate a very basic port. 

Change to `contrib` directory to make new port. If you want to contribute your port, add it to `contrib` directory then make PR.
```
$ cd ports/contrib
$ ../gentemplate.sh http://dl.suckless.org/dwm/dwm-6.4.tar.gz
# Depends on: 

name=dwm
version=6.4
release=1
source=(http://dl.suckless.org/${name}/${name}-${version}.tar.gz)
```

Here you can see port created for dwm (dwm/Pkgfile). Now lets build it. Always build new ports using fakeroot to make sure port not broken and pollute the system.
```
$ cd dwm
$ fakeroot pkgmk
...
=======> Build result:
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/bin/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/man/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/man/man1/
-rw-r--r--  0 root   root     1874 Nov 19 00:45 usr/share/man/man1/dwm.1.gz
-rwxr-xr-x  0 root   root    56608 Nov 19 00:45 usr/bin/dwm
=======> WARNING: Footprint not found, creating new.
=======> Building '/var/cache/pkg/packages/dwm#6.4-1.pkg.tar.xz' succeeded.
```
When package is built, you can install it as root.
```
$ sudo pkgmk -i
```
Ok then the package is installed.

Here is `Pkgfile` with all options available to use:
```
# dependencies
# Depends on: pkg1 pkg2 pkg3

# port's name, make sure same as port directory
name=dwm

# port's version
version=6.4

# port's release, used for bump package, start with '1'. Always revert back to '1' when 'version=' is updated.
release=1

# port's source url, patch and needed files
source=(http://dl.suckless.org/${name}/${name}-${version}.tar.gz examplepatch.patch)

# for runit services, you can use 'run' or '<name>.run' and 'finish' or '<name>.finish' to install service into '/etc/sv/<name>/run' or '/etc/sv/<name>/finish'
# use '<name>.file' to install into '/etc/sv/<name>/file'
# use 'file' to install into '/etc/sv/<port name>/file'
# this runit files required in 'source=()' array
sv=(run finish name.run name.finish conf)

# by default build type is automatically detected but you can force it to use certain build type
# available build type is: meson_build, configure_build, cmake_build, python3_build, makefile_build and perlmodule_build
build_type=

# by default common build opts is already set, use this to add extra build opts
build_opt="-Denablethis=yes -Ddisablethat=no"

# patch (*.patch and *.diff files) is automatically applied using '-Np1' option.
# use this to use other patch options
patch_opt=""

# use this to keep static libraries (*.a)
keep_static=1

# use this to keep libtool files (*.la)
keep_libtool=1

# use this to keep locale files (/usr/share/locale/??)
keep_locale=1

pre_build() {
  # executed before package is build. Eg:
  ./autogen.sh
}

post_build() {
  # executed after package is built. Eg:
  mv -v $PKG/etc/X11/xinit/xinitrc.d/90-consolekit \
    $PKG/etc/X11/xinit/xinitrc.d/90-consolekit.sh
}

pre_build() {
  # this is replacement for regular 'build()' function.
  # if this function is used, both 'pre_build()' and 'pre_build()' is completely ignored.
  ./autogen.sh
  ./configure --prefix=/usr
  make
  # DESTDIR=$PKG is needed, but sometimes not, already handled by automated extension script
  # thats why build package using fakeroot very recommended for new ports
  make install
}
```

Thats some explanation for writing ports. For unused options, remove it. Keep it simple!.

Since the package manager and some utilities is used from CRUX, you can check CRUX wiki for extra info: https://crux.nu/Wiki/HomePage
