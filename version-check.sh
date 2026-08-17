#!/bin/bash
# A script to list version numbers of critical development tools

# If you have tools installed in other directories, adjust PATH here AND
# in ~lfs/.bashrc (section 4.4) as well.

LC_ALL=C 
PATH=/usr/bin:/bin

bail() { echo "FATAL: $1"; exit 1; }
grep --version > /dev/null 2> /dev/null || bail "grep does not work"
sed '' /dev/null || bail "sed does not work"
sort   /dev/null || bail "sort does not work"

ver_check()
{
   if ! type -p $2 &>/dev/null
   then 
     echo "ERROR: Cannot find $2 ($1)"; return 1; 
   fi
   v=$($2 --version 2>&1 | grep -E -o '[0-9]+\.[0-9\.]+[a-z]*' | head -n1)
   if printf '%s\n' $3 $v | sort --version-sort --check &>/dev/null
   then 
     printf "OK:    %-9s %-6s >= $3\n" "$1" "$v"; return 0;
   else 
     printf "ERROR: %-9s is TOO OLD ($3 or later required)\n" "$1"; 
     return 1; 
   fi
}

ver_kernel()
{
   kver=$(uname -r | grep -E -o '^[0-9\.]+')
   if printf '%s\n' $1 $kver | sort --version-sort --check &>/dev/null
   then 
     printf "OK:    Linux Kernel $kver >= $1\n"; return 0;
   else 
     printf "ERROR: Linux Kernel ($kver) is TOO OLD ($1 or later required)\n" "$kver"; 
     return 1; 
   fi
}

# Coreutils first because --version-sort needs Coreutils >= 7.0
if sort --version |& grep -q uutils; then
    ver_check Coreutils  sort     0.8 || bail "Uutils Coreutils too old, stop"
else
    ver_check Coreutils  sort     8.1 || bail "GNU Coreutils too old, stop"
fi
ver_check Bash           bash     3.2
ver_check Binutils       ld       2.13.1
ver_check Bison          bison    2.7
ver_check Diffutils      diff     2.8.1
ver_check Findutils      find     4.2.31
ver_check Gawk           gawk     4.0.1
ver_check GCC            gcc      5.4
ver_check "GCC (C++)"    g++      5.4
ver_check Grep           grep     2.5.1a
ver_check Gzip           gzip     1.3.12
ver_check M4             m4       1.4.10
ver_check Make           make     4.0
ver_check Patch          patch    2.5.4
ver_check Perl           perl     5.8.8
ver_check Python         python3  3.4
ver_check Sed            sed      4.1.5
ver_check Tar            tar      1.22
ver_check Texinfo        texi2any 5.0
ver_check Xz             xz       5.0.0
ver_kernel 5.10


echo "BFS host dependency checks:"

if ! type -p pkg-config &>/dev/null
then
   bail "pkg-config is required for BFS bootstrap"
else
   echo "OK:    pkg-config found ($(pkg-config --version 2>/dev/null | head -n1))"
fi

if pkg-config --exists libarchive 2>/dev/null
then
   archive_version=$(pkg-config --modversion libarchive 2>/dev/null)
   echo "OK:    libarchive development files found (${archive_version})"
else
   bail "libarchive development files not found (Debian/Ubuntu: install libarchive-dev)"
fi

if ! type -p bsdtar &>/dev/null
then
   bail "bsdtar is required for BFS bootstrap (Debian/Ubuntu: install libarchive-tools)"
else
   bsdtar_version=$(bsdtar --version 2>/dev/null | head -n1)
   echo "OK:    bsdtar found (${bsdtar_version})"
fi

if ! printf '#include <gmp.h>\nint main(void){return 0;}\n' | gcc -x c - -lgmp -o /tmp/bfs-gmp-check 2>/dev/null
then
   rm -f /tmp/bfs-gmp-check
   bail "GMP development files not found or unusable (Debian/Ubuntu: install libgmp-dev)"
else
   rm -f /tmp/bfs-gmp-check
   echo "OK:    GMP development files found and link correctly"
fi

if ! printf '#include <mpfr.h>\nint main(void){mpfr_t x; mpfr_init(x); mpfr_clear(x); return 0;}\n' | gcc -x c - -lmpfr -lgmp -o /tmp/bfs-mpfr-check 2>/dev/null
then
   rm -f /tmp/bfs-mpfr-check
   bail "MPFR development files not found or unusable (Debian/Ubuntu: install libmpfr-dev)"
else
   rm -f /tmp/bfs-mpfr-check
   echo "OK:    MPFR development files found and link correctly"
fi


if ! pkg-config --exists libtirpc 2>/dev/null
then
   bail "libtirpc development files not found (Debian/Ubuntu: install libtirpc-dev)"
else
   tirpc_version=$(pkg-config --modversion libtirpc 2>/dev/null)
   echo "OK:    libtirpc development files found (${tirpc_version})"
fi

if ! printf '#include <rpc/rpc.h>\nint main(void){return 0;}\n' | \
     gcc -x c - $(pkg-config --cflags --libs libtirpc 2>/dev/null) \
     -o /tmp/bfs-tirpc-check 2>/dev/null
then
   rm -f /tmp/bfs-tirpc-check
   bail "libtirpc headers/libraries are present but cannot be compiled and linked"
else
   rm -f /tmp/bfs-tirpc-check
   echo "OK:    libtirpc headers and libraries compile/link correctly"
fi


if ! type -p autoreconf &>/dev/null
then
   bail "autoreconf is required for BFS bootstrap (Debian/Ubuntu: install autoconf)"
else
   autoreconf_version=$(autoreconf --version 2>/dev/null | head -n1)
   echo "OK:    autoreconf found (${autoreconf_version})"
fi

if mount | grep -q 'devpts on /dev/pts' && [ -e /dev/ptmx ]
then echo "OK:    Linux Kernel supports UNIX 98 PTY";
else echo "ERROR: Linux Kernel does NOT support UNIX 98 PTY"; fi

alias_check() {
   if $1 --version 2>&1 | grep -qi $2
   then printf "OK:    %-4s is $2\n" "$1";
   else printf "ERROR: %-4s is NOT $2\n" "$1"; fi
}
echo "Aliases:"
alias_check awk GNU
alias_check yacc Bison
alias_check sh Bash

echo "Compiler check:"
if printf "int main(){}" | g++ -x c++ -
then echo "OK:    g++ works";
else echo "ERROR: g++ does NOT work"; fi
rm -f a.out

if [ "$(nproc)" = "" ]; then
   echo "ERROR: nproc is not available or it produces empty output"
else
   echo "OK: nproc reports $(nproc) logical cores are available"
fi
