#!/usr/bin/env bash
set -Eeuo pipefail

STORAGE=$(pwd)/workdir
COUNTRY="CN"
DEBUG="Y"
ARCH="amd64"
mkdir -p $STORAGE

html(){
  echo "html: $1"
}

error(){
  printf "%b%s%b \E[1;34m❯ \E[1;31m ERROR: $1 \E[0m\n"
}

info(){
  printf "%b%s%b \E[1;34m❯ \E[1;36m Info: $1 \E[0m\n"
}

: "${URL:=""}"    # URL of the PAT file to be downloaded.

if [ -f "$STORAGE/dsm.ver" ]; then
  BASE=$(<"$STORAGE/dsm.ver")
else
  # Fallback for old installs
  BASE="DSM_VirtualDSM_42962"
fi

if [ -n "$URL" ]; then
  BASE=$(basename "$URL" .pat)
  if [ ! -f "$STORAGE/$BASE.system.img" ]; then
    BASE=$(basename "${URL%%\?*}" .pat)
    : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
    BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')
  fi
fi

if [[ -f "$STORAGE/$BASE.boot.img" ]] && [[ -f "$STORAGE/$BASE.system.img" ]]; then
  info "Previous installation found"
  exit 0  # Previous installation found
fi

html "Please wait while Virtual DSM is being installed..."

DL=""
DL_CHINA="https://cndl.synology.cn/download/DSM"
DL_GLOBAL="https://global.synologydownload.com/download/DSM"

[[ "${URL,,}" == *"cndl.synology"* ]] && DL="$DL_CHINA"
[[ "${URL,,}" == *"global.synology"* ]] && DL="$DL_GLOBAL"

if [ -z "$DL" ]; then
  [ -z "$COUNTRY" ] && setCountry
  [ -z "$COUNTRY" ] && info "Warning: could not detect country to select mirror!"
  [[ "${COUNTRY^^}" == "CN" ]] && DL="$DL_CHINA" || DL="$DL_GLOBAL"
fi

[ -z "$URL" ] && URL="$DL/release/7.2.1/69057-1/DSM_VirtualDSM_69057.pat"

BASE=$(basename "${URL%%\?*}" .pat)
: "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')

if [[ "$URL" != "file://$STORAGE/$BASE.pat" ]]; then
  rm -f "$STORAGE/$BASE.pat"
fi

rm -f "$STORAGE/$BASE.agent"
rm -f "$STORAGE/$BASE.boot.img"
rm -f "$STORAGE/$BASE.system.img"

[[ "$DEBUG" == [Yy1]* ]] && set -x

# Check filesystem
FS=$(stat -f -c %T "$STORAGE")

if [[ "${FS,,}" == "overlay"* ]]; then
  info "Warning: the filesystem of $STORAGE is OverlayFS, this usually means it was binded to an invalid path!"
fi

if [[ "${FS,,}" == "fuse"* ]]; then
  info "Warning: the filesystem of $STORAGE is FUSE, this extra layer will negatively affect performance!"
fi

if [[ "${FS,,}" != "fat"* && "${FS,,}" != "vfat"* && "${FS,,}" != "exfat"* && "${FS,,}" != "ntfs"* && "${FS,,}" != "msdos"* ]]; then
  TMP="$STORAGE/tmp"
else
  TMP="/tmp/dsm"
  TMP_SPACE=2147483648
  SPACE=$(df --output=avail -B 1 /tmp | tail -n 1)
  SPACE_MB=$(( (SPACE + 1048575)/1048576 ))
  if (( TMP_SPACE > SPACE )); then
    error "Not enough free space inside the container, have $SPACE_MB MB available but need at least 2 GB." && exit 93
  fi
fi

rm -rf "$TMP" && mkdir -p "$TMP"

# Check free diskspace
ROOT_SPACE=536870912
SPACE=$(df --output=avail -B 1 / | tail -n 1)
SPACE_MB=$(( (SPACE + 1048575)/1048576 ))
(( ROOT_SPACE > SPACE )) && error "Not enough free space inside the container, have $SPACE_MB MB available but need at least 500 MB." && exit 96

MIN_SPACE=8589934592
SPACE=$(df --output=avail -B 1 "$STORAGE" | tail -n 1)
SPACE_GB=$(( (SPACE + 1073741823)/1073741824 ))
(( MIN_SPACE > SPACE )) && error "Not enough free space for installation in $STORAGE, have $SPACE_GB GB available but need at least 8 GB." && exit 94

# Check if output is to interactive TTY
if [ -t 1 ]; then
  PROGRESS="--progress=bar:noscroll"
else
  PROGRESS="--progress=dot:giga"
fi

# Download the required files from the Synology website

ROOT="Y"
RDC="$STORAGE/dsm.rd"

if [ ! -f "$RDC" ]; then

  MSG="Downloading installer..."
  PRG="Downloading installer ([P])..."
  info "Install: $MSG" && html "$MSG"

  RD="$TMP/rd.gz"
  POS="65627648-71021835"
  VERIFY="b4215a4b213ff5154db0488f92c87864"
  LOC="$DL/release/7.0.1/42218/DSM_VirtualDSM_42218.pat"

  rm -f "$RD"
  #/run/progress.sh "$RD" "$PRG" &
  { curl -r "$POS" -sfk -S -o "$RD" "$LOC"; rc=$?; } || :

  #fKill "progress.sh"
  (( rc != 0 )) && error "Failed to download $LOC, reason: $rc" && exit 60

  SUM=$(md5sum "$RD" | cut -f 1 -d " ")

  if [ "$SUM" != "$VERIFY" ]; then

    PAT="/install.pat"
    rm "$RD"
    rm -f "$PAT"

    html "$MSG"
    #/run/progress.sh "$PAT" "$PRG" &
    { wget "$LOC" -O "$PAT" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

    #fKill "progress.sh"
    (( rc != 0 )) && error "Failed to download $LOC , reason: $rc" && exit 60

    tar --extract --file="$PAT" --directory="$(dirname "$RD")"/. "$(basename "$RD")"
    rm "$PAT"

  fi

  cp "$RD" "$RDC"

fi

if [ -f "$RDC" ]; then

  { xz -dc <"$RDC" >"$TMP/rd" 2>/dev/null; rc=$?; } || :
  (( rc != 1 )) && error "Failed to unxz $RDC, reason $rc" && exit 91

  { (cd "$TMP" && cpio -idm <"$TMP/rd" 2>/dev/null); rc=$?; } || :

  if (( rc != 0 )); then
    ROOT="N"
    { (cd "$TMP" && fakeroot cpio -idmu <"$TMP/rd" 2>/dev/null); rc=$?; } || :
    (( rc != 0 )) && error "Failed to extract $RDC, reason $rc" && exit 92
  fi

  git clone https://mirror.ghproxy.com/https://github.com/technorabilia/syno-extract-system-patch $TMP/syno-extract-system-patch

  docker build --tag syno-extract-system-patch $TMP/syno-extract-system-patch

fi

rm -rf "$TMP" && mkdir -p "$TMP"

info "Install: Downloading $BASE.pat..."

MSG="Downloading DSM..."
PRG="Downloading DSM ([P])..."
html "$MSG"

PAT="$TMP/$BASE.pat"
rm -f "$PAT"

if [[ "$URL" == "file://"* ]]; then

  cp "${URL:7}" "$PAT"

else

  #/run/progress.sh "$PAT" "$PRG" &

  { wget "$URL" -O "$PAT" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

  #fKill "progress.sh"
  (( rc != 0 )) && error "Failed to download $URL , reason: $rc" && exit 69

fi

[ ! -f "$PAT" ] && error "Failed to download $URL" && exit 69

SIZE=$(stat -c%s "$PAT")

if ((SIZE<250000000)); then
  error "The specified PAT file is probably an update pack as it's too small." && exit 62
fi

MSG="Extracting downloaded image..."
info "Install: $MSG" && html "$MSG"

if { tar tf "$PAT"; } >/dev/null 2>&1; then

  tar xpf "$PAT" -C "$TMP/."

else

  docker run --rm -v $TMP:/data syno-extract-system-patch \
    /data/$BASE.pat \
    /data/.

fi

MSG="Preparing system partition..."
info "Install: $MSG" && html "$MSG"

BOOT=$(find "$TMP" -name "*.bin.zip")
[ ! -f "$BOOT" ] && error "The PAT file contains no boot image." && exit 67

BOOT=$(echo "$BOOT" | head -c -5)
unzip -q -o "$BOOT".zip -d "$TMP"

SYSTEM="$STORAGE/$BASE.system.img"
rm -f "$SYSTEM"

# Check free diskspace
SYSTEM_SIZE=4954537983
SPACE=$(df --output=avail -B 1 "$STORAGE" | tail -n 1)
SPACE_MB=$(( (SPACE + 1048575)/1048576 ))

if (( SYSTEM_SIZE > SPACE )); then
  error "Not enough free space in $STORAGE to create a 5 GB system disk, have only $SPACE_MB MB available." && exit 97
fi

if ! touch "$SYSTEM"; then
  error "Could not create file $SYSTEM for the system disk." && exit 98
fi

if [[ "${FS,,}" == "xfs" || "${FS,,}" == "btrfs" || "${FS,,}" == "bcachefs" ]]; then
  { chattr +C "$SYSTEM"; } || :
  FA=$(lsattr "$SYSTEM")
  if [[ "$FA" != *"C"* ]]; then
    error "Failed to disable COW for system image $SYSTEM on ${FS^^} filesystem (returned $FA)"
  fi
fi

if ! fallocate -l "$SYSTEM_SIZE" "$SYSTEM"; then
  if ! truncate -s "$SYSTEM_SIZE" "$SYSTEM"; then
    rm -f "$SYSTEM"
    error "Could not allocate file $SYSTEM for the system disk." && exit 98
  fi
fi

PART="$TMP/partition.fdisk"

{       echo "label: dos"
        echo "label-id: 0x6f9ee2e9"
        echo "device: $SYSTEM"
        echo "unit: sectors"
        echo "sector-size: 512"
        echo ""
        echo "${SYSTEM}1 : start=        2048, size=     4980480, type=83"
        echo "${SYSTEM}2 : start=     4982528, size=     4194304, type=82"
} > "$PART"

sfdisk -q "$SYSTEM" < "$PART"

MOUNT="$TMP/system"
rm -rf "$MOUNT" && mkdir -p "$MOUNT"

MSG="Extracting system partition..."
info "Install: $MSG" && html "$MSG"

HDA="$TMP/hda1"
IDB="$TMP/indexdb"
PKG="$TMP/packages"
HDP="$TMP/synohdpack_img"

[ ! -f "$HDA.tgz" ] && error "The PAT file contains no OS image." && exit 64
mv "$HDA.tgz" "$HDA.txz"

[ -d "$PKG" ] && mv "$PKG/" "$MOUNT/.SynoUpgradePackages/"
rm -f "$MOUNT/.SynoUpgradePackages/ActiveInsight-"*

[ -f "$HDP.txz" ] && tar xpfJ "$HDP.txz" --absolute-names -C "$MOUNT/"

if [ -f "$IDB.txz" ]; then
  INDEX_DB="$MOUNT/usr/syno/synoman/indexdb/"
  mkdir -p "$INDEX_DB"
  tar xpfJ "$IDB.txz" --absolute-names -C "$INDEX_DB"
fi

LABEL="1.44.1-42218"
OFFSET="1048576" # 2048 * 512
NUMBLOCKS="622560" # (4980480 * 512) / 4096
MSG="Installing system partition..."

if [[ "$ROOT" != [Nn]* ]]; then

  tar xpfJ "$HDA.txz" --absolute-names --skip-old-files -C "$MOUNT/"

  info "Install: $MSG" && html "$MSG"

  mke2fs -q -t ext4 -b 4096 -d "$MOUNT/" -L "$LABEL" -F -E "offset=$OFFSET" "$SYSTEM" "$NUMBLOCKS"

else

  fakeroot -- bash -c "set -Eeu;\
        tar xpfJ $HDA.txz --absolute-names --skip-old-files -C $MOUNT/;\
        printf '%b%s%b' '\E[1;34m❯ \E[1;36m' 'Install: $MSG' '\E[0m\n';\
        mke2fs -q -t ext4 -b 4096 -d $MOUNT/ -L $LABEL -F -E offset=$OFFSET $SYSTEM $NUMBLOCKS"

fi

rm -rf "$MOUNT"
echo "$BASE" > "$STORAGE/dsm.ver"

if [[ "$URL" == "file://$STORAGE/$BASE.pat" ]]; then
  rm -f "$PAT"
else
  mv -f "$PAT" "$STORAGE/$BASE.pat"
fi

mv -f "$BOOT" "$STORAGE/$BASE.boot.img"
rm -rf "$TMP"

{ set +x; } 2>/dev/null
[[ "$DEBUG" == [Yy1]* ]] && echo

html "Installation finished successfully..."
