#!/bin/bash
#
# ddrexcue-helper.sh
# Wire Moore 2024
# https://github.com/c-o-pr/ddrescue-helper

#set -x
TRACE=false

usage() {
  cat << EOF
*** $(basename "$0"): Usage

  -u | -m | -f <device>
     :: UNMOUNT / MOUNT / FSCK

  -c [ -X ] [ -M ] <label> <source> <destination>
     :: COPY with ddrescue creating bad-block and slow read maps.
     :: Use /dev/null for <destination> to SCAN <source>.
     :: -X to scrape during SCAN
     :: -M passed to ddrescue to retrim

  -p | -s | -q | -z | -Z [ -K ] <label> <device>
     :: REPORT / ZAP
     -p | -s
        REPORT files affected by read errors | slow reads.
          macOS: HFS+
          Linux: ext2/3/4. NTFS, HFS+
     -q PLOT a graph of the read-rate log on terminal using gluplot.
     -z ZAP PREVIEW: Print a list of bad blocks, but don't try to ZAP them.
     -Z ZAP: Overwrite drive blocks specified by the MAP to help trigger
        <device> to re-allocate underlying sectors. The block is read tested and
        only written if the read fails.
     -K ZAP 4096 byte blocks instead of 512.
  <device> is a /dev entry for an block storage device. For MOUNT, UNMOUNT or
  FSCK, if <device> is a whole drive, all its partitions are affected. MOUNT and
  UNMOUNT ignore the EFI Service Parition (first partition of GPT dformat rive).

  <source> <destination> /dev block storage devices or plain files.

  <label> is a name for a directory created by COPY to contain ddrescue map and
  rate-log data. Temporary files and reports are also saved there.
EOF
}

help() {
  usage
  cat << EOF

  FSCK (-f) works with the following volume types:
    macOS: FAT, ExFAT, HFS+, APFS
    Limux: ext2/3/4, FAT, ExFAT, NTFS, HFS+

  With MOUNT (-m), <device> can be a UUID to be removed from /etc/fstab. In
  certain use cases, an /etc/fstab entry for a volume UUID can end up orphaned.

  With COPY (-c) <destination> IS OVERWRITTEN from <source>

  If <source> and <destinatio> are /dev entries for block storage devices
  <destination> becomes a clone of <source>.

  Use /dev/null for <destination> to SCAN <source> producing a bad block map
  and rate log without making a COPY.

  If <source> is a /dev and <destinatio> is a plain file, destination becomes
  an image of the device.

  If <source> and <destinatio> are plan files, a file copy is made.

  On macOS, use the "rdisk" form of the /dev to get fastest drive access (e.g.,
  /dev/rdisk7).

DESCRIPTION

  UNMOUNT (-u) prevents auto-moounting. This is critical to ensure the integrity
  of COPY. If <device> is a drive, all its partitions are unmouonted (including
  APFS containers on macOS). The GPT EFI partition is not included as it is not
  normally auto-mounted.

  MOUNT (-m) merely disables auto-mount prevention and remounts partition(s).

  Note: Mount behavior under Linux systemd + udev has  subtlties such as
  on-demand moounts and esoteric paths for mountpoints. But it can mostly be
  left to itself. If you want to force Linux to mount use:

  sudo mount -t <fs-type> -o uid=$USER,gid=$USER,force,rw <device> <directory>

  MOUNT will accept a UUID without a <device> and remove an /etc/fstab entry
  with that UUID. This is an alternative to editing /etc/fstab by hand when
  an entry becomes orphaned.

  FSCK (-f) checks and repairs supported volumes on partitions. You may, or may
  not, want to use FSCK on <destination> if there were read errors during copy.
  If you are attempting to return a drive to service with ZAP, you may want to
  check <source>, although not necessarily. You need to think through your
  recovery intentions to determine next steps after COPY.

  COPY (-c) <source> to <destination> using ddrescue to build metadata for
  unreadable (bad) blocks (block map) and create a rate log. This metadata is
  placed in a sub-directory named <label> created in the current working
  directory. Any existing MAP metadata for <label> is sanity-checked against the
  specfied <source> and <destinatio>.

  COPY RESUMES when existing block MAP data is found for the combination of
  <label>, <source>, <destination> and ddrescue is not "Finished". COPY will
  continue until ddrescue determines the disposition of all blocks at the
  source. Remove (or move) the metadata directory to start over from begining of
  the source.

  The COPY <destination> can be /dev/null which creates the effect of a SCAN
  for read errors on <source>, and produces the MAP data in <label> for use with
  REPORT and ZAP.

  COPY implies UNMOUNT of <source> and <destination>. MOUNT after COPY must be
  performed explicitly.

  The boot drive is not allowed with COPY. (Maybe it should be allowed for
  SCAN).

  -X Enables SCAN "scrape." See the GNU ddrescue documentation. To save time for
  SCAN, scrape is disabled by default, avoiding waiting for additional reads in
  bad areas that aren't likely to change the error afftected-files REPORT. SCAN
  without -X implies that some blocks are not read, Which could cause REPORT
  (-p) to list files as being affected by errors for blocks that are readble.
  For a drive that stores large media files (MB+) unscraped areas are unlikely
  to be part of multiple files. Scrape is enabled by default for COPY.

  `-M`: is passed to ddrescue as the retrim option, which marks all failed
  blocks as untrimmed, causing them to be retried.

  It's common for a failing drive to disconnectr during a COPY "scape" pass.
  Run ddrescue-helper again with the parameters to resume.

  The MAP metadata created by COPY for drives and partitions feeds REPORT, PLOT
  and ZAP. It's unclear if bad block reallocations can be triggered through file
  ZAP but it's allowed.

  REPORT (-p, -s) lists files affected by errors or slow reads recorded in the
  map metadata for <label>. SLOW is less than 1 MB/s (this should be user
  selectable).

  REPORT is meaningless for a file copy.

  PLOT (-q) produces a graph of read-rate performance from the ddrescue
  rate-log to a dumb terminal. This can provide a picture of overall drive
  health.

  For REPORT, <device> must be a partition (e.g. /dev/rdisk2s2) with a supported
  filesystem. MAP metadata can be either for the partition (e.g., /dev/rdisk7s2)
  or for the whole drive (e.g. /dev/rdisk7). The necessary block address offsets
  for proper location of files will be automatically calculated.

  ZAP (-Z) blocks listed as errors in an existing block map. This uses dd to
  write specific discrete blocks in an attempt to make the drive re-allocate
  them. ZAP attempts to read and writes only if the read fails.

  ZAP PREVIEW (-z) of lets you see what ZAP will touch without zapping. It's
  just another way of visualizing the ddrescue error map.

  -K Switch ZAP to 4096 byte block size. This is experimental for 4K Advanced
  Format drives which may present as 512 sectors but internall manage as 4K.

  ZAP uses dd(1). For old versions of dd(1) or systems which don't support the
  idirect and odirect flags, you may need to consider "raw" device access.

  ZAPPING plain file blocks has not been well tested.

  MAP metadata from an unfinished COPY or DCAN can be used with REPORT and ZAP.

RECOVERY OVERVIEW

  The main point of this helper is to make is easy to create a COPY a drive,
  partition or file when source media errors prevent a conventional methods.
  The value of this script assumes that media errors may be interfering with
  access to data, but the drive is functional.

  Making an COPY is an obvious important first step to recovery from bad blocks.

  Persistent UNMOUNT ensures integrity of COPY.

  After COPY, ddrescue output summarizes completion status and error locations.

  FSCK checks basic integrity of a destination after COPY.

  For some filesystems (noted above) the ddrescue read error data can be used to
  REPORT files affected by read errors and slow reads. When you are recovering a
  drive or partition, this information helps you assess the quality of the copy.
  Affected files can be restored from backup or rescued individually using this
  helper. You could also be set affected files aside to prevent reuse of those
  areas of the drive from being reused. by the file system.

  If you can't access a volume at all, bad blocks can be ZAPPED which may
  trigger a spinning drive to re-allocated them. This might return a drive with
  a small number of baad blocks to service. ZAP read tests blocks before writing
  them. The risk of ZAPPING is low because the blocks are already unreadable.
  However, whem bad blocks get re-allocated, this can lead to subsequent events
  which are dangerous to data if the bad blocks were occupied by key filesystem
  metadata.

  Note that the concerns for making a COPY are completely seperable from the
  concerns of REPORTs about affected-files, FSCK and ZAPPING. You have to fit
  the puzzle pieces together.

  Forensics is a complex topic beyond the scope of this script.

THIS SCRIPT DEPENDS ON
  Bash V3+

  GNU ddrescue
    macOS: Use [ macports | brew ] install ddrescue
    Linux: Available via standard repositories as gddrescue.

  Linux systemd, udev (this should not be neccessary but no way to test for now)

  On macOS, FSCK supports for HFS+, msdos, and ExFAT (and APPS) volumes.
  macOS REPORT supports HFS+.

  Linux file system support depends on the following packages available from
  standard repositories.
    dosfstools, exfatprogs, hfsutils, and ntfsprogs

  Gnuplot for PLOT function.

ALSO SEE
  GNU ddrescue Manual
  https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

SOURCE OF THIS SCRIPT
  https://github.com/c-o-pr/ddrescue-helper

by /wire 2024
EOF
}

usage_packages() {
  _advise echo "You can obtain packages using apt (Linux) or with homebrew or macports (macOS)"
  _advise echo "If you unfamiliar with packages on macOS, use Homebrew."
  _advise echo "https://brew.sh/"
}

#######################################
# FUNCTIONS SUPPORTING USER ENVIRONMENT
#######################################

cleanup() {
  echo > /dev/null
}
_abort() {
  local zap_in_progress="$1"
  local device="$2"

  echo; echo '*** Aborted'
  if [ "$zap_in_progress" == "true" ]; then
    flush_io "$device"
  fi
  cleanup
  echo
  exit 1
}
trap "_abort false" SIGINT SIGTERM

#_suspend() {
#  trap _abort SIGINT SIGTERM
#  suspend
#  return 0
#}
#trap _suspend SIGTSTP

_DEBUG() {
  [ $TRACE ] || _color_fx_wrapper "$_cfx_debug" \
    echo "DEBUG: ${FUNCNAME[1]}: $@" >&2
}
# These colors below to the xterm-256color termcap personality.
# Colors chosen to work with dark and light themes.
_cfx_debug=11 # red-orange
_cfx_error=160 # red
_cfx_warn=214 # gold
_cfx_advise=228 # yellow 51 # cyan
_cfx_info=246 # grey
_error() {
  local caller=$( [ ${FUNCNAME[1]} != "main" ] && \
                  echo "${FUNCNAME[1]}:" || \
                  echo "" )
  _color_fx_wrapper "$_cfx_error" echo '***' "$caller $@" >&2
}
_warn() {
  _color_fx_wrapper "$_cfx_warn" "${@}"
}
_advise() {
  _color_fx_wrapper "$_cfx_advise" "${@}"
}
_info() {
  _color_fx_wrapper "$_cfx_info" "${@}"
}

# MACRO to add color terminal output if
# tput is available and output is a terminal
#
if which tput > /dev/null && \
   [ -t 1 -a -t 2 ] && [ "$TERM" == "xterm-256color" ]; then
  _color_fx_wrapper() {
    # Pass in echo or printf with params.
    # Bash goofiness to preserve input param grouping
    # Get a local array of all params with ""s:
    local color="$1"
    # Have to cast as array to use array shift
    local ary=( "${@}" )
    # Use array indexing to shift out first 2 elements, preserve "" grouping
    ary=( "${ary[@]:1}" );
    # Use color for info messaging
    tput setaf "$color"
    # Output remainder of command
    "${ary[@]}"
    # Reset color
    tput sgr0
  }
else
  # Output is not a terminal
  _color_fx_wrapper() {
    local ary=( "${@}" )
    ary=( "${ary[@]:1}" );
    "${ary[@]}"
  }
fi

get_OS() {
  if which diskutil > /dev/null; then
    echo "macOS"
  elif which lsblk > /dev/null; then
    echo "Linux"
  else
    echo "(Unknown host OS)"
  fi
}

escalate() {
# XXX not used
  _info echo "Escalating privileges..."
  if ! sudo echo -n; then
    _error "sudo failed"
    exit 1
  fi
}

absolute_path() {
  # Run in a subshell to prevent hosing the current working dir.
  # XXX This breaks if current user cannot cd into parent of CWD.
  (
    if [ -z $1 ]; then return 1; fi
    if ! cd "$(dirname "$1")"; then return 1; fi
    case "$(basename $1)" in
      ..)
        echo "$(dirname $(pwd))";;
      .)
        echo "$(pwd)";;
      *)
        # Strip extra leading /
        echo "$(pwd)/$(basename "$1")" | tr -s /
        ;;
    esac
  )
}

is_uuid() {
  # Force uppercase of the input as a side-effect of is UUID
  # Older bash treats " as part of =~ pattern
  #
  # Linux bug workaround, Linux volume UUIDs are treated as strings not numbers
  # Force:
  #   XXXX-XXXX
  #   XXXXXXXXXXXXXXXX
  #   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

  case $(get_OS) in
    macOS)
      if [[ "$1" =~ ^[A-Za-z0-9]{8}-([A-Za-z0-9]{4}-){3}-*[A-Za-z0-9]{12}$ ]]; then
        echo "$1"
        return 0
      fi
      return 1
      ;;
    Linux)
      # XXXX-XXXX
      if [[ "$1" =~ ^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$ ]]; then
        echo "$1" | tr 'a-z' 'A-Z'
        _DEBUG "$1" | tr 'a-z' 'A-Z'
        return 0
      fi
      # XXXXXXXXXXXXXXXX
      if [[ "$1" =~ ^[A-Za-z0-9]{16}$ ]]; then
        echo "$1" | tr 'a-z' 'A-Z'
        _DEBUG "$1" | tr 'a-z' 'A-Z'
        return 0
      fi
      # xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      if [[ "$1" =~ ^[A-Za-z0-9]{8}-([A-Za-z0-9]{4}-){3}-*[A-Za-z0-9]{12}$ ]]; then
        echo "$1" | tr 'A-Z' 'a-z'
        _DEBUG "$1" | tr 'A-Z' 'a-z'
        return 0
      fi
      return 1
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac

  return 1
}

dd_supports_direct_io() {
  case $(get_OS) in
    macOS)
      dd if=/dev/null iflag=direct > /dev/null 2>&1
      ;;
    Linux)
      dd --help | grep -F "direct I/O" > /dev/null 2>&1
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

##########################
# FUNCTIONS SUPPORTING ZAP
##########################

#  od -t xC
#  sudo hdparm --read-sector "$block" "$target" > /dev/null

read_block() {
  local target="$1"
  local block="$2"
  local direct_option="${3:-true}"
  local K4="${4:-false}"

#  echo; echo $direct_option $K4 >&2

  local option=""
  if [ "$(get_OS)" == "Linux" ]; then
    option="iflag=sync"
  fi
  if $direct_option; then
    if ! [ -z "$option" ]; then
      option+=",direct"
    fi
  else
    option="iflag=direct"
  fi

  local blocksize=512
  if $K4; then blocksize=4096; fi

  # Don't quote $option as empty arg confuses dd.
  cat /dev/null >| ./TMP
  sudo dd status=none bs=$blocksize count=1 iseek="$block" \
    if="$target" $option > /dev/null 2> ./TMP
  result=$?
  if [ -s ./TMP ] && ! grep -F -q -i "input/output error" ./TMP; then
    echo; cat ./TMP
  fi
#  cat >&2 <<EOF
#EOF
  # For unknown reasons, a write seek after a read failure may fail,
  # but waiting a bit before the next I/O helps
  return $result
}

#  echo sudo hdparm --yes-i-know-what-i-am-doing --write-sector "block" "target"

write_block() {
  local target="$1"
  local block="$2"
  local direct_option="${3:-true}"
  local K4="${4:-false}"

#  echo; echo $direct_option $K4 >&2

  # On macOS sync and direct produce different
  # write failure responses:
  # sync,direct -> bad file descriptor
  # direct -> bad file descriptor
  # sync -> resource busy

  local option="oflag=sync"
  if $direct_option; then
    option+=",direct"
  fi

  local blocksize=512
  if $K4; then blocksize=4096; fi

  cat /dev/null >| ./TMP
  sudo dd status=none bs=$blocksize count=1 oseek="$block" \
    conv=notrunc if=/dev/random of="$target" $option 2> ./TMP
  result=$?

  # If output is I/O error then squelch. Print other errors.
  if [ -s ./TMP ] && ! grep -F -q -i "input/output error" ./TMP; then
    echo; cat ./TMP
    result=128
  fi
#  cat >&2 <<EOF
#EOF
  return $result
}

zap_sequence() {
  local target="$1"
  local block="$2"
  local count="$3"
  local K4="${4:-false}"

  local result t
  local direct_option="$(dd_supports_direct_io "$target")"

  _info printf \
    "zap_sequence: Processing $target %d (0x%X) %d:\n" \
    "$block" "$block" "$count"

  local slow_time=3
  local max_extend=2
  local range=$count
  local read_time
  local this_io_failed
  local last_io_failed=false
  #
  # If a read or write fails just try to write the next block without
  # reading because write failure is more indicative of bad drive health
  # than read failure. If write doesn't succeed there's no hope for ZAP.
  #
  # reading because it's likely to be If the last block in the extent either
  # fails or is slow, extend the range of ZAP up to max_extend blocks.
  #
  for ((c = 1; c <= range; c++)); do

    this_io_failed=false

    if ! $last_io_failed; then
      printf "  %d [0x%X] read" "$block" "$block"
      # Time plus time for a slow read
      let t="$(date +%s)"+slow_time
      read_block "$target" "$block" "$direct_option" "$K4"
      result=$?
      # Time after read
      t2=$(date +%s)
      # read_time calculation inc -1 works around imprecision of date on macOS
      # which is limited to whole seconds
      read_time=$((t2 - (t - slow_time) - 1))
#      echo -n " $t $t2 $read_time"

      # If failed or slow
      if [ "$read_time" -gt 0 ] || [ $result -ne 0 ]; then
        if [ $result -ne 0 ]; then
          echo -n " FAILED ($result, ${read_time}s), write"
        else
          echo -n " SLOW (${read_time}s), write"
        fi
        this_io_failed=true
      else
        echo " OK"
      fi
    else
      printf "  %d [0x%X] write" "$block" "$block"
    fi

    if $this_io_failed || $last_io_failed; then
      write_block "$target" "$block" "$direct_option" "$K4"
      result=$?
      if [ "$result" -ne 0 ] ; then
        echo " FAILED ($result)"
        this_io_failed=true
      else
        echo -n " OK, read"
        read_block "$target" "$block" "$direct_option" "$K4"
        if ! [ $? ]; then
          echo " FAILED"
          this_io_failed=true
        else
          echo " OK"
          this_io_failed=false
        fi
      fi
    fi

    # Read issue on last block so extend
    if $this_io_failed; then
      last_io_failed=true
      if (( c == range && c < (count + max_extend) )); then
        _advise echo "zap_sequence: extending 1 block, max $max_extend"
        let range+=1
      fi
    else
      last_io_failed=false
    fi

    let block+=1
    sleep 0.1
  done

  _info echo "zap_sequence: done, $range blocks"
  # Side effect, return actual number of blocks processed
  return $range
}

zap_from_mapfile() {
  local device="$1"
  local map_file="$2"
  local zap_blocklist="$3" # side-effect
  local preview="${4:-true}"
  local K4="${5:-false}"

  local blocksize=512
  if $K4; then blocksize=4096; fi

  # First do no harm
  if [ "$preview" != "true" ] && \
     [ "$preview" != "false" ]; then
    _error "parameter error"
    return 1
  fi
  _info echo "zap_from_mapfile: blocklist: $zap_blocklist"
  _info echo "zap_from_mapfile: blocksize: $blocksize"
  if ! $preview; then
    if dd_supports_direct_io "$device"; then
      _info echo "USING DIRECT I/O: true"
    else
      _info echo "USING DIRECT I/O: false"
    fi
  fi

  # Parse map for zap
  extract_error_extents_from_map_file "$map_file" | \
   ddrescue_map_extents_bytes_to_blocks "$blocksize" | \
   sort -n >| "$zap_blocklist"

  if [ ! -s "$zap_blocklist" ]; then
    _info echo "Missing or empty bad-block list"
    return 1
  fi
  if grep '[^0-9 ]' "$zap_blocklist"; then
    _info echo "Bad-block list should be a list of numbers"
    return 1
  fi

  local device_format="$(get_device_format "$device")"
  if [ -z "$device_format" ]; then
    exit 1
  fi
  # Count blocks and sanity check
  cat "$zap_blocklist" | \
    {
    local _max_blocks=2000
    local _max_extent=500
    local total_blocks=0
    local address_error=false
    local format_error=false
    while read block count; do
      if [ -z $block ] || [ -z $count ]; then
        _error "block list format error"
        format_error=true
      fi
      if [ $count -eq 0 ]; then
        _error "zero length extent"
        format_error=true
      fi
      if ! sanity_check_block_range \
              "$device_format" "$block" "$count" "$K4"; then
        _warn "bad block(s) in partition table or volume header"
#        address_error=true
      fi
      if [ $count -gt "$_max_extent" ]; then
        _warn echo "*** zap_from_mapfile: Extent > $_max_extent blocks"
      fi
      let total_blocks+=$count
    done
    if $format_error; then
      return 1
    fi
    if [ "$total_blocks" -gt "$_max_blocks" ]; then
      _error "Total blocks $total_blocks > max allowed ($_max_blocks)"
      return 1
    fi
    if $address_error; then
      return 1
    fi
  }
  if [ $? -ne 0 ]; then return 1; fi

  # Do zap
  if $preview; then
    _info echo "zap_from_mapfile: ZAP PREVIEW: $Device"
    printf "%12s %4s %11s %5s\n" "Block" "Count" "(hex)"
    cat "$zap_blocklist" | \
    { \
      total_blocks=0
      while read block count; do
        printf "%12d %-4d %#12x %#5.3x\n" \
          "$block" "$count" "$block" "$count"
        let total_blocks+=$count
      done
      _info echo "zap_from_mapfile: done, total $total_blocks blocks"
    }
  else
    ( printf "\n\n###\n"; date) >> "$zap_blocklist-LOG"
    _warn echo "Blocks are read tested and skipped if readable"
    _warn echo -n "CONTINUE? [y/N] "
    read -r response
    if [[ ! $response =~ ^[Yy]$ ]]; then
       _info echo "zap_from_mapfile: ...STOPPED."
       return 1
    fi
    cat "$zap_blocklist" | \
    { \
      total_blocks=0
      while read block count; do
        zap_sequence "$device" "$block" "$count" "$K4"
        let total_blocks+=$?
      done
      _info echo "zap_from_mapfile: done, total $total_blocks blocks"
      flush_io "$device" false
    } | tee -a "$zap_blocklist-LOG"
# | tee >((grep "FAIL") >> "$zap_blocklist-LOG")

  fi
  return 0
}

#####################################
# FUNCTIONS FOR SMART BLOCK REPORTING
#####################################

zap_from_smart() {
  return 1
}

start_smart_selftest() {
  echo "Starting long self test"
  if ! sudo smartctl -t long "$1"; then
    if sudo smartctl -a "$1" | grep -i -A C "in progress"; then
      echo "SELF TEST IN PROGRESS"
    else
      echo "CAN'T START SELF TEST"
      return 1
    fi
  else
    echo "TEST STARTED"
  fi
}

smart_scan_drive() {
  local drive="$1"
  local smart_blocklist="$2" # side-effect

# XXX EXPERIMENTAL
# XXX THIS APPROACH DIDN'T WORK OUT DUE TO LIMITATIONS
# XXX IN SMART REPORTING

  # Zaps on the fly to get SMART test to move ahead

  if [ -z $drive ]; then exit 1; fi

  start_smart_selftest "$drive"

  # Fixed count
  local fixed_count=0
  local finished=false
  while [ $finished == false ]; do

    while sudo smartctl -a "$drive" | grep -i -C 3 "in progress"; do
      sleep 10;
#      echo WAITING
    done

    local x=$(sudo smartctl -a "$drive" | grep "^#" | \
               sed -e 's/\# *//' -e 's/  .*//' | tail -1)

    echo "log events $x, handled $fixed_count"

    #
    # XXX ADD A EXECUTION COMPLETE STATUS CHECK
    # When no more errors are listed since last test, work is done
    # Otherwise restart the test
    #
    if [ $fixed_count -eq $x ]; then finished=true; continue; fi

    create_smartctl_error_blocklist "$drive" "$smart_blocklist"

#   zap_from_smart "$drive"

    start_smart_selftest "$drive"

    fixed_count=$x
  done
}

############################################
# FUNCTIONS FOR BLOCK LISTS, REPORTS AND ZAP
############################################

sanity_check_block_range() {
  local device_format="$1"
  local block="$2"
  local count="$3"
  local K4="${4:-false}"

  # XXX NOT YET USED
  # Populate with checks for metadata areas that could be catastrophic
  # to overwrite, like the partition table, superblock, etc.
  # At least check for very low and very high numbered blocks
  # relative to the device range.
  case "$device_format" in
    file) return 0 ;;
    gpt)
      local device_size="$(get_device_size "$device")"
      if ! $K4; then
        if (( block <= 40 )) || \
           (( block >= device_size - 41 )); then
          return 1
        fi
      else
        if (( block <= 40 / 8)) || \
           (( block >= (device_size / 8) - (41 / 8) )); then
          return 1
        fi
      fi
      return 0
      ;;
    mbr) return 0 ;;
    hfsplus)
      local device_size="$(get_device_size "$device")"
      if ! $K4; then
        if (( block <= 2 )) || \
           (( block >= device_size - 2 )); then
          return 1
        fi
      else
        if (( block == 0 )) || \
           (( block == (device_size / 8) - 1  )) ; then
          return 1
        fi
      fi
      ;;
    apfs) return 0 ;;
    ext*) return 0 ;;
    msdos) return 0 ;;
    ntfs) return 0 ;;
    *)
      _info echo "unknown device type $device_type"
      return 1
      ;;
  esac
}

extract_error_extents_from_map_file() {
  grep -v "^#" "$1" | \
  grep -E '0x[0-9a-fA-F]+ +0x[0-9a-fA-F]+' | \
  grep -e - -e / -e '*'
}

extents_to_list() {
  local partition_offset="$1"
  local device_blocksize="$2"
  local fs_blocksize="$3"

  if [ $# -lt 3 ]; then
    _error "missing parameters"
    return 1
  fi
  _DEBUG $partition_offset $device_blocksize $fs_blocksize
  local block count
  while IFS=" " read block count; do
    block=$(( (block - partition_offset) / (fs_blocksize / device_blocksize) ))
    _DEBUG $block
    if [ -z $block ] || [ $block -eq 0 ] || \
       [ -z $count ] || [ $count -eq 0 ]; then break; fi
    for (( i = 0; i < count; i++ )); do
      echo $(( block + i ))
    done
  done
}

ddrescue_map_extents_bytes_to_blocks() {
  local blocksize="${1:-512}"

  # This code depends on the input being a monotonically increasing list of
  # block addrs and lengths.
  #
  # Convert hex map data for byte addresses and extents
  # into decimal blocks.
  # Input (512):
  #   Addr   Len
  #   0x800  0x200  extraneous
  # Output:
  #   4      1
  # 0 or 0 are skipped
  #
  _DEBUG "blocksize: $blocksize"

  # Input addresses are bytes but naturally aligned to blocks because drive I/O
  # are LBAs, typically 512 bytes.
  #
  local addr len
  if (( blocksize == 512 )); then
    # Simply divide to convert to blocks.
    while read addr len x; do
      addr=$(( addr / blocksize ))
      len=$(( (len + blocksize - 1) / blocksize ))
      echo $addr $len
    done
    exit
  fi

  # When comverting to 4096 byte blocks, handle 512 byte block extents which
  # overlap within 4096 byte blocks.
  local prev_addr prev_len next_addr a l

  # Read ahead 1 extent to permit detection of overlap by next extent. Must
  # calculate extents in bytes (or 512 blocks) then convert to 4096 blocks as
  # last step to properly account for overlap.
  read addr len x
  prev_addr=$addr
  prev_len=$len
  next_addr=$((prev_addr + prev_len))
#  echo NEXT $next_addr 1>&2
  remainder=false
  while read addr len x; do
    if (( addr > next_addr )); then
      # The current extent doesn't overlap the previous so output previous.
      a=$(( prev_addr / blocksize ))
      l=$(( (prev_len + blocksize - 1) / blocksize ))
#      echo $prev_addr $prev_len
      echo $a $l
      prev_addr=$addr
      prev_len=$len
      remainder=false
    else
      # The cuurent extent overlaps the previous, so accumulate its length.
#      echo ADDR $addr $len 1>&2
      prev_len=$((prev_len + (next_addr - addr) + len))
      remainder=true
    fi
    next_addr=$((addr + len))
#    printf "%#7x, %d, %6d, %#12x\n" $prev_len $addr $len $next_addr 1>&2
#    echo NEXT $N 1>&2
  done
#  echo $prev_addr $prev_len
  if $remainder; then
    # Finish up last extent
    a=$(( prev_addr / blocksize ))
    l=$(( (prev_len + blocksize - 1) / blocksize ))
    echo $a $l
  fi
}

parse_ddrescue_map_for_fsck() {
  local map_file="$1"
  local fsck_blocklist="$2" # filename for EXTENTS side-effect
  local partition_offset="${3:-0}"
  local device_blocksize="${4:-512}"
  local fs_blocksize="${5:-4096}" # For ext2/3/4 reports, req debugfs

  _info echo "FS BLOCKSIZE: $fs_blocksize" 1>&2

  # Pull a list of _error extents from the map
  # convert them from byte to block addresses
  # and emit a list of corresponding blocks.
  #
  # The map file is a list of byte addresses.
  # EXTENTS just for debugging the calculation.
  #
  # The partition offset is in drive sectors
  # The block addresses may be in filesystem blocks
  #
  if [ $# -lt 2 ]; then
    _error "missing parameters"
    return 1
  fi
  local block count
  extract_error_extents_from_map_file "$map_file" | \
    ddrescue_map_extents_bytes_to_blocks $device_blocksize | \
    tee "${fsck_blocklist}-EXTENTS" | \
    sort -n | \
    extents_to_list "$partition_offset" "$device_blocksize" "$fs_blocksize"
}

create_ddrescue_error_blocklist() {
  local device="$1"
  local map_file="$2"
  local fsck_blocklist="$3" # side-effect
  local partition_offset="${4:-0}"

  # Translate a map file into a list of blocks that can be
  # used with fsck -B to list files.
  #
  # Check if map file is a drive-relative or partition relative.
  # If drive relative, compute the partition offset and subtract
  # it from the drive block addresses, as fsck is partition-relative
  # addressing.
  #
  # fsck_hfs expects block addresses to be drive relative
  # fsck is relative to partition, so if <device> is a drive
  # then compute offset.

  if [ $# -lt 3 ]; then
    _error "missing parameters"
    return 1
  fi
  _info echo "ERROR BLOCKLIST: $fsck_blocklist"
  parse_ddrescue_map_for_fsck \
    "$map_file" \
    "$fsck_blocklist" \
    "$partition_offset" \
    "$(get_device_blocksize "$device")" \
    "$(get_fs_blocksize_for_file_lookup "$device")" \
      >| "$fsck_blocklist"

  if [ ! -s "$fsck_blocklist" ]; then
    _info echo "NO ERROR BLOCKS"
    exit 0
  fi
}

parse_rate_log_for_fsck() {
  local rate_log="$1"
  local slow_blocklist="$2" # Output file name
  local slow_limit="$3" # Regions slower than this are selected
  local partition_offset="${4:-0}"
  local device_blocksize="${5:-512}"
  local fs_blocksize="${6:-4096}" # For ext2/3/4 reports, req debugfs

  local n addr rate ave_rate bad_areas bad_size interval block count
  grep -h -E "^ *[0-9]+  0x" "${rate_log}"-* | \
    while IFS=" " read n addr rate ave_rate bad_areas bad_size; do
      # Log entires are issued once per second. Compute a sparse list of extents
      # based on the rate for that second to cover the region with 10 samples at
      # evenly spaced intervals. Advanced Format drives are fundamentally 4096
      # byte formats, so place samples on 4096 byte intervals
      # Interger div rounds down.
      #
      if (( rate < "$slow_limit" )); then
        interval=$(( rate / 50 / 4096 ))
        for (( i=0; i<=interval; i++ )); do
          echo $(( addr + ( i * interval * 4096 ) )) 0x200
        done
      fi
    done | \
    # The compendium of logs may duplicate slow regions so filter dups out
    # EXTENTS just for debugging the calculation
    uniq | \
    sort -n | \
    ddrescue_map_extents_bytes_to_blocks $device_blocksize | \
    tee "${slow_blocklist}-EXTENTS" | \
    extents_to_list "$partition_offset" "$device_blocksize" "$fs_blocksize"
}

create_slow_blocklist() {
  local device="$1"
  local rate_log="$2"
  local slow_blocklist="$3" # Output file name
  local partition_offset="${4:-0}"
  local slow_limit="${5:-1000000}" # Regions slower than this are selected

  _info echo "SLOW BLOCKLIST (less than $slow_limit bytes per sec)"
  parse_rate_log_for_fsck \
    "$rate_log" \
    "$slow_blocklist" \
    "$slow_limit" \
    "$partition_offset" \
    "$(get_device_blocksize "$device")" \
    "$(get_fs_blocksize_for_file_lookup "$device")" \
      >> "$slow_blocklist"

  if [ ! -s "$slow_blocklist" ]; then
    _info echo "NO SLOW BLOCKS"
    exit 0
  fi
}

create_smartctl_error_blocklist() {
  local device="$1"
  local smart_blocklist="$2" # Output file name

  echo "Creating a UNIQUE bad block list from smartcrl event log"
  # Only errors may include repeated blocks, eliminate dups
  sudo smartctl -l selftest "$device" | \
    grep "#" | sed 's/.* //' | grep -v -- "-" | \
    uniq | sort -n > "$smart_blocklist"

  if [ ! -s "$fsck_blocklist" ]; then
    _info echo "NO ERROR BLOCKS"
    exit 0
  fi
}

################################
# FUNCTIONS FOR RUNNING ddrescue
################################

make_ddrescue_shim() {
  # Cteate a temp helper script so ddrescue to be restarted
  # after a read timeout withoout a sudo password request
  # XXX PASS SIGNAL TO SCAN SCRIPT
  local shim_script="${1:-ddrescue-shim.sh}"

  if ! which ddrescue > /dev/null; then
    _info echo "ddrescue not found on PATH"
    return 1
  fi

  # Don't let an old helper script bollacks the work
  if [ -s "$shim_script" ]; then
    if ! rm -f "$shim_script"; then
      _info echo "error, coouldn't replace exosting helper"
      return 1
    fi
  fi
  cat >| "$shim_script" <<"EOF"
#!/bin/bash
_cleanup() {
  if [ ! -z "$user" ] && [ "$user" != root ]; then
    echo "$(basename "$0"): Metadata: setting ownership to $user"
    if [ -f "$map_file" ]; then
      chown "$user" "$map_file" "${map_file}.bak"
    fi
    if ls "${rate_log}-"* > /dev/null 2>&1; then
      chown "$user" "${rate_log}-"*
    fi
    if [ -f "$event_log" ]; then
      chown "$user" "$event_log"
    fi
    if [ -f "$dest" ]; then
      echo "$(basename "$0"): $dest: setting ownership to $user"
      chown "$user" "$dest"
    fi
  fi
}
_abort() {
  echo "*** $(basename "$0"): aborted"
  _cleanup
  exit 1
}
trap _abort SIGINT SIGTERM

source="$1"
dest="$2"
map_file="$3"
event_log="$4"
rate_log="$5"
trim="${6:-true}"
scrape="${7:-false}"
K4="${8:-false}"
retrim="${9:-false}"
user="${10:-$USER}"

next_rate_log_name() {
  local rate_log="$1"

  # ddrescue overwrites the rate log for any run that makes progress,
  # so give each run is own log file, named xxx-0...xxx-N
  # If ddrescue is "Finished" no rate log is output from subsequent runs.

  local last_log
  local c=0
  # Get name of latest rate log; squelch _error if none.
  last_log="$(ls -1 -t  ${rate_log}-* 2> /dev/null | head -1)"
  if [ -z "$last_log" ]; then
    # XXX If more than 1000 rate logs the naming gets janky but it
    # will still work.
    echo "${rate_log}-000"
  else
    # xxx-000 -> c=0+1 --> xxx-001
    # Strings beginning with 0 are treated as octal so trim
    c=$(echo "${last_log##*-}" | sed 's/^0*//')
    let c++
    echo $(printf "${rate_log}-%03d" $c)
  fi
}

# Make sure that missing paramters don't lead to
# a disaster with ddrescue
#if [ ${#args[@]} -lte 5 ]; then

missing=false
args=("$@")
for (( i=0; i<=4; i++ )); do
  if [ -z "${args[$i]}" ]; then missing=true; fi
done
if $missing; then
  echo "$(basename "$0"): missing parameter(s)"
  echo "  source=\"$1\" dest=\"$2\" map_file=\"$3\""
  echo "  event_log=\"$4\" rate_log=\"$5\""
  echo "  scrape=\"$6\" trim=\"$7\" K4=\"$8\" retrim=\"$9\""
  echo "  user=\"$10\""
  exit 1
fi

# -b x (block size default 512)
# -f force (allow output to /dev)
# -n no scrape
# -N no trim
# -T Xs Maximum time since last successful read allowed before giving up.
# -r x read retries
# -b sector size
# -A try again
opts="-f -T 10m -r0"
if ! $trim; then opts+=" -N"; fi
if ! $scrape; then opts+=" -n"; fi
if $K4; then opts+=" -b 4096"; fi
if $retrim; then opts+=" -M"; fi
opts+=" --log-events=$event_log"

tries=0
max=10
finished=false
while [ $tries -lt $max ]; do
  let tries+=1
  ddrescue $opts --log-rates="$(next_rate_log_name $rate_log)" \
    "$source" "$dest" "$map_file"
  result=$?
#  if [ $result -ne 0 ]; then break; fi
  if grep -q -F "Finished" "$map_file"; then finished=true; break; fi
  sleep 1
done
if [ $result -ne 0 ]; then
  echo "*** $(basename "$0"): ddrescue non-zero exit status ($result)"
  _cleanup
  exit $result
fi
if ! $finished; then
  echo "*** $(basename "$0"): COPY INCOMPLETE: stopping after $max tries"
  _cleanup
  exit $result
fi
_cleanup
exit 0
EOF
  chmod 755 "$shim_script"
}

run_ddrescue() {
  local copy_source="$1"
  local copy_dest="$2"
  local map_file="$3"
  local event_log="$4"
  local rate_log="$5"
  # For rescue, apply trim and scrape to salvage as much data as possible
  local trim="${6:-true}"
  local scrape="${7:-false}"
  local K4="${8:-false}"
  local retrim="${9:-false}"

  local result
  local shim_script="./ddrescue-shim.sh"
  make_ddrescue_shim "$shim_script"
  _DEBUG "$(pwd)"
  sudo "$shim_script" "$copy_source" "$copy_dest" "$map_file" \
       "$event_log" "$rate_log" \
       "$trim" "$scrape" "$K4" "$retrim" "$USER"
  result=$?
  return $result
}

get_commandline_from_map() {
  local map_file="$1"

  if [ ! -s "$map_file" ]; then
    _info echo "no map file"
    exit 1
  fi
  grep "# Command line: ddrescue" "$map_file"
}

resource_matches_map() {
  local device="$1"
  local map_file="$2"

  if [ -s "$map_file" ]; then
    # Spaces around $device matter!
    if grep -F -q "# Mapfile. Created by GNU ddrescue" "$map_file"; then
       grep -F -q " $device " "$map_file"
    else
      return 1
    fi
  else
    _info echo "$map_file" >&2
    return 1
  fi
}

get_device_from_ddrescue_map() {
  local map_file="$1"

  # This depends on the map command line having the format
  # ddrescie <options> <source> <destination> <map-file>
  #
  # XXX Won't work for device names (files) with white-space
  # XXX E.g., file names
  #
  local x
  x=$(grep "Command line: ddrescue" "$map_file" | \
        sed -E 's/^.+ ([^ ]+) [^ ]+ [^ ]+$/\1/')
  if [ -z $x ]; then
    _error "map device = \"\""
    exit 1
  fi
  echo "$x"
}

############################
# FUNCTIONS FOR DEVICE LOGIC
############################

resource_exists() {
  [ -f "$1" ] || [ -L "$1" ] || [ -b "$1" ] || [ -c "$1" ]
}

flush_io() {
  local device="$1" # Not used on macOS
  local flush_all="${2:-true}"

  case $(get_OS) in
    macOS)
      _info echo -n "flush_io: "
      if $flush_all || [ -f "$device" ]; then
        _info echo -n "purge, "
        sudo purge
      fi
      _info echo -n "sync, "
      sync
      _info echo "done"
      ;;
    Linux)
      _info echo -n "flush_io: $device: "
      if $flush_all || [ -f "$device" ]; then
        _info echo -n "drop caches, "
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
      fi
      _info echo -n "sync, "
      sync
      if ! [ -f "$device" ]; then
        _info echo -n "flushbufs, "
        sudo blockdev --flushbufs $device
         # Flush device onboard buffer, if supported by drive
        _info echo -n "flush drive, "
        sudo hdparm -F $device
      fi
      _info echo "done"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_inode() {
  local path="$1"

  if [ ! -f "$path" ]; then echo "[inode lookup failed]"; return 1;  fi
  case $(get_OS) in
    macOS)
      stat -f %i "$path"
      ;;
    Linux)
      stat --printf %i "$path"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_symlink_target() {
  local path="$1"

  case $(get_OS) in
    macOS)
      # stat exit status returns 0 regardless wheether symnlink is resolved.
      target=$( stat -f %Y "$path" 2> /dev/null )
      if [ ! -z "$target" ]; then echo "$target"; else return 1; fi
      ;;
    Linux)
      return 1
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_alias_target() {
  local path="$1"

  if [ ! -f "$path" ]; then return 1;  fi
  case $(get_OS) in
    macOS)
      # Heredoc exit status returns 0 regardless wheether alias is resolved.
      target=$( osascript -e'on run {a}
        set p to POSIX file a
        tell app "finder"
          set Xype to kind of item p
          if Xype is "Alias" then
            set myPath to original item of item p
            set myPOSIXPath to quoted form of POSIX path of (myPath as text)
            do shell script "echo " & myPOSIXPath
          end if
        end tell
      end' "$(echo "$path")" 2> /dev/null )
      if [ ! -z "$target" ]; then echo "$target"; else return 1; fi
      ;;
    Linux)
      # No alias semtantics on Linux, just a kind of plain file.
      return 1
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

cat > /dev/null <<"EOF"
get_partition_table_type() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep -q "GUID_partition_scheme" && echo "gpt" || echo ""
      ;;
    Linux)
      lsblk --raw -n -d -o PTTYPE "$device"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}
EOF

get_partition_uuid() {
  local device="$1"

  # XXX Not used.
  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Disk / Partition UUID:" | \
        sed -E 's/^.+ ([-0-9A-F]+$)/\1/'
      ;;
    Linux)
      return 1
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_volume_uuid() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Volume UUID:" | \
        sed -E 's/^.+ ([-0-9A-F]+$)/\1/'
      ;;
    Linux)
      local _id="$(lsblk -n -d -o UUID "$device")"
      # Bug workaround, Linux volume UUIDs are treated as strings not numbers
      # Force:
      #   XXXX-XXXX
      #   XXXXXXXXXXXXXXXX
      #   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      if [[ "$_id" =~ ^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$ ]] || \
         [[ "$_id" =~ ^[A-Za-z0-9]{16}$ ]]; then
        echo "$_id" | tr 'a-z' 'A-Z'
      else
        echo "$_id" | tr 'A-Z' 'a-z'
      fi
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_volume_name() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Volume Name:" | \
        sed -E 's/^.+: +(.+)$/\1/'
      ;;
    Linux)
      lsblk -n -d -o LABEL "$device"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_device_format() {
  local device="$1"

  # OUTPUT: file, gpt, mbr, hfsplus, ntfs, msdos, exfat, ext2/3/4, apfs
  #
  # XXX vfat for all versions of FAT with LFN (long filename) support;
  # XXX msdos for all versions of FAT without LFN support (8.3-only).

  local format
  if [ -f "$device" ]; then echo "file"; return 0; fi

  case $(get_OS) in
    macOS)
      # If drive, get format
      if [ "$device" == "$(strip_partition_id "$device")" ]; then
        format="$( diskutil info "$device" | \
                   grep -F "Content (IOContent):" | \
                   sed -E 's/^.+: *([-_A-Za-z ]+)$/\1/' | \
                   sed -e 's/FDisk_partition_scheme/mbr/' \
                       -e 's/GUID_partition_scheme/gpt/' )"
      else
        # Is volume
        format="$( diskutil info "$device" | \
          grep -F "Type (Bundle):" | \
          sed -E 's/^.+: *([a-z]+) *$/\1/' | \
            sed 's/hfs/hfsplus/' )"
      fi
      ;;
    Linux)
      # If drive, get format
      if [ "$(strip_partition_id "$device")" == "$device" ]; then
        format="$( lsblk -n -d -o PTTYPE "$device" | \
                   sed -e 's/dos/mbr/' )"
      else
        # Is volume
        format="$( lsblk -n -d -o FSTYPE "$device" | \
                   tr 'A-Z' 'a-z' | \
                   sed -e 's/vfat/msdos/' \
                   )"
      fi
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac

  if [ -z "$format" ]; then
    _error "unknown format $device"
    return 1
  fi
  echo "$format"

}

get_device_blocksize() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Device Block Size:" | \
        sed -E 's/^.+: *([0-9]+).*$/\1/'
      ;;
    Linux)
#       echo 512
      lsblk --raw -n -d -o PHY-SEC "$device" # --raw no whitespace
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_fs_blocksize_for_file_lookup() {
  local device="$1"

  # NTFS and macOS HFS+ -B works with drive blocks (sectors)
  # not filesystem blocks
  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Device Block Size:" | \
        sed -E 's/^.+: *([0-9]+).*$/\1/'
      ;;
    Linux)
      if [[ "$(get_device_format "$device")" =~ ext[234] ]]; then
        # Ext2/3/4
        sudo blkid -p -o value --match-tag FSBLOCKSIZE "$device"
      else
        echo $(get_device_blocksize "$device")
      fi
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

is_gpt() {
  local device="$1"
#  _info echo \"$(get_partition_table_type "$device")\" >&2
  [ "$(get_device_format "$device")" == "gpt" ]
}

is_mounted() {
  local device="$1"

  local mounted
  case $(get_OS) in
    macOS)
      mounted=$(diskutil info "$device" | \
                grep "Mounted:" | \
                sed -E 's/^.+: +([^ ].+)$/\1/')
      [ "$mounted" == "Yes" ]
      ;;
    Linux)
      [ ! -z "$(lsblk -n -d -o MOUNTPOINT "$device")" ]
      return
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

is_hfsplus() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | grep -q Apple_HFS
      ;;
    Linux)
      [ "$(get_device_format "$device")" == "hfsplus" ]
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

is_ntfs() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | grep -q NTFS
      ;;
    Linux)
      [ "$(get_device_format "$device")" == "ntfs" ]
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

is_ext() {
  local device="$1"

  case $(get_OS) in
    macOS)
      return 1
      ;;
    Linux)
      [[ "$(get_device_format "$device")" =~ ^ext[234]$ ]]
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

is_device() {
  # Is device v. regular file or /dev/null
  # /dev/null is regarded as NOT a device
  local device="$1"
  local quiet="${2:-true}"

  if ! [[ "$device" =~ ^/dev ]]; then return 1; fi

  if [[ "$device" =~ ^/dev/null$ ]]; then return 1; fi

  # device specifies "/dev/" so make sure it exists
  if ! resource_exists "$device"; then
    return 2;
  fi

  case $(get_OS) in
    macOS)
      if $quiet; then
        diskutil list "$device" > /dev/null
      else
        diskutil list "$device"
      fi
      ;;
    Linux)
      if $quiet; then
        lsblk -o NAME,FSTYPE,SIZE,LABEL,UUID,MOUNTPOINT "$device" > /dev/null
      else
        lsblk -o NAME,FSTYPE,SIZE,LABEL,UUID,MOUNTPOINT "$device"
      fi
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

get_device_offset() {
  local device="$1"

  # Output in 512 byte blocks

  local offset
  case $(get_OS) in
    macOS)
      offset=$( diskutil info "$device" | \
        grep -F "Partition Offset:" | \
        sed -E 's/^.*\(([0-9]*).*$/\1/' )
      ;;
    Linux)
      # Offset is returned in device blocks
      offset=$(lsblk -n -d -o START "$device")
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
  if ! [[ "$offset" =~ ^[0-9]+$ ]]; then
    _error "offset lookup failed"
    return 1
  fi
  echo $offset
}

get_device_size() {
  local device="$1"

  # Output in 512 byte blocks

  local size
  case $(get_OS) in
    macOS)
      size="$( diskutil info "$device" | \
               grep -F "Disk Size:" | \
               sed -E 's/^[^\(]+\(([0-9]+) Bytes\).+$/\1/' )"
      ;;
    Linux)
      # Offset is returned in device blocks
      size=$(lsblk -b -n -d -o SIZE "$device")
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac

  if ! [[ "$size" =~ ^[0-9]+$ ]]; then
    _error "size lookup failed"
    return 1
  fi
  echo $(( $size / 512 ))
}

device_is_boot_drive() {
  local device="$1"

# XXX
#  local x
#      x=$( diskutil list /dev/disk1 | \
#             grep "Physical Store" | \
#             sed -E 's/.+(disk[0-9]+).+$/\1/')
#      if [ -z $x ]; then
#        if [[ $(strip_parition_id "$device" =~ "$x" ]]; then
#           return 1
#        fi
#      else
#      fi
# XXX

  local boot_drive

  if [[ "$device" =~ ^/dev/null$ ]]; then return 1; fi

  case $(get_OS) in
    macOS)
      # No boot drives
#      boot_drive="$(strip_partition_id "$(bless -getboot)")"
#      if diskutil list "$device" | \
#           grep -F -q -e "Physical Store" -e "Container" || \
#         [ "$(strip_partition_id "$device")" == "$boot_drive" ]; then

      # No boot drives
      boot_drive="$(strip_partition_id "$(bless -getboot)")"
      if [ "$(strip_partition_id "$device")" == "$boot_drive" ]; then
        return 0
      fi
      return 1
      ;;
    Linux)
      boot_drive="/dev/$(lsblk -no pkname $(findmnt -n / | awk '{ print $2 }'))"
      [ "$(strip_partition_id "$device")" == "$boot_drive" ]
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

strip_partition_id() {
  local device="$1"

  # From device
  case $(get_OS) in
    macOS)
      echo "$device" | sed 's/s[0-9][0-9]*$//'
      ;;
    Linux)
      echo "$device" | sed 's/[0-9][0-9]*$//'
      ;;
    *)
      _error "Unknown host OS"
      kill $$
      ;;
  esac

}

list_partitions() {
  local device="$1"
  local include_efi=${2:-false}

  # Outputs a list of drive partitions strings without "/dev/"
  #
  # E.g., "disk21s2 disk21s3" or "sdb2 sdb3"
  # The first partition on the drive is assumed to be
  # If <device> is a drive, all it's partitions are returned
  # including partitions within containers.
  # Comntainers may not be nested.
  #
  # Single partition vs a drive with possible multiple parts;
  #
  # Device will be a /dev spec, but diskutil list doesn't output "/dev/".

  # The EFI service parition is optionally included in the list
  # It is never auto-mounted by default
  # grep -v means invert match
  local include_first_partition=true
  if is_gpt "$(strip_partition_id "$device")" && \
     ! $include_efi; then
    include_first_partition=false
    _DEBUG "is_gpt: true"
  fi
  case $(get_OS) in

    macOS)

      # Parse out container disks (physical stores) and
      # follow containers to the synthesized drive.
      # Multiple containers are allowed.
      # Containers are not nested.
      # Output of not-container v. container:
      #   "Container diskxx" -> Contains
      #   "Physical Store" -> Contained

      _DEBUG "$device"
      local p=""
      local c v
      # The device is either a drive or a specific partition
      if [ "$device" == "$(strip_partition_id "$device")" ]; then

        _info echo "$device, device is entire drive" >&2
        _info echo "PARTITION LIST INCLUDES ESP: $include_efi" >&2

        if $include_first_partition; then

#          mapfile partitions < \
#           <( diskutil list "$device" | \
#              grep '^ *[2-9][0-9]*:' | \
#              sed -E 's/^.+(disk[0-9]+s[0-9]+).*$/\1/' )

          p=( $(diskutil list "$device" | \
            grep -v -e "Container disk" -e "Snapshot" | \
            grep '^ *[1-9][0-9]*:' | \
            sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        else
          p=( $(diskutil list "$device" | \
            grep -v -e "EFI EFI" -e "Container disk" -e "Snapshot" | \
            grep '^ *[1-9][0-9]*:' | \
            sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        fi
        # Get drive's containers, if any
        c=( $(diskutil list "$device" | \
          grep "Container disk" | \
          sed -E 's/^.+Container (disk[0-9]+).+$/\1/') )

      else

        _DEBUG "$device device is a partition ($(get_device_format $device))"
        # Get the one conmtainer, if any
        p=( $(diskutil info "$device" | \
          grep "APFS Container:" | \
          sed -E 's/^.+(disk[0-9]+)$/\1/') )
        _DEBUG "p=${p[@]}"

        # No container, just a basic partition
        if [ -z $p ]; then
          # Return supplied device minus "/dev/" to agree with
          # output of diskutil for other cases
          echo "${device#/dev/}"
          return 0
        else
          # Is a container, so process it
          c=( $(diskutil list "$p" | \
            grep "Container disk" | \
            sed -E 's/^.+Container (disk[0-9]+).+$/\1/') )
          _DEBUG "c=${c[@]}"
          # continue on to process the container
        fi

      fi

      _DEBUG "p=${p[@]}"
      _DEBUG "c=${c[@]}"

      # For all containers, process their contents as volumes
      v=""
      if [ ! -z "$c" ]; then
        for x in ${c[@]}; do
          # Contained volumes begin at continaer's partition index 1
          v=( ${v[@]} $(diskutil list "$x" | \
                  grep '^ *[1-9][0-9]*:' | \
                  sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        done
        _DEBUG "v=${v[@]}"
      fi

      if [ -z $p ] && [ -z $v ]; then
        _info echo "$device has no eligible partitions" >&2
      else
        echo ${p[@]} ${v[@]}
      fi

      return 0
      ;;

    Linux)

      # The device is either a drive or a specific partition
      if [ "$device" != "$(strip_partition_id "$device")" ]; then
        _DEBUG "$device device is a partition ($(get_device_format $device))"
        echo "${device#/dev/}"
        return
      else
        _info echo "$device, device is entire drive" >&2
        _info echo "PARTITION LIST INCLUDES ESP: $include_efi" >&2
        # The EFI service parition is optionally included in the list
        # It is never auto-mounted by default
        # grep -v means invert match
        local p
        if $include_first_partition; then
          p=( $(lsblk --raw -n -o NAME "$device" | \
            grep -E -o "^[a-z]+[0-9]+") )
        else
          p=( $(lsblk --raw -n -o NAME "$device" | \
            grep -E -v "^[a-z]+1$" | \
            grep -E -o "^[a-z]+[0-9]+") )
        fi
        if [ -z $p ]; then
          _info echo "$device has no eligible partitions" >&2
          return 1
        else
          _DEBUG XXX ${p[@]}
          echo ${p[@]}
        fi
      fi
      ;;

    *)
      _error "Unknown host OS"
      kill $$
  esac
}

#######################
# MOUNT, UNMOUNT & FSCK
#######################

os_mount() {
  local device="$1"

  if [ -z $device ]; then return 1;  fi
  case $(get_OS) in
    macOS)
      sudo diskutil mount "$device"
      ;;
    Linux)
# XXX os_unmount for Linux is a stub for future
# XXX handling of older fixed mountpoints
# XXX Modern Debian, e.g.,  Ubuntu and Mint handle
# XXX mounting through systemd and udev rules
#
#      local label=$(get_volume_label)
#      if [ -z "$volume_label"]; then
#        _error "volume has no label, not mounted"
#        return 1
#      fi
#      # -A automount=yes, see systemd-mount(1)
#      sudo systemd-mount -A \
#        --owner "$USER" -o rw "$device" "$volume_label"
      return 0
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

os_unmount() {
  local device="$1"

  if [ -z $device ]; then return 1;  fi
  case $(get_OS) in
    macOS)
      sudo diskutil unmount "$device"
      ;;
    Linux)
      # See os_mount above.
      sudo umount "$device"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

add_to_fstab() {
  local volume_uuid="$1"
  local fs_type="$2"
  local volume_name="${3:-(name unspecified)}"
  local device="${4:-(device unspecified)}"

  if [ "$#" -lt 2 ]; then
    # fstab entires must list the correct filesystem type or
    # they won't be honored by the system.
    _error "_error misssing parameters"
    return 1
  fi
  if grep -q -i "^UUID=$volume_uuid" /etc/fstab; then
    # XXX Add update of particulars
    _info echo "add_to_fstab: $volume_uuid already exists"
    return 0
  fi
#  _info echo "add_to_fstab: $volume_uuid $volume_name"

  case $(get_OS) in
    macOS)
      # Juju with vifs to edit /etc/fstab
      #
      # G (got to end)
      # A (append at end of line)
      # :wq (write & quit
      # THERE'S A NEEDED <ESC> CHARACTER EMBEDDED BEFORE :wq
      #
      # XXX Convert to ex(1)
      EDITOR=vi
      sudo vifs <<EOF > /dev/null 2>&1
GA
UUID=$volume_uuid none $fs_type rw,noauto # "$volume_name" $device:wq
EOF
      if [ $? -ne 0 ]; then
        _error "vifs failed"
        return 1
      fi
      return 0
      ;;

    Linux)
#      cat <<EOF
      sudo sed -i "$ a UUID=$volume_uuid none $fs_type noauto 0 0 # \"$volume_name\" $device" /etc/fstab
#EOF
      sudo systemctl daemon-reload
      return
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

remove_from_fstab() {
  local volume_uuid="$1"
#  local volume_name="$2"
#  local fs_type="$3"

  if ! grep -E -q -i "^(UUID=)*$volume_uuid" /etc/fstab; then
    _error "$volume_uuid not found"
    return 1
  fi

  case $(get_OS) in
    macOS)
      # Juju with vifs to edit /etc/fstab
      # /<pattern> (go to line with pattern)
      # dd (delete line)
      # :wq (write & quit
      _info echo "$volume_uuid"
      EDITOR=vi
      sudo vifs <<EOF > /dev/null 2>&1
/$volume_uuid
dd:wq
EOF
      if [ $? -ne 0 ]; then
        _error "vifs failed"
        return 1
      fi
      ;;

    Linux)
      sudo sed -E -i "/^UUID=$volume_uuid/d" /etc/fstab
      sudo systemctl daemon-reload
      return
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}

unmount_device() {
  local device="$1"

  # Unmount and disable auto-remoount of device
  # If device is drive, do so for all its partitions
  #
  local partitions volume_uuid volume_name fs_type
  local result=0

  # Single partition vs a drive with possible multiple parts
  # device will be a /dev spec, but diskutil list doesn't include "/dev/"
  local p
  partitions=( $(list_partitions "$device") )
  if [ "${#partitions[@]}" -gt "1" ]; then
    _info echo "unmount_device: ${partitions[@]}"
  fi
  for (( p=0; p<${#partitions[@]}; p++ )); do
    local part=/dev/"${partitions[$p]}"
    _DEBUG "unmount_device: $part"

    # If no volume UUID, there's no meaning to fstab entry.
    # Volume likely read-only or not at all.
    volume_uuid="$(get_volume_uuid $part)"
    if [ -z "$volume_uuid" ]; then continue; fi

    _DEBUG "unmount_device: $volume_uuid"

    volume_name="$(get_volume_name $part)"
    fs_type=$(get_device_format "$part")
    add_to_fstab "$volume_uuid" "$fs_type" "$volume_name" "$part"

    # Ubuntu & Mint will mount and unmount devices automatically
    # with changes to /etc/fstab, above.
    #
    # When using a VM, its device arbitration may influence auto-mount
    # logic but including a UUID in /etc/fstab seems to reliably prevent
    # auto-mount.
    #
    os_unmount "$part"
    local r=$?
    _DEBUG "UNMOUNT STATUS $device: $r"
    ! is_mounted "$device"
    _DEBUG "RESULT $?"
    let result+=$?
  done
  _info echo "/etc/fstab:"
  _advise cat /etc/fstab
  return $result
}

mount_device() {
  local device="$1"

  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  local partitions volume_uuid volume_name
  local result=0
  _DEBUG "$device" "$(strip_partition_id "$device")"
  partitions=( $(list_partitions "$device") )
  _info echo "mount_Device: ${partitions[@]}"
  local p
  for (( p=0; p<${#partitions[@]}; p++ )); do
    local part=/dev/"${partitions[$p]}"
    _DEBUG -n "$part "

    volume_uuid="$(get_volume_uuid $part)"
    if [ -z "$volume_uuid" ]; then continue; fi

    _info echo "nmount_device: $volume_uuid"

    volume_name="$(get_volume_name $part)"

    remove_from_fstab "$volume_uuid" "$volume_name"

    os_mount "$part"

# XXX Under systemd mounting is passive. When the device is referred to
# XXX is receives its mountpoint. Running systemd-mount assigns it a
# XXX mountpoint in /run/media/system, put this recinds it from the desktop
# XXX systemd-umount will return it to the desktop.
#    is_mounted "$device"
#    let result+=$?

  done
  _info echo "/etc/fstab:"
  _advise cat /etc/fstab
  return $result
}

fsck_device() {
  local device="$1"
  local find_files="${2:-false}"
  local blocklist="$3"

  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  local partitions volume_uuid nr_checked fs_type
  local result=0

  if $find_files && [ -z "$blocklist" -o ! -f "$blocklist" ]; then
    echo "fsck_device; missing block list for find files"
    return 1
  fi

  # If <device> is a specific partition, check it.
  # If a whole drive, check them all.
  escalate
  case $(get_OS) in
    macOS)
      # Black arts
      flush_io
      partitions=( $(list_partitions "$device" true) )
      _DEBUG "$device" "$(strip_partition_id "$device")"
      _DEBUG ${partitions[@]}

      local p nr_checked=0
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
        fs_type=$(get_device_format "$part")
        _DEBUG "$part" "$fs_type"
        case $fs_type in
          hfsplus)
            if ! $find_files; then
              sudo fsck_hfs -f -y "$part"
            else
              # On macOS -l "lock" must be used when mounted write
#              cat $blocklist
              sudo fsck_hfs -n -l -B "$blocklist" "$device"
            fi
            let result+=$?
            let nr_checked+=1
            ;;
          apfs)
            sudo fsck_apfs -y "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          msdos)
            sudo fsck_msdos -y "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          *)
            echo "fsck_device Skipping $part, unknown filesystem"
            ;;
        esac
      done
      if [ $nr_checked -eq 0 ]; then
        echo "No HFS+ volumes on $device"
      fi
      return $result
      ;;

    Linux)
      partitions=( $(list_partitions "$device" true) )
      _DEBUG "$device" "$(strip_partition_id "$device")"
      _DEBUG ${partitions[@]}

      local p nr_checked=0
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
        if ! $find_files; then
          flush_io "$part"
        fi
        fs_type=$(get_device_format "$part")
        _DEBUG "$part" "$fs_type"
        case $fs_type in
          hfsplus)
            if ! which fsck.hfs; then
              _error "Need fsck for HFS+ (hfstools), skipping $part"
              continue
            fi
            if $find_files; then
              sudo fsck.hfs -n -l -B "$blocklist" "$device"
            else
              sudo fsck.hfs -f -p "$device"
            fi
            let result+=$?
            let nr_checked+=1
            ;;
          msdos)
            if ! which fsck.fat; then
              _error "Missing fsck for FAT (dosfstools), skipping $part"
              continue
            fi
            sudo fsck -a -l "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          exfat)
            if ! which fsck.exfat; then
              _error "Missing fsck for exFAT (exfatprogs), skipping $part"
              continue
            fi
            sudo fsck.exfat -p -s "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          ntfs)
            if ! which ntfsfix; then
              _error "Missing ntfsfix / ntfsclusters (ntfsprogs), skipping $part"
              continue
            fi
            if $find_files; then
              local block count
              cat "${blocklist}-EXTENTS" | \
                while read block count; do
                  sudo ntfscluster -s ${block}-$((block+count)) "$part" | \
                    grep -F -v "inode found"
                done
              return
            fi
            # -d clear dirty if volume can be fixed and mounted
            sudo ntfsfix -d "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          ext[234])
            if $find_files; then
              local blocks=$(cat "${blocklist}" | tr '\n' ' ')
              _DEBUG $blocks

              # debugfs icheck finds corresponding inodes for a list of blocks
              # Output looks like:
              # "Block Inode"
              # block-nr inode-nr
              # block-nr "<no block found>"
              # ...
              inodes=$(sudo debugfs -R "icheck $blocks" "$part" 2> /dev/null | \
                awk -F'\t' '
                  # Strip header and collect 2nd fields (inode number)
                  # into an array
                  NR > 1 { affected[$2]++; }
                  # After all lines processed iterate over the inode array
                  # casting out blocks with no inode.
                  END {
                    for (inode in affected) {
                      if (inode == "<block not found>") {
#                        printf("%d unallocated block\n", affected[in]) > "/dev/stderr";
                         continue;
                      }
                      printf inode OFS;
                    }
                  }'
              )
              # strip trailing whitespace
              inodes=$(echo $inodes)
# Alternate
#              inodes=$( \
#                sudo debugfs -R "icheck $blocks" "$part" | \
#                tail -n +2 | \
#                sed -E '/[0-9]+\s+<block not found>/d' | \
#                sed -E 's/([0-9]+\s+)([0-9]+)/\2/g' | \
#                tr '\n' ' ' \
#              )
              _DEBUG $inodes

              # debugfs ncheck prints path names for indodes.
              #
              sudo debugfs -R "ncheck -c $inodes" "$part"
              return
            fi
            sudo fsck -f -p "$part"
            let result+=$?
            let nr_checked+=1
            ;;
          *)
            echo "fsck_device Skipping $part, unknown filesystem ($fs_type)"
            ;;
        esac
      done
      if [ $nr_checked -eq 0 ]; then
        echo "No supported volume(s) on $device"
      fi
      return $result
      ;;

    *)
      _error "Unknown host OS"
      kill $$
  esac
}

check_mount() {
  local path="$1"
  local device="$2"

  case $(get_OS) in
    macOS)
      d="$(df | grep disk23 | sed 's/  */ /g' | cut -d ' ' -f 9)"
      echo "/Volumes/V0-/_XXX/" | grep -F -q "^$d"
      ;;
    Linux)
      # Returns true if path is on device
      findmnt --target "$path" | grep -F "$device"
      ;;
    *)
      _error "Unknown host OS"
      kill $$
  esac
}


##################################
#            MAINLINE
##################################

Do_Unmount=false
Do_Mount=false
Do_Fsck=false
#
Do_Smart_Scan=false
Do_Copy=false
#
Do_Error_Files_Report=false
Do_Slow_Files_Report=false
Do_Rate_Plot=false
#
Do_Zap_Blocks=false
Preview_Zap_Regions=true
#
Opt_Trim=true
Opt_Scrape=false
Opt_4K=false
Opt_Zap_Slow=false
# ddrescue option -A --try-again
Opt_Retrim=false
#
Zap_In_Progress=false
#Zap_Extend_Extent=false

while getopts ":cfhmpqsuzKMXZ" Opt; do
  case ${Opt} in
    c) Do_Copy=true ;;
    f) Do_Fsck=true ;;
    h) help | more; exit 0 ;;
    m) Do_Mount=true ;;
    p) Do_Error_Files_Report=true ;;
    q) Do_Rate_Plot=true ;;
    s) Do_Slow_Files_Report=true ;;
    u) Do_Unmount=true ;;
    z)
      # Only preview
      Do_Zap_Blocks=true
      Preview_Zap_Regions=true
      ;;
    M) Opt_Retrim=true ;;
    K) Opt_4K=true ;;
    X) Opt_Scrape=true ;;
    Z)
      # Overwite blocks in the device one at a time using an existing map
      Do_Zap_Blocks=true
      Preview_Zap_Regions=false
      ;;
    *)
      usage
      _advise echo  "$(basename "$0"): Unknown option $1"
      exit 1
      ;;
  esac
done
# Move remaining args into postion at $1...
shift $((OPTIND - 1))

if ! $Do_Mount && ! $Do_Unmount && ! $Do_Fsck && \
   ! $Do_Copy && ! $Do_Smart_Scan && \
   ! $Do_Error_Files_Report && ! $Do_Slow_Files_Report && \
   ! $Do_Zap_Blocks && \
   ! $Do_Rate_Plot && \
   true; then
  _info echo "$(basename "$0"): Nothing to do (-h for help)"
  exit 0
fi

# USAGE 1

if $Do_Mount || $Do_Unmount || $Do_Fsck; then

  if \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
     $Do_Rate_Plot || \
     false; then
    _error "Incompatible options (1)"
    exit 1
  fi

  if [ $# -ne 1 ]; then
    _error "Missing or extra parameter (1)"
    exit 0
  fi

  Device="$1"

  if $Do_Unmount; then
    if $Do_Mount; then
      _error "Incompatible options (1a)"
      exit 1
    fi
    if ! is_device "$Device" false; then
      _error "No such device $Device"
      exit 1
    fi
    _info echo "unmount: Disable automount..."
    if ! unmount_device "$Device"; then
      _error "Unmount(s) failed"
      exit 1
    fi
    exit 0
  fi

  if $Do_Mount; then
    if $Do_Unmount || $Do_Fsck; then
      _error "Incompatible options (1b)"
      exit 1
    fi

    # Various use-cases can leave an orphan UUID in /etc/fstab
    # The user could remove it with vifs(8).
    # This just makes it simpler.
    # Allow "UUID=" in string in mixture of upper and lower.
    # UUIDs are forced upper.
    if _uuid=$(is_uuid "${Device/[Uu][Uu][Ii][Dd]=}"); then
      # Just remove it from /etc/fstab
      remove_from_fstab "$_uuid"
      _info echo "/etc/fstab:"
      _advise cat /etc/fstab
      exit
    fi
    if ! is_device "$Device" false; then
      _error "No such device $Device"
      exit 1
    fi
    _info echo "Enable automount and mount..."
    if ! mount_device "$Device"; then
      _error "errors occurred"
      exit 1
    fi
    exit 0
  fi

  if $Do_Fsck; then
    if $Do_Mount; then
      _error "Incompatible options (1c)"
      exit 1
    fi
    fsck_device "$Device" false
  fi
  exit 0
fi

# USAGE 2

if $Do_Smart_Scan; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck \
     $Do_Copy || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
     $Do_Rate_Plot || \
     false; then
    _error "Incompatible options (2)"
    exit 1
  fi

  if [ $# -ne 1 ]; then
    _error "Missing or extra parameters (2)"
    exit 1
  fi

  #
  # Run a long test and monitor it's progress
  # When bad blocks are found, reallocate them and
  # restart the test.
  #
  # XXX THIS DOESN'T WORK WELL BECAUSE SMARTCTL WON'T
  # XXX RELIABLY CREATE A FULL LIST OF BLOCKS
  # XXX Use ddrescue instead
  #
  _info echo "Deprecated, doesn't work"
  # Verify device is a drive not a partition
#    smart_scan_drive "$device" "$smart_blocklist"

  exit 1
fi

if $Do_Copy; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck \
     $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
     $Do_Rate_Plot || \
     false; then
    _error "Incompatible options (2)"
    exit 1
  fi

  if [ $# -ne 3 ]; then
    _error "Missing or extra parameters (2)"
    exit 1
  fi

  if ! which ddrescue; then
    _error "ddrescue(1) not found on PATH"
    usage_packages
    echo
    exit 1
  fi
  if ! ddrescue --help | grep -F -q -- "--log-events" || \
     ! ddrescue --help | grep -F -q -- "--log-rates" || \
     ! ddrescue --help | grep -F -q -- "--no-scrape" || \
     ! ddrescue --help | grep -F -q -- "--no-trim"; then
    _error "ddrescue(1) version missing needed options"
    _error "  --log-events"
    _error "  --log-rates"
    _error "  --no-scrape"
    _error "  --no-trim"
    usage_packages
    echo
    exit 1
  fi

  # GLOBALS
  Label="${1%/}" # Name for metadata folder including the ddrescue map.
  Copy_Source="$2"
  Copy_Dest="$3"

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Block_List="$Label.fsck-blocklist"
  Zap_Block_List="$Label.zap-blocklist"
  Smart_Block_List="$Label.smart-blocklist"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log"
  Files_Log="$Label.files-log"
  Metadata_Path=""

  Copying=false
  Resuming=false

  if [[ "$Label" =~ ^/dev ]]; then
    _error "Command line args reversed?"
    exit 1
  fi

  # Verify paths don't collide
  result=0

  if ! Metadata_Path=$(absolute_path "$Label"); then
    _error "copy: Invalid label path $Label"
    let result+=1
  fi
  if ! Copy_Source=$(absolute_path "$Copy_Source"); then
    _error "copy: Invalid source path $Copy_Source"
    let result+=1
  fi
  if ! Copy_Dest=$(absolute_path "$Copy_Dest"); then
    _error "copy: Invalid destinationpath $Copy_Dest"
    let result+=1
  fi
  _info echo "copy: Metadata path $Metadata_Path"
  _info echo "copy: Source path $Copy_Source"
  _info echo "copy: Dest path $Copy_Dest"
  if [ $result -gt 0 ]; then exit 1; fi

  if [ "$Copy_Source" == "$Copy_Dest" ] || \
     [ "$Copy_Source" == "$Metadata_Path" ] || \
     [ "$Copy_Dest" == "$Metadata_Path" ]; then
    _error "copy: <label>, <source> and <destination> paths overlap"
    exit 1
  fi

  # Ensure the path for the metadata isn't on a mountpoint for either device.
  if check_mount "$(dirname "$Metadata_Path")" "$Copy_Source" || \
     check_mount "$(dirname "$Metadata_Path")" "$Copy_Dest"; then
    _error "copy: <label> can't be a dir on the source or destination"
    exit 1
  fi

  # Map_File remains relative to the metadata directory, no harm no foul.
  # Source and destination paths are absolute to avoid hazards.
  if ! mkdir -p "$Label"; then
    _error "copy: Can't create a data dir for \"$Label\""
    exit 1
  fi

  _DEBUG "copy: Matadata directory: ${Label}"

  if ! cd "$Metadata_Path"; then echo "Setup error (cd $Label)"; exit 1; fi

  # Verify Copy_Source is eligible
  if is_device "$Copy_Source" false; then
    if device_is_boot_drive "$Copy_Source"; then
      _error "copy: Boot drive can't be used."
      exit 1
    fi
  else
    if [ "$?" == "2" ]; then
      # Specs "/dev/" but no such device.
      _error "copy: $Copy_Source: device not found"
      exit 1
    fi
    # Is file
    #
    if [ -d "$Copy_Source" ]; then
      _error "copy: Source cannot be a directory: $Copy_Source"
      exit 1
    fi
    if ! resource_exists "$Copy_Source"; then
      _error "copy: No such file $Copy_Source"
      exit 1
    fi
    if _t="$(get_symlink_target "$Copy_Source")"; then
      _error "copy: Source cannot be symlink: $Copy_Source -> $_t"
      exit 1
    fi
    if _t="$(get_alias_target "$Copy_Source")"; then
      _error "copy: Source cannot be alias: $Copy_Source -> $_t"
      exit 1
    fi
    _info echo "copy: Source is a file: $Copy_Source"
  fi

  # Verify Copy_Dest is eligible
  if is_device "$Copy_Dest" false; then
    if device_is_boot_drive "$Copy_Dest"; then
      _error "copy: Boot drive can't be used."
      exit 1
    fi
    # Continue
  else
    if [ "$?" == "2" ]; then
      # Specs "/dev/" but no such device.
      _error "copy: $Copy_Dest: device not found"
      exit 1
    fi
    # Is file
    if [ -d "$Copy_Dest" ]; then
      _error "copy: Destionation cannot be a directory: $Copy_Dest"
      exit 1
    fi
    if [ "$Copy_Dest" == "/dev/null" ]; then
      _info echo "copy: Destination is /dev/null (scanning)"
    else
      if _t="$(get_symlink_target "$Copy_Dest")"; then
        _error "copy: Destination cannot be symlink: $Copy_Dest -> $_t"
        exit 1
      fi
      if _t="$(get_alias_target "$Copy_Dest")"; then
        _error "copy: Destination cannot be alias: $Copy_Dest -> $_t"
        exit 1
      fi
      Opt_Scrape=true
      _info echo "copy: Destination is a file: $Copy_Dest"
    fi
  fi

  # Determine status: first-run or resuming.
  if [ -s "$Map_File" ]; then

    if ! resource_matches_map "$Copy_Source" "$Map_File"; then
      # XXX Can't distingush between source and dest in the map.
      # XXX IF src /dst were reversed this would still pass.
      _error "copy: Existing block map ($Label) but not for $Copy_Source"
      get_commandline_from_map "$Map_File"
      exit 1
    fi
    if resource_matches_map "$Copy_Dest" "$Map_File"; then
      if [ "$Copy_Dest" != "/dev/null" ] && \
         [ ! -s "$Copy_Dest" ]; then
        _error "copy: Existing block map ($Label) but missing destination file $Copy_Dest"
        exit 1
      fi
      # XXX Fair assumption
      # XXX Could compare the first N blocks of source / dest to verify
      Resuming=true
    else
      _error "copy: Existing block map ($Label) not for this destination"
      get_commandline_from_map "$Map_File"
      exit 1
    fi

    #
    # For files, check mtimes and reject if source is newer than dest
    #
    if [ -f "$Copy_Source" ] && [ -f "$Copy_Dest" ] && [ $Resuming ]; then
      if [ $(stat -f %m "$Copy_Source") -gt $(stat -f %m "$Copy_Dest") ]; then
        _error "copy: Block map exists and source is newer than destinmation, quitting"
        exit 1
      fi
    fi
  fi

  # Unlikely edge case of hard links to same file
  if [ -f "$Copy_Source" ] && [ -f "$Copy_SDest" ]; then
    if [ "$(get_inode "$Copy_Source")" == "$(get_inode "$Copy_Dest")" ]; then
      _error "copy: source & destination are same file (inode: $(get_inode "$Copy_Dest"))"
      exit 1
    fi
  fi

  if $Resuming; then
    _info echo "RESUMING COPY"
  elif is_device "$Copy_Dest" false || \
       [[ ! "$Copy_Dest" =~ ^/dev/null$ && -s "$Copy_Dest" ]]; then
    echo 'copy: *** WARNING DESTRUCTIVE'
    read -r -p "copy: *** OVERWRTIE ${Copy_Dest}? [y/N] " response
    if [[ ! $response =~ ^[Yy]$ ]]; then
       _info echo "copy: ...STOPPED."
       exit 1
    fi
  fi

  if ! $Opt_4K; then
    _info echo "BLOCK SIZE: 512"
  else
    _info echo "BLOCK SIZE: 4096"
  fi

  if is_device "$Copy_Source" && ! unmount_device "$Copy_Source"; then
    _error "copy: Unmount failed $Copy_Source"
    exit 1
  fi
  if is_device "$Copy_Dest" && ! unmount_device "$Copy_Dest"; then
    _error "copy: Unmount failed $Copy_Dest"
    exit 1
  fi

  Copying=true
  if ! run_ddrescue \
         "$Copy_Source" \
         "$Copy_Dest" \
         "$Map_File" \
         "$Event_Log" \
         "$Rate_Log" \
         "$Opt_Trim" \
         "$Opt_Scrape" \
         "$Opt_4K" \
         "$Opt_Retrim"; then
    _error "copy: ddrescue returned error exit status ($?) or was interruped"
    exit 1
  fi
  if [ -s "$Map_File" ]; then
    _info echo "copy: Map saved in $Label/$Map_File";
  fi

  cleanup
  exit 0
fi

# USAGE 3

if \
   $Do_Error_Files_Report || $Do_Slow_Files_Report || \
   $Do_Zap_Blocks || \
   false; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck || \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Rate_Plot || \
     false; then
    _error "Incompatible options (3)"
    exit 1
  fi

  # Need a label and metadata
  if [ $# -ne 2 ]; then
    _error "Missing or extra parameters (3)"
    exit 1
  fi

  # GLOBALS
  Label="${1%/}" # Name for metadata folder including the ddrescue map.
  Device="$2"
  # Device is required becuase a although a map contains a command-line record
  # of the output device, which could be extracted, the map can be for a whole
  # drive, while a report must be for a partition.

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Block_List="$Label.blocklist-error"
  Slow_Fsck_Block_List="$Label.blocklist-slow"
  Zap_Block_List="$Label.blocklist-zap"
  Smart_Block_List="$Label.blocklist-smart"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log" # Incremeted if exists
  Error_Files_Report="$Label.FILES-REPORT-ERROR"
  Slow_Files_Report="$Label.FILES-REPORT-SLOW"
  Partition_Offset=0
  Device_Blocksize=""
  Fs_Blocksize=""

  if [[ "$Label" =~ ^/dev ]]; then
    _error "report/zap: Command line args reversed?"
    exit 1
  fi

  if ! $Preview_Zap_Regions && \
     ! is_device "$Device" && ! [ -f "$Device" ]; then
    _error "report/zap: No such device or file ($Device)"
    exit 1
  fi

  # Zap only: file path is allowed.
  # Setup path for map check beloiw.
  if $Do_Zap_Blocks && [ -f "$Device" ] && \
     ! Device=$(absolute_path "$Device"); then
    _error "zap: Invalid file path $Device"
    exit 1
  fi

  if ! cd "$Label" > /dev/null 2>&1; then
    _error "report/zap: No metadata found ($Label)"
    exit 1
  fi
  if [ ! -s "$Map_File" ]; then
    _error "report/zap: No ddrescue block map ($Label). Create with -c"
    exit 1
  fi

  # Check existing mapfile to see if it lists <device> as device.
  #
  # XXX No easy way to determine whether match of source or destination
  # XXX from mapfile. Need side store of parameters for -c.
  #
  # For printing files, the mapfile for the whole drive is allowed
  # is allowed for a device that's a partition.
  #
  if ! resource_matches_map "$Device" "$Map_File"; then
    if $Do_Error_Files_Report || $Do_Slow_Files_Report; then
      # Accept whole drive map for a partition device
      x="$(strip_partition_id "$Device")"
      if ! resource_matches_map "$x" "$Map_File"; then
        _error "report: Existing block map ($Label) but not for $Device"
        get_commandline_from_map "$Map_File"
        exit 1
      fi
      # Fall through
    else
      _error "report: Existing block map ($Label) but not for $Device"
      get_commandline_from_map "$Map_File"
      exit 1
    fi
  fi

  # <device> is a partition, but map may be for a drive.
  #
  # Filesystem reports (fsck/debugfs/ntfscluster) expect block
  # addresses to be partition relative.
  #
  # If <device> is a drive then an offset is needed.
  #
  if $Do_Error_Files_Report || $Do_Slow_Files_Report; then

    # Verify device is present
    if ! is_device "$Device"; then
      _error "report: No such device $device"
      exit 1
    fi

    if [ "$Device" != "$(get_device_from_ddrescue_map "$Map_File")" ]; then
      # Correspondence to the map was checked coming in,
      # so assume the map is for a whole drive, compute offset.
      Partition_Offset=$(get_device_offset "$Device")
      if [ -z $Partition_Offset ] || [ $Partition_Offset -eq 0 ]; then
        _info echo "report: partition offset fail"
        return 1
      fi
    fi
    _info echo "PARTITION OFFSET: $Device: $Partition_Offset blocks ($(get_device_blocksize "$Device") bytes per block)"

    if ! is_hfsplus "$Device" && \
       ! is_ext "$Device" && \
       ! is_ntfs "$Device"; then
      _error "report: Usupported volume type ($(get_device_format "$Device")) req. HFS+, NTFS, ext2, ext3, ext4"
      exit 1
    fi

    if $Do_Error_Files_Report; then
      # Report on stdout and saved in report file
      # Side effect is Error_Fsck_Block_List
      create_ddrescue_error_blocklist \
        "$Device" \
        "$Map_File" \
        "$Error_Fsck_Block_List" \
        "$Partition_Offset"
#      cat "$Error_Fsck_Block_List"
      fsck_device "$Device" true "$Error_Fsck_Block_List" | \
        tee "$Error_Files_Report"
      _info echo "report: files affected by errors: $Label/$Error_Files_Report"
    fi

    if $Do_Slow_Files_Report; then
      # Report on stdout and saved in report file
      create_slow_blocklist \
        "$Device" \
        "$Rate_Log" \
        "$Slow_Fsck_Block_List" \
        "$Partition_Offset" \
        1000000
#      cat "$Slow_Fsck_Block_List"
      fsck_device "$Device" true "$Slow_Fsck_Block_List" | \
        tee "$Slow_Files_Report"
      _info echo "report: files affected by slow reads: $Label/$Slow_Files_Report"
    fi

    exit
  fi

  if $Do_Zap_Blocks; then
    # No partition offset is needed for zap because there's no
    # dependency on a partition-relative utility list fsck.
    # The user specifies the device that was used to make the map.

    if ! $Preview_Zap_Regions; then
      if is_device "$Device"; then
        _info echo "zap: Umount and prevent automount..."
        if ! unmount_device "$Device"; then
          _error "zap: Unmount failed"
          exit 1
        fi
      fi
      # XXX This must be outside of any function
      trap "_abort true $Device" SIGINT SIGTERM
    fi

    zap_from_mapfile "$Device" \
                     "$Map_File" \
                     "$Zap_Block_List" \
                     $Preview_Zap_Regions \
                     $Opt_4K
    exit
  fi

fi

# USAGE 3+

if \
   $Do_Rate_Plot || \
   false; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck || \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
     false; then
    _error "Incompatible options (3+)"
    exit 1
  fi

  if ! which gnuplot > /dev/null; then
    _error "gnuplot(1) not found on PATH"
    usage_packages
    echo
    exit 1
  fi

  # Need a label and metadata
  if [ $# -ne 1 ]; then
    _error "Missing or extra parameters (3+)"
    exit 1
  fi

  # GLOBALS
  Label="${1%/}" # Name for metadata folder including the ddrescue map.

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Block_List="$Label.blocklist-error"
  Slow_Fsck_Block_List="$Label.blocklist-slow"
  Zap_Block_List="$Label.blocklist-zap"
  Rate_Log="$Label.rate-log" # Incremeted if exists
  Rate_Plot_Data="$Label.rate-data"
  Rate_Plot_Report="$Label.REPORT-RATE-PLOT"
  Partition_Offset=0
  Device_Blocksize=""
  Fs_Blocksize=""

  if ! cd "$Label" > /dev/null 2>&1; then
    _error "rateplot: No metadata found ($Label)"
    exit 1
  fi
  if ! ls "${Rate_Log}-"* > /dev/null 2>&1; then
    _error "rateplot: No ddrescue rate-log data ($Label)"
    exit 1
  fi

  # Prep the rate log for graph and feed it to gluplot.
  cat "${Rate_Log}-"* | grep -v "#" | sort -n | uniq | \
    awk '
      BEGIN { OFS=FS }
      {
        a=$2 / 1000000000
        b=$3 / 1000000
        printf "%0.3f %d\n", a, b
      }' | \
    gnuplot -e \
    "set terminal dumb; \
     unset grid; \
     set xlabel \"Position GB\"; \
     set ylabel \"Rate\nMB/s\"; \
     plot \"-\" using 1:2 title \"$Label\" pt \"|\"" | \
    tee "$Rate_Plot_Report"

    _info echo "Plot saved to $Label/$Rate_Plot_Report"

#     set xtics format \"\"; \

fi

cleanup