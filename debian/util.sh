#!/bin/bash
##### -*- mode:shell-script; indent-tabs-mode:nil; sh-basic-offset:2 -*-
##### Original Author: Travis Cross <tc@traviscross.com>
##### Hacks for more generic use: Ken Rice <krice@freeswitch.org>

set -e

ddir="."
[ -n "${0%/*}" ] && ddir="${0%/*}"
cd $ddir/../

#### lib

err () {
  echo "$0 error: $1" >&2
  exit 1
}

announce () {
  cat >&2 <<EOF

########################################################################
## $1
########################################################################

EOF
}

xread () {
  local xIFS="$IFS"
  IFS=''
  read $@
  local ret=$?
  IFS="$xIFS"
  return $ret
}

mk_dver () { echo "$1"; }
mk_uver () { echo "$1"; }
dsc_source () { dpkg-parsechangelog | grep '^Source:' | awk '{print $2}'; }
dsc_ver () { dpkg-parsechangelog | grep '^Version:' | awk '{print $2}'; }
up_ver () { mk_uver "$(dsc_ver)"; }
dsc_base () { echo "$(dsc_source)_$(dsc_ver)"; }
up_base () { echo "$(dsc_source)-$(up_ver)"; }

find_distro () {
  case "$1" in
    experimental) echo "sid";;
    unstable) echo "sid";;
    testing) echo "jessie";;
    stable) echo "wheezy";;
    oldstable) echo "squeeze";;
    *) echo "$1";;
  esac
}

find_suite () {
  case "$1" in
    sid) echo "unstable";;
    jessie) echo "testing";;
    wheezy) echo "stable";;
    squeeze) echo "oldstable";;
    *) echo "$1";;
  esac
}

#### debian/rules helpers

create_dbg_pkgs () {
  for x in $ddir/*; do
    test ! -d $x && continue
    test "$x" = "tmp" -o "$x" = "source" && continue
    test ! "$x" = "${x%-dbg}" && continue
    test ! -d $x/usr/lib/debug && continue
    mkdir -p $x-dbg/usr/lib
    mv $x/usr/lib/debug $x-dbg/usr/lib/
  done
}

check_repo_clean () {
  git diff-index --quiet --cached HEAD \
    || err "uncommitted changes present"
  git diff-files --quiet \
    || err "unclean working tree"
  git diff-index --quiet HEAD \
    || err "unclean repository"
  ! git ls-files --other --error-unmatch . >/dev/null 2>&1 \
    || err "untracked files or build products present"
}

get_last_release_ver () {
  dsc_ver | cut -f 1 -d- -
}

get_nightly_version () {
  dsc_ver | cut -f 1 -d- -
}

get_nightly_revision_human () {
  dsc_ver | cut -f 1 -d- -
}

create_orig () {
  {
    set -e
    local OPTIND OPTARG
    local uver="" hrev="" bundle_deps=false modules_list="" zl=9e
    while getopts 'bm:nv:z:' o "$@"; do
      case "$o" in
        n) uver="nightly";;
        v) uver="$OPTARG";;
        z) zl="$OPTARG";;
      esac
    done
    shift $(($OPTIND-1))
    if [ -z "$uver" ] || [ "$uver" = "nightly" ]; then
      uver="$(get_nightly_version)"
      hrev="$(get_nightly_revision_human)"
    fi
    local treeish="$1" dver="$(mk_dver "$uver")"
    local orig="../$(dsc_source)_$dver.orig.tar.xz"
    [ -n "$treeish" ] || treeish="HEAD"
    check_repo_clean
    git reset --hard "$treeish"
    mv .gitattributes .gitattributes.orig
    local -a args=(-e '\bdebian-ignore\b')
    grep .gitattributes.orig "${args[@]}" \
      | while xread l; do
      echo "$l export-ignore" >> .gitattributes
    done
    echo "$uver" > .version && git add -f .version
    git commit --allow-empty -m "nightly v$uver"
    git archive -v \
      --worktree-attributes \
      --format=tar \
      --prefix=$(dsc_source)-$uver/ \
      HEAD \
      | xz -c -${zl}v > $orig
    mv .gitattributes.orig .gitattributes
    git reset --hard HEAD~1 && git clean -fdx
  } 1>&2
  echo $orig
}

set_modules_quicktest () {
  cat > debian/modules.conf <<EOF
applications/mod_commands
EOF
}

create_dsc () {
  {
    set -e
    local OPTIND OPTARG modules_conf="" modules_list="" speed="normal" suite_postfix="" suite_postfix_p=false zl=9
    local modules_add=""
    while getopts 'f:m:p:s:u:z:' o "$@"; do
      case "$o" in
        f) modules_conf="$OPTARG";;
        m) modules_list="$OPTARG";;
        p) modules_add="$modules_add $OPTARG";;
        s) speed="$OPTARG";;
        u) suite_postfix="$OPTARG"; suite_postfix_p=true; ;;
        z) zl="$OPTARG";;
      esac
    done
    shift $(($OPTIND-1))
    local distro="$(find_distro $1)" orig="$2"
    local suite="$(find_suite $distro)"
    local orig_ver="$(echo "$orig" | sed -e 's/^.*_//' -e 's/\.orig\.tar.*$//')"
	echo "orig_ver: $orig_ver"
    local dver="${orig_ver}-${distro}+1"
	echo "dver: $dver"
    $suite_postfix_p && { suite="${distro}${suite_postfix}"; }
    [ -x "$(which dch)" ] \
      || err "package devscripts isn't installed"
    [ "$zl" -ge "1" ] || zl=1
    dch -b -m -v "$dver" --force-distribution -D "$suite" "Nightly build."
	echo "WTF!@#!@#1"
    git add debian/changelog && git commit -m "nightly v$orig_ver"
	echo "WTF!@#!@#2"
    dpkg-source -i.* -Zxz -z${zl} -b .
	echo "WTF!@#!@#3"
    dpkg-genchanges -S > ../$(dsc_base)_source.changes
	echo "WTF!@#!@#4"
    local dsc="../$(dsc_base).dsc"
	echo "WTF!@#!@#5"
    git reset --hard HEAD^ && git clean -fdx
	echo "WTF!@#!@#6"
  } 1>&2
  echo $dsc
}

fmt_debug_hook () {
    cat <<'EOF'
#!/bin/bash
export debian_chroot="cow"
cd /tmp/buildd/*/debian/..
/bin/bash < /dev/tty > /dev/tty 2> /dev/tty
EOF
}

get_sources () {
  local tgt_distro="$1"
  while read type path distro components; do
    test "$type" = deb || continue
    printf "$type $path $tgt_distro $components\n"
  done < /etc/apt/sources.list
}

get_mirrors () {
  get_sources "$1" | tr '\n' '|' | head -c-1; echo
}

build_debs () {
  {
    set -e
    local OPTIND OPTARG debug_hook=false hookdir="" cow_build_opts=""
    local keep_pbuilder_config=false
    local use_system_sources=false
    while getopts 'Bbdkt' o "$@"; do
      case "$o" in
        B) cow_build_opts="--debbuildopts '-B'";;
        b) cow_build_opts="--debbuildopts '-b'";;
        d) debug_hook=true;;
        k) keep_pbuilder_config=true;;
        t) use_system_sources=true;;
      esac
    done
    shift $(($OPTIND-1))
    local distro="$(find_distro $1)" dsc="$2" arch="$3"
    if [ -z "$distro" ] || [ "$distro" = "auto" ]; then
      if ! (echo "$dsc" | grep -e '-[0-9]*~[a-z]*+[0-9]*'); then
        err "no distro specified or found"
      fi
      local x="$(echo $dsc | sed -e 's/^[^-]*-[0-9]*~//' -e 's/+[^+]*$//')"
      distro="$(find_distro $x)"
    fi
    [ -n "$arch" ] || arch="$(dpkg-architecture | grep '^DEB_BUILD_ARCH=' | cut -d'=' -f2)"
    [ -x "$(which cowbuilder)" ] \
      || err "package cowbuilder isn't installed"
    local cow_img=/var/cache/pbuilder/base-$distro-$arch.cow
    cow () {
      if ! $use_system_sources; then
        cowbuilder "$@" \
          --distribution $distro \
          --architecture $arch \
          --basepath $cow_img
      else
        local keyring="$(mktemp /tmp/keyringXXXXXXXX.asc)"
        apt-key exportall > "$keyring"
        cowbuilder "$@" \
          --distribution $distro \
          --architecture $arch \
          --basepath $cow_img \
          --keyring "$keyring" \
          --othermirror "$(get_mirrors $distro)"
        rm -f $keyring
      fi
    }
    if ! [ -d $cow_img ]; then
      announce "Creating base $distro-$arch image..."
      local x=30
      while ! cow --create; do
        [ $x -lt 1 ] && break; sleep 120; x=$((x-1))
      done
    fi
    announce "Updating base $distro-$arch image..."
    local x=30
    local opts="--override-config"
    $keep_pbuilder_config && opts=""
    while ! cow --update $opts; do
      [ $x -lt 1 ] && break; sleep 120; x=$((x-1))
    done
    announce "Building $distro-$arch DEBs from $dsc..."
    if $debug_hook; then
      mkdir -p .hooks
      fmt_debug_hook > .hooks/C10shell
      chmod +x .hooks/C10shell
      hookdir=$(pwd)/.hooks
    fi
    cow --build $dsc \
      --hookdir "$hookdir" \
      --buildresult ../ \
      $cow_build_opts
  } 1>&2
  echo ${dsc%.dsc}_${arch}.changes
}

default_distros () {
  local host_distro="Debian"
  test -z "$(which lsb_release)" || host_distro="$(lsb_release -is)"
  case "$host_distro" in
    Debian) echo "sid jessie wheezy" ;;
    Ubuntu) echo "utopic trusty" ;;
    *) err "Unknown host distribution \"$host_distro\"" ;;
  esac
}

build_all () {
  local OPTIND OPTARG
  local orig_opts="" dsc_opts="" deb_opts="" modlist=""
  local archs="" distros="" orig="" depinst=false par=false
  while getopts 'a:bc:df:ijkl:m:no:p:s:tu:v:z:' o "$@"; do
    case "$o" in
      a) archs="$archs $OPTARG";;
      b) orig_opts="$orig_opts -b";;
      c) distros="$distros $OPTARG";;
      d) deb_opts="$deb_opts -d";;
      f) dsc_opts="$dsc_opts -f$OPTARG";;
      i) depinst=true;;
      j) par=true;;
      k) deb_opts="$deb_opts -k";;
      m) orig_opts="$orig_opts -m$OPTARG"; dsc_opts="$dsc_opts -m$OPTARG";;
      n) orig_opts="$orig_opts -n";;
      o) orig="$OPTARG";;
      t) deb_opts="$deb_opts -t";;
      u) dsc_opts="$dsc_opts -u$OPTARG";;
      v) orig_opts="$orig_opts -v$OPTARG";;
      z) orig_opts="$orig_opts -z$OPTARG"; dsc_opts="$dsc_opts -z$OPTARG";;
    esac
  done
  shift $(($OPTIND-1))
  [ -n "$archs" ] || archs="amd64 i386"
  [ -n "$distros" ] || distros="$(default_distros)"
  ! $depinst || aptitude install -y \
    rsync git less cowbuilder ccache \
    devscripts equivs build-essential
  [ -n "$orig" ] || orig="$(create_orig $orig_opts HEAD | tail -n1)"
  if [ -n "$modlist" ]; then
    local modtmp="$(mktemp /tmp/modules-XXXXXXXXXX.conf)"
    > $modtmp
    for m in "$modlist"; do printf '%s\n' "$m" >> $modtmp; done
    dsc_opts="$dsc_opts -f${modtmp}"; fi
  [ -n "$orig" ] || orig="$(create_orig $orig_opts HEAD | tail -n1)"
  mkdir -p ../log
  > ../log/changes
  echo; echo; echo; echo
  trap 'echo "Killing children...">&2; for x in $(jobs -p); do kill $x; done' EXIT
  if [ "${orig:0:2}" = ".." ]; then
    echo "true" > ../log/builds-ok
    for distro in $distros; do
      echo "Creating $distro dsc..." >&2
      local dsc="$(create_dsc $dsc_opts $distro $orig 2>../log/$distro | tail -n1)"
      echo "Done creating $distro dsc." >&2
      if [ "${dsc:0:2}" = ".." ]; then
        local lopts="-b"
        for arch in $archs; do
          {
            echo "Building $distro-$arch debs..." >&2
            local changes="$(build_debs $lopts $deb_opts $distro $dsc $arch 2>../log/$distro-$arch | tail -n1)"
            echo "Done building $distro-$arch debs." >&2
            if [ "${changes:0:2}" = ".." ]; then
              echo "$changes" >> ../log/changes
            else
              echo "false" > ../log/builds-ok
            fi
          } &
          $par || wait
          lopts="-B"
        done
      fi
    done
    ! $par || wait
  fi
  [ -z "$modlist" ] || rm -f $modtmp
  trap - EXIT
  cat ../log/changes
  test "$(cat ../log/builds-ok)" = true || exit 1
}

usage () {
  cat >&2 <<EOF
$0 [opts] [cmd] [cmd-opts]

options:

  -d Enable debugging mode.

commands:

  archive-orig

  build-all

    [ This must be run as root! ]

    -a Specify architectures
    -c Specify distributions
    -d Enable cowbuilder debug hook
    -f <modules.conf>
      Build only modules listed in this file
    -i Auto install build deps on host system
    -j Build debs in parallel
    -k Don't override pbuilder image configurations
    -m [ quicktest | non-dfsg ]
      Choose custom list of modules to build
    -n Nightly build
    -o <orig-file>
      Specify existing .orig.tar.xz file
    -t Use system /etc/apt/sources.list in build environment
    -u <suite-postfix>
      Specify a custom suite postfix
    -v Set version
    -z Set compression level

  build-debs <distro> <dsc-file> <architecture>

    [ This must be run as root! ]

    -B Binary architecture-dependent build
    -b Binary-only build
    -d Enable cowbuilder debug hook
    -k Don't override pbuilder image configurations
    -t Use system /etc/apt/sources.list in build environment

  create-dbg-pkgs

  create-dsc <distro> <orig-file>

    -f <modules.conf>
      Build only modules listed in this file
    -m [ quicktest | non-dfsg ]
      Choose custom list of modules to build
    -p <module>
      Include otherwise avoided module
    -s [ paranoid | reckless ]
      Set FS bootstrap/build -j flags
    -u <suite-postfix>
      Specify a custom suite postfix
    -z Set compression level

  create-orig <treeish>

    -n Nightly build
    -v Set version
    -z Set compression level

EOF
  exit 1
}

while getopts 'dh' o "$@"; do
  case "$o" in
    d) set -vx;;
    h) usage;;
  esac
done
shift $(($OPTIND-1))

cmd="$1"; [ -n "$cmd" ] || usage
shift
case "$cmd" in
  archive-orig) archive_orig "$@" ;;
  build-all) build_all "$@" ;;
  build-debs) build_debs "$@" ;;
  create-dbg-pkgs) create_dbg_pkgs ;;
  create-dsc) create_dsc "$@" ;;
  create-orig) create_orig "$@" ;;
  *) usage ;;
esac
