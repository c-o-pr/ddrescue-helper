#!/bin/bash
#set -x
TRACE=false

usage() {
  cat << USAGE
$(basename "$0") Usage:

  WARNING! DESTRUCTIVE TO DATA!
  BEFORE USING READ THE DOCUMENTATION FOR GNU ddrescue.
  STUDY THIS USAGE CAREFULLY BEFORE USING -Z

  -m | -u | -f <device>
    :: unmount / mount / fsck

    With -m, <device> can be a UUID to be removed from /etc/fstab.
    In certain use cases, an /etc/fstab entry for a volume UUID can end
    up orphaned.

  -c [ -X ] <label> <source> <destination>
    :: copy

    Use /dev/null for <destination> to scan <source> producing
    a map and rate log.

  -p | -s | -z | -Z <label> <device>
    :: print affected files reports / zap-blocks

    -p [SAFE] report files affected by read errors in map data.
    -s [SAFE] report files affected by slow reads in rate log.

    -z Zap preview. Print a list of block regions that will nbe zapped,
       but don't zap them. Examine the list to sanity check before -Z.
    -Z [DANGEROUS] Overwrite drive blocks at _error regions specified by map data
       to help trigger <device> to re-allocate underlying sectors.

  <label> Name for a directory created to contain ddrescue map and log data.

  <device> /dev entry for an block storage device.
    IMPORTANT: See description below.

    On macOS, use the "rdisk" form of the device special file to get
    full speed access (e.g., /dev/rdisk17).

    If <device> is a whole drive, all its partitions are affected.
    Except for -m and -u which ignore EFI service parition.

  <source> <destination> regular file or /dev block storage device.

    If <destination> is a regular file it becomes an (image) of <source>
    If <destinatio> is a /dev entry for an block storage device it becomes a
    clone of <source>.

    DATA AT <destination> is OVERWRITTEN WIth DATA FROM <source>

  DESCRIPTION
  Create and use ddrescue block map data to address bad blocks
  and locate files in partitions (HFS+) assocated with the bad blocks.

  -u Unmount <device> partition(s) and prevent auto-moounting.
     The GPT EFI partition is not included as it is not normally auto-mounted.
     If device is a drive, all its partitions are unmouonted including
     APFS containers.

  -m Undo autmount prevention and remount drive or partition on <device>.

  -f Fsck. Check and repair partitions (HFS+).

  -c Copy <source> to <destination> using ddrescue to build metadata for
     unreadable (bad) blocks (block map) and create a rate log.

     Metadata including the block map for the copy is placed in a subdir
     named <label> in the current working dir.

     <destination> can be /dev/null, in which case the effect is a "scan"
     for read errors on <source> to produce the block for use with
     -p -s -z and -Z.

     If existing block map data for <label>, <source> and <destination>
     is present, copying resumes until ddrescue determines the disposition
     of all blocks in the source, subject to limits on scripting.
     (ddescue "finished").

     Existing block map data ets a simple sanity-check that it pertains
     to the specfied <source> and <destinatio>.

     Copy implies unmount (-u) <source> and <destination>.
     Mounting (-m) after copy must be performed explicitly.

     The metadata created by any -c for drvies and partitions
     can be used by -p -s -z and -Z. When the source is a file, it may be
     interesting to know which blocks are affected by these are logical blocks
     within the file, not device blocks.

     By default -c when <destination> is /dev/null (scan) doesn't scrape
     to avoid waiting for additional reads in likely bad areas that aren't
     likely to change afftect files reporting. Enable scan scrape with -X.

     The boot drive cannot used (altoough maybe it should be allowed for scan).

  -X Enable ddrescue "scrape" during scan. See GNU ddrescue doc.

  -p Report for HFS+ partition of files affected by _error regions
     listed in the ddrescue map for <label>. Affected files can be
     restored from backup or rescued individually using this helper.

  -s Report for HFS+ partition of files affected by regions of
     slow reads as listed in the ddrescue rate log for <label>
     (slow is less than 1 MB/s). Affected files can be set aside to avoid
     further dependency on that drive region.

     For print, <device> must a HFS+ partition (e.g. /dev/rdisk2s2),
     but block map data can wither for the partition or for the
     whole drive (e.g. /dev/rdisk2). If <device> is for a partition,
     but the map is for a whole ddrive, the necessary offset for
     proper location of files will be automatically calculated.

     Map data from an unfinished copy can be used with -p and -s with the
     obvious caveat of missing infomration.

  -z Print a preview of _error blocks to be zapped, allowing you to sanity check
     the implications before actually zapping with -Z. For example, if you
     have errors in the first 40 512-byte blocks for a GPT drive, you will
     overwrite the drive's partition table, so make a copy of
     the backup partition table first (beyond the scope of this help).

  -Z Zap blocks listed as errors in an existing block map.
     Uses dd to write specific discrete blocks in an attempt
     to make the drive re-allocate them.

    Map data from an unfinished copy or scan can be used with -p -s -z -Z,
    assuming any bad blocks or slow areas have been recorded.

  REQUIRES
    Bash V3+
    GNU ddrescue: [ macports | brew ] install ddrescue
    fsck(8) - mac builtin
    diskutil(8) - mac builtin

  SEE
    GNU ddrescue Manual
    https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

  SOURCE OF THIS SCRIPT
    https://github.com/c-o-pr/ddrescue-helper

USAGE
}

cleanup() {
  return 0
}
_abort() {
  echo; echo '*** Aborted.'; echo
  cleanup
  exit 1
}
trap _abort SIGINT SIGTERM

#_suspend() {
#  trap _abort SIGINT SIGTERM
#  suspend
#  return 0
#}
#trap _suspend SIGTSTP

_error() {
  local caller=$( [ ${FUNCNAME[1]} != "main" ] && \
                  echo "${FUNCNAME[1]}:" || \
                  echo "" )
  echo "*** $caller $@" >&2
}
_DEBUG() {
  [ $TRACE ] || echo "DEBUG: ${FUNCNAME[1]}: $@" >&2
}
_info() {
  echo "$@"
}

get_OS() {
  if which diskutil > /dev/null; then
    echo "macOS"
  elif which lsblk > /dev/null; then
    echo "Linux"
  else
    echo "(unknown)"
  fi
}

escalate() {
# XXX not used
  _info "Escalating privileges..."
  if ! sudo echo -n; then
    _error "sudo failed"
    exit 1
  fi
}

absolute_path() {
  # Run in a subshell to prevent hosing the current working dir.
  # XXX This breaks if current user cannot cd into a path element.
  (
    if [ -z $1 ]; then return 1; fi
    if ! cd "$(dirname "$1")"; then return 1; fi
    case "$(basename $1)" in
        ..) echo "$(dirname $(pwd))";;
        .)  echo "$(pwd)";;
        *)  echo "$(pwd)/$(basename "$1")";;
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
      return 1
      ;;
  esac

  return 1
}

##########################
# FUNCTIONS SUPPORTING ZAP
##########################

read_block() {
  local target="$1"
  local block="$2"

#  sudo hdparm --read-sector "$block" "$target" > /dev/null
  sudo dd bs=512 count=1 if="$target" \
    iseek="$block" iflag=direct #| od -t xC
}

write_block() {
  local target="$1"
  local block="$2"

#  echo sudo hdparm --yes-i-know-what-i-am-doing --write-sector "$2" "$1"
  sudo dd bs=512 count=1 if=/dev/random of="$target" \
    oseek="$block" oflag=sync,direct conv=notrunc
}

zap_sequence() {
  local target="$1"
  local block="$2"
  local count="$3"

  local result t
  local max=3
  local c=1
  printf "zap_sequence: Processing $target %d (0x%X) %d:\n" "$block" "$block" "$count"
  while [ "$c" -le "$count" ]; do
    printf "%d (0x%X) read " "$block" "$block"
#    debug -n "$block read "
    let t=$(date +%s)+2
    read_block "$target" "$block" > /dev/null 2>&1
    result=$?
    t2=$(date +%s)
#    debug $t $t2
    if [ $result -ne 0 ] || [ $t -lt $t2 ]; then
      echo -n "FAILED ($result), write "
      write_block "$target" "$block"  > /dev/null 2>&1
      result=$?
      if [ "$result" -ne 0 ] ; then
        echo "FAILED"
        sleep 0.1
      else
        echo -n "re-read "
        if ! read_block "$target" "$block" > /dev/null 2>&1; then
          echo -n "FAILED"
        else
          echo -n "ok"
        fi
      fi
    else
      echo -n "ok"
    fi
    let block+=1
    let c+=1
    echo
  done
  _info "done, $count blocks"
}

zap_from_mapfile() {
  local device="$1"
  local map_file="$2"
  local zap_blocklist="$3" # side-effect
  local preview="${4:-true}"

  echo "$zap_blocklist"

  # Parse map for zap
  extract_error_extents_from_map_file "$map_file" | \
   ddrescue_map_extents_bytes_to_blocks 512 | \
   sort -n >| "$zap_blocklist"

  if [ ! -s "$zap_blocklist" ]; then
    _info "Missing or empty bad-block list"
    return 1
  fi
  if grep '[^0-9 ]' "$zap_blocklist"; then
    _info "Bad-block list should be a list of numbers"
    return 1
  fi

  local block count total_blocks=0
  if $preview; then
    _info "PREVIEW"
  fi
  _info "DEVICE BLOCK COUNT (hex)"
  cat "$zap_blocklist" | \
  { \
    while read block count; do
      if [ -z $block ] || [ $block -eq 0 ] || \
         [ -z $count ] || [ $count -gt 500 ]; then
        _info "address is 0 or count > 500"
        return 1
      fi
      let total_blocks+=$count
      if $preview; then
        printf "$device %12d %-4d %#12x %#5.3x\n" \
          "$block" "$count" "$block" "$count"
      else
        zap_sequence "$device" "$block" "$count"
      fi
    done
    _info "done, total $total_blocks blocks"
  }

  return 0
}

zap_from_smart() {
  return 1
}

#####################################
# FUNCTIONS FOR SMART BLOCK REPORTING
#####################################

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

###############################################
# FUNCTIONS FOR BLOCK LISTS FOR REPORTS AND ZAP
###############################################

sanity_check_blocklist() {
  local blocklist="$1"
  local device="$2"

  # XXX NOT YET USED
  # Populate with checks for metadata areas that could be catastrophic
  # to overwrite, like the partition table, superblock, etc.
  # At least check for very low and very high numbered blocks
  # relative to the device range.
  case $(get_device_type "$device") in
    file)
      return 0
      ;;
    GPT)
      return 0
      ;;
    hfs)
      return 0
      ;;
    apfs)
      return 0
      ;;
    ext*)
      return 0
      ;;
    msdos)
      return 0
      ;;
    ntfs)
      return 0
      ;;
    *)
      _info "unknown device type $device_type"
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

  # Convert hex map data for byte addresses and extents
  # into decimal blocks.
  # Input (512):
  #   Addr   Len
  #   0x800  0x200  extraneous
  # Output:
  #   4      1
  # 0 or 0 are skipped
  #
  _DEBUG "blocksize $blocksize"
  local addr len
  while read addr len x; do
    _DEBUG input $addr $len
    addr=$(( addr / blocksize ))
    len=$(( (len + blocksize - 1 ) / blocksize ))
    # Edge case
    if  (( addr == 0 || len == 0 )); then continue; fi
    # decimal
    echo $addr $len
    _DEBUG output $addr $len 
  done
}

parse_ddrescue_map_for_fsck() {
  local map_file="$1"
  local fsck_blocklist="$2" # filename for EXTENTS side-effect
  local partition_offset="${3:-0}"
  local device_blocksize="${4:-512}"
  local fs_blocksize="${5:-4096}" # For ext2/3/4 reports, req debugfs

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
  _info "ERROR BLOCKLIST: $fsck_blocklist"
  parse_ddrescue_map_for_fsck \
    "$map_file" \
    "$fsck_blocklist" \
    "$partition_offset" \
    $(get_device_blocksize "$device") \
    $(get_fs_blocksize "$device") \
      >| "$fsck_blocklist"

  if [ ! -s "$fsck_blocklist" ]; then
    _info "NO ERROR BLOCKS"
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

  _info "SLOW BLOCKLIST (less than $slow_limit bytes per sec)"
  parse_rate_log_for_fsck \
    "$rate_log" \
    "$slow_blocklist" \
    "$slow_limit" \
    "$partition_offset" \
    $(get_device_blocksize "$device") \
    $(get_fs_blocksize "$device") \
      >> "$slow_blocklist"

  if [ ! -s "$slow_blocklist" ]; then
    _info "NO SLOW BLOCKS"
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
    _info "NO ERROR BLOCKS"
    exit 0
  fi
}

################################
# FUNCTIONS FOR RUNNING ddrescue
################################

make_ddrescue_helper() {
  # Cteate a temp helper script so ddrescue to be restarted
  # after a read timeout withoout a sudo password request
  # XXX PASS SIGNAL TO SCAN SCRIPT
  local helper_script="${1:-ddrescue.sh}"

  if ! which ddrescue > /dev/null; then
    _info "ddrescue not found on PATH"
    return 1
  fi

  # Don't let an old helper script bollacks the work
  if [ -s "$helper_script" ]; then
    if ! rm -f "$helper_script"; then
      _info "error, coouldn't replace exosting helper"
      return 1
    fi
  fi
  cat >| "$helper_script" << "EOF"
#!/bin/bash
source="$1"
device="$2"
map_file="$3"
event_log="$4"
rate_log="$5"
trim="${6:-true}"
scrape="${7:-false}"

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
    c=${last_log##*-}; let c++
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
  echo "$(basename "$0"): copy: missing parameter(s)"
  echo "  source=\"$1\" device=\"$2\" map_file=\"$3\""
  echo "  event_log=\"$4\" rate_log=\"$5\""
  echo "  scrape_opt=\"$6\" trim_opt=\"$7\""
  exit 1
fi

# -b x (block size default 512)
# -f force (allow output to /dev)
# -n no scrape
# -N no trim
# -T Xs Maximum time since last successful read allowed before giving up.
# -r x read retries
opts="-f -T 10s -r0"
if ! $trim; then opts+=" -N"; fi
if ! $scrape; then opts+=" -n"; fi
opts+=" --log-events=$event_log"

tries=0
max=10
finished=false
while ! $finished && [ $tries -lt $max ]; do
  let tries+=1
  ddrescue $opts  --log-rates="$(next_rate_log_name $rate_log)" \
    "$source" "$device" "$map_file"
  sleep 1
  if grep -F "Finished" "$map_file" > /dev/null; then finished=true; fi
done
if ! $finished; then
  echo "*** COPY INCOMPLETE: aborted after $max tries"
  exit 1
fi
exit 0
EOF
  chmod 755 "$helper_script"
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

  local helper_script="./ddrescue.sh"
  make_ddrescue_helper "$helper_script"
  _info "$(pwd)"
  sudo "$helper_script" "$copy_source" "$copy_dest" "$map_file" \
       "$event_log" "$rate_log" \
       "$trim" "$scrape"
  sudo chown $USER ./*
  return $?
}

get_commandline_from_map() {
  local map_file="$1"

  if [ ! -s "$map_file" ]; then
    _info "no map file"
    exit 1
  fi
  grep "# Command line: ddrescue" "$map_file"
}

resource_matches_map() {
  local device="$1"
  local map_file="$2"

  if [ -s "$map_file" ]; then
    # Spaces arounf $device matter!
    if grep -q "# Mapfile. Created by GNU ddrescue" "$map_file"; then
       grep -q " $device " "$map_file"
    else
      return 1
    fi
  else
    _info "$map_file" > /dev/stderr
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
    _error "map device = \"\"" > /dev/stderr
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
      return 1
      ;;
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
      return 1
      ;;
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
      return 1
      ;;
  esac
}

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
      return 1
      ;;
  esac
}

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
      return 1
      ;;
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
      return 1
      ;;
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
      return 1
      ;;
  esac
}

get_fs_type() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Type (Bundle):" | \
        sed -E 's/^.+: *([a-z]+) *$/\1/'
      ;;
    Linux)
      lsblk -n -d -o FSTYPE "$device"
      ;;
    *)
      return 1
      ;;
  esac
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
      return 1
      ;;
  esac
}

get_fs_blocksize() {
  local device="$1"

  case $(get_OS) in
    macOS)
      # macOS HFS+ -B works with drive blocks not filesystem blocks
      diskutil info "$device" | \
        grep "Device Block Size:" | \
        sed -E 's/^.+: *([0-9]+).*$/\1/'
      ;;
    Linux)
#       echo 512
      sudo blkid -p -o value --match-tag FSBLOCKSIZE "$device"
      ;;
    *)
      return 1
      ;;
  esac
}

is_gpt() {
  local device="$1"
#  _info \"$(get_partition_table_type "$device")\" >&2
  [ "$(get_partition_table_type "$device")" == "gpt" ]  
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
      ;;
    *)
      return 1
      ;;
  esac
}

is_hfsplus() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | grep -q Apple_HFS
      ;;
    Linux)
      [ $(get_fs_type "$device") == "hfsplus" ]
      ;;
    *)
      return 1
      ;;
  esac
}

is_ntfs() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | grep -q NTFS
      ;;
    Linux)
      [ $(get_fs_type "$device") == "ntfs" ]
      ;;
    *)
      return 1
      ;;
  esac
}

is_ext() {
  local device="$1"

  case $(get_OS) in
    macOS)
      return 1
      ;;
    Linux)
      [[ $(get_fs_type "$device") =~ ^ext[234]$ ]]
      ;;
    *)
      return 1
      ;;
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
        lsblk -f "$device" > /dev/null
      else
        lsblk -f "$device"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

get_partition_offset() {
  local device="$1"

  local offset
  case $(get_OS) in
    macOS)
      offset=$( diskutil info "$device" | \
        grep "Partition Offset" | \
        sed -E 's/^.*\(([0-9]*).*$/\1/' )
      ;;
    Linux)
      # Offset is returned in device blocks
      offset=$(lsblk -n -d -o START "$device")
      ;;
    *)
      offset=0
      ;;
  esac
  if [ -z $offset ]; then
    _error "partition offset lookup failed" >&2
    echo 0
    return 1
  fi
  echo $offset
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
      return 0
      ;;
  esac
}

strip_partition_id() {
  # From device
  case $(get_OS) in
    macOS)
      echo "$1" | sed 's/s[0-9][0-9]*$//'
      ;;
    Linux)
      echo "$1" | sed 's/[0-9][0-9]*$//'
      ;;
    *)
      echo "strip_partition_id unknown OS"
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

        _info "$device, device is entire drive" >&2
        _info "PARTITION LIST INCLUDES ESP: $include_efi" >&2

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

        _DEBUG "$device device is a partition ($(get_fs_type $device))"
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
        _info "$device has no eligible partitions" >&2
      else
        echo ${p[@]} ${v[@]}
      fi

      return 0
      ;;

    Linux)

      # The device is either a drive or a specific partition
      if [ "$device" != "$(strip_partition_id "$device")" ]; then
        _DEBUG "$device device is a partition ($(get_fs_type $device))"
        echo "${device#/dev/}"
        return
      else
        _info "$device, device is entire drive" >&2
        _info "PARTITION LIST INCLUDES ESP: $include_efi" >&2
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
          _info "$device has no eligible partitions" >&2
          return 1
        else
          _DEBUG XXX ${p[@]} 
          echo ${p[@]}
        fi
      fi
      ;;
    *)
      return 1
      ;;
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
      return 1
      ;;
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
      sudo systemd-umount "$device"
      return 0
      ;;
    *)
      return 1
      ;;
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
    _info "add_to_fstab: $volume_uuid already exists"
    return 0
  fi
#  _info "add_to_fstab: $volume_uuid $volume_name"

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
      os_unmount "$device"
      return
      ;;
    *)
      return 1
      ;;
  esac
}

remove_from_fstab() {
  local volume_uuid="$1"
#  local volume_name="$2"
#  local fs_type="$3"

  if ! grep -q -i "^UUID=$volume_uuid" /etc/fstab; then
    _error "$volume_uuid not found"
    return 1
  fi

  case $(get_OS) in
    macOS)
      # Juju with vifs to edit /etc/fstab
      # /<pattern> (go to line with pattern)
      # dd (delete line)
      # :wq (write & quit
      _info "$volume_uuid"
      EDITOR=vi
      sudo vifs <<EOF > /dev/null 2>&1
/^UUID=$volume_uuid
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
      return 1
      ;;
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
  _info "unmount_device: ${partitions[@]}"
  for (( p=0; p<${#partitions[@]}; p++ )); do
    local part=/dev/"${partitions[$p]}"
    _DEBUG "unmount_device: $part"

    # If no volume UUID, there's no meaning to fstab entry.
    # Volume likely read-only or not at all.
    volume_uuid="$(get_volume_uuid $part)"
    if [ -z "$volume_uuid" ]; then continue; fi

    _info "unmount_device: $volume_uuid"
    
    volume_name="$(get_volume_name $part)"
    fs_type=$(get_fs_type "$part")
    add_to_fstab "$volume_uuid" "$fs_type" "$volume_name" "$part"

    # Ubuntu & Mint will mount and unmount devices automatically
    # with changes to /etc/fstab, above.
    #
    # When using a VM, its device arbitration may influence auto-mount
    # logic but including a UUID in /etc/fstab seems to reliably prevent
    # auto-mount.
    #
    os_unmount "$part"
    ! is_mounted "$device" 
    let result+=$?
  done
  echo "/etc/fstab:"
  cat /etc/fstab; echo "done"
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
  _info "mount_Device: ${partitions[@]}"
  local p
  for (( p=0; p<${#partitions[@]}; p++ )); do
    local part=/dev/"${partitions[$p]}"
    _DEBUG -n "$part "

    volume_uuid="$(get_volume_uuid $part)"
    if [ -z "$volume_uuid" ]; then continue; fi
    
    _info "nmount_device: $volume_uuid"

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
  echo "/etc/fstab:"
  cat /etc/fstab; echo "done"
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
  case $(get_OS) in
    macOS)
      partitions=( $(list_partitions "$device" true) )
      _DEBUG "$device" "$(strip_partition_id "$device")"
      _DEBUG ${partitions[@]}

      local p nr_checked=0
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
        fs_type=$(get_fs_type "$part")
        _DEBUG "$part" "$fs_type"
        case $fs_type in
          hfs)
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
        fs_type=$(get_fs_type "$part")
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
              sudo fsck.hfs -f -y "$device"
            fi
            let result+=$?
            let nr_checked+=1
            ;;
          vfat)
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
            sudo fsck.exfat -p "$part"
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
      return 1
      ;;
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
#
Do_Zap_Blocks=false
Preview_Zap_Regions=true
#
Opt_Trim=true
Opt_Scrape=false

while getopts ":cfhmpsuzXZ" Opt; do
  case ${Opt} in
    c) # Copy and build block map and rate-log
      Do_Copy=true
      ;;
    f)
      Do_Fsck=true
      ;;
    h)
      usage | more; exit 0
      ;;
    m)
      Do_Mount=true
      ;;
    X)
      # For use with a scan copy (-c where destination=/dev/null) disable
      # ddrescue trimming of region following read error.
      #
      # With -N ddrescue will mark the block map at a read _error as extending
      # for 64KiB (128 512-byte blocks).
      #
      # Skipping trimming can avoid waiting for additional read timeouts if the
      # region has additional bad blocks.
      #
      # Because not every block is read, -N could cause print (-p) to report
      # files for blocks that are not actually unreadble.
      #
      # For a drive with large (GB) media files, such a small region is unlikely
      # to be part of multiple files.
      #
      # Regarding zap (-Z) each block in the map region will be read-tested
      # before overwriting it.
      #
      # When zap (-Z) is done for a scan map made with -N, the user should
      # examine the output of zap to see if additional blocks in the error
      # region were unreadable and not the implications on print (-p) The worst
      # case is files are implicated but not affected by bad blocks.
      #
      # -N can also be used with a proper copy with the proviso that the copy
      # must be inherently incomplete.
      Opt_Scrape=true
      ;;
    p)
      Do_Error_Files_Report=true
      ;;
    s)
      Do_Slow_Files_Report=true
      ;;
    u)
      Do_Unmount=true
      ;;
    z)
      # Only preview
      Do_Zap_Blocks=true
      Preview_Zap_Regions=true
      ;;
    Z)
      # Overwite blocks in the device one at a time using an existing map
      Do_Zap_Blocks=true
      Preview_Zap_Regions=false
      ;;
    *)
      usage
      _info "$(basename "$0"): Unknown option $1"
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
   true; then
  _info "$(basename "$0"): Nothing to do (-h for usage)"
  exit 0
fi

# USAGE 1

if $Do_Mount || $Do_Unmount || $Do_Fsck; then

  if \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
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
    _info "unmount: Disable automount..."
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
      echo "/etc/fstab:"
      cat /etc/fstab; echo
      exit
    fi
    if ! is_device "$Device" false; then
      _error "No such device $Device"
      exit 1
    fi
    _info "Enable automount and mount..."
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
  _info "Deprecated, doesn't work"
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
     false; then
    _error "Incompatible options (2)"
    exit 1
  fi

  if ! which ddrescue; then
    _error "ddrescue(1) not found on PATH"
    error
    _error "You can obtain ddrescue using homebrew or macports"
    _error "If you are not familiar with packages on macUS, use Homebrew."
    _error "//brew.sh/"
    exit 1
  fi

  if [ $# -ne 3 ]; then
    _error "Missing or extra parameters (2)"
    exit 1
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    _error "Command line args reversed?"
    exit 1
  fi

  # GLOBALS
  Label="$1" # Name for metadata folder including the ddrescue map.
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

  continuing=false

  # Verify paths don't collide
  result=0
  if ! absolute_path "$Label" > /dev/null; then
    _error "copy: Invalid label path $Label"
    let result+=1
  else
    Metadata_Path="$(absolute_path "$Label")"
  fi
  if ! absolute_path "$Copy_Source" > /dev/null; then
    _error "copy: Invalid source path $Copy_Source"
    let result+=1
  else
    Copy_Source="$(absolute_path "$Copy_Source")"
  fi
  if ! absolute_path "$Copy_Dest" > /dev/null; then
    _error "copy: Invalid destinationpath $Copy_Dest"
    let result+=1
  else
    Copy_Dest="$(absolute_path "$Copy_Dest")"
  fi
  _info "copy: Metadata path: $Metadata_Path"
  _info "copy: Source path: $Copy_Source"
  _info "copy: Dest path: $Copy_Dest"
  if [ $result -gt 0 ]; then exit 1; fi

  if [ "$Copy_Source" == "$Copy_Dest" ] || \
     [ "$Copy_Source" == "$Metadata_Path" ] || \
     [ "$Copy_Dest" == "$Metadata_Path" ]; then
    _error "copy: <label>, <source> and <destination> paths must differ"
    exit 1
  fi

  # Map_File remains relative to the metadata directory, no harm no foul.
  # Source and destination paths are absolute to avoid hazards.
  if ! mkdir -p "$Label"; then
    _error "copy: Can't create a data dir for \"$Label\""
    exit 1
  fi
  _DEBUG "copy: Matadata directory: ${Label}"
  if ! cd "$Label"; then echo "Setup _error (cd $Label)"; exit 1; fi

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
    _info "copy: Source is a file: $Copy_Source"
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
      _info "copy: Destination is /dev/null (scanning)"
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
      _info "copy: Destination is a file: $Copy_Dest"
    fi
  fi

  # Determine status: first-run or continuing.
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
      continuing=true
    else
      _error "copy: Existing block map ($Label) not for this destination"
      get_commandline_from_map "$Map_File"
      exit 1
    fi

    #
    # For files, check mtimes and reject if source is newer than dest
    #
    if [ -f "$Copy_Source" ] && [ -f "$Copy_Dest" ] && [ $continuing ]; then
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

  if $continuing; then
    echo "RESUMING COPY"
  elif is_device "$Copy_Dest" false || \
       [[ ! "$Copy_Dest" =~ ^/dev/null$ && -s "$Copy_Dest" ]]; then
    echo 'copy: *** WARNING DESTRUCTIVE ***'
    read -r -p "copy: OVERWTIE ${Copy_Dest}? [y/N] " response
    if [[ ! $response =~ ^[Yy]$ ]]; then
       _info "copy: ...STOPPED."
       exit 1
    fi
  fi

  if is_device "$Copy_Source" && ! unmount_device "$Copy_Source"; then
    _error "copy: Unmount failed $Copy_Source"
    exit 1
  fi
  if is_device "$Copy_Dest" && ! unmount_device "$Copy_Dest"; then
    _error "copy: Unmount failed $Copy_Dest"
    exit 1
  fi

  if ! run_ddrescue "$Copy_Source" "$Copy_Dest" "$Map_File" \
            "$Event_Log" "$Rate_Log" "$Opt_Trim" "$Opt_Scrape"; then
    _error "copy: something went wrong"
    exit 1
  fi

  exit 0
fi

# USAGE 3

if $Do_Error_Files_Report || $Do_Slow_Files_Report || \
   $Do_Zap_Blocks || $Do_Summarize_Zap_Regions; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck || \
     $Do_Copy || $Do_Smart_Scan || \
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
  Label="$1" # Name for metadata folder including the ddrescue map.
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

  if ! cd "$Label" > /dev/null 2>&1; then
    _error "report/zap: No metadata found ($Label)"; exit 1;
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    _error "report/zap: Command line args reversed?"
    exit 1
  fi

  if ! is_device "$Device" false; then
    if [ -f "$Device" ]; then
      _error "report/zap: Can't report on files (examine the rate log)"
      exit 1
    fi
    _error "report/zap: No such device ($Device)"
    exit 1
  fi
  # Don't accept the startup drive
  if device_is_boot_drive "$Device"; then
    _error "report/zap: Boot drive can't be used."
    exit 1
  fi

  if [ ! -s "$Map_File" ]; then
    _error "rreport/zap: No ddrescue block map ($Label). Create with -c"
    exit 1
  fi

  # Check existing mapfile to see if it lists <device> as device.
  #
  # For printing files, the mapfile for the whole drive is allowed
  # is allowed for a device that's a partition.
  #
  if [ -s "$Map_File" ]; then
    if ! resource_matches_map "$Device" "$Map_File"; then
      if $Do_Error_Files_Report || $Do_Slow_Files_Report; then
        #
        # Accept whole drive map for a partition device
        #
        x="$(strip_partition_id "$Device")"
        if ! resource_matches_map "$x" "$Map_File"; then
          _error "report: Existing block map ($Label) but not for $Device"
          get_commandline_from_map "$Map_File"
          exit 1
        fi
      else
        _error "report: Existing block map ($Label) but not for $Device"
        get_commandline_from_map "$Map_File"
        exit 1
      fi
    fi
  fi

  if $Do_Error_Files_Report || $Do_Slow_Files_Report; then

    if ! is_hfsplus "$Device" && \
       ! is_ext "$Device" && \
       ! is_ntfs "$Device"; then
      _error "report: Usupported volume type ($(get_fs_type "$Device")) req. HFS+, NTFS, ext2, ext3, ext4"
      exit 1
    fi
    if ! resource_matches_map "$Device" "$Map_File" &&
       ! resource_matches_map "$(strip_partition_id "$Device")" "$Map_File";
       then
      _error "report: Existing block map ($Label) but not for $Device"
      get_commandline_from_map "$Map_File"
      exit 1
    fi

    # <device> is a partition, but map may be for a drive.
    #
    # Filesystem reports (fsck/debugfs/ntfscluster) expect block
    # addresses to be partition relative.
    #
    # If <device> is a drive then an offset is needed.
    #
    if [ "$Device" != "$(get_device_from_ddrescue_map "$Map_File")" ]; then
      # Correspondence to the map was checked coming in,
      # so assume the map is for a whole drive, so compute offset.
      Partition_Offset=$(get_partition_offset "$Device")
      if [ -z $Partition_Offset ] || [ $Partition_Offset -eq 0 ]; then
        _info "report: partition offset fail"
        return 1
      fi
    fi
    _info "PARTITION OFFSET: $Partition_Offset blocks ($(get_device_blocksize "$Device") bytes per block)"

    if $Do_Error_Files_Report; then

      # Report on stdout and saved in report file
      create_ddrescue_error_blocklist \
        "$Device" \
        "$Map_File" \
        "$Error_Fsck_Block_List" \
        "$Partition_Offset"
#      cat "$Error_Fsck_Block_List"
      fsck_device "$Device" true "$Error_Fsck_Block_List" | \
        tee "$Error_Files_Report"
      _info "report: files affected by errors: $Label/$Error_Files_Report"

    elif $Do_Slow_Files_Report; then

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
      _info "report: files affected by slow reads: $Label/$Slow_Files_Report"

    else
      _error "report: MAINLINE GLITCH, SHOULD NOT HAPPEN"
    fi

    exit
  fi

  if $Do_Zap_Blocks; then
    if [ ! -s "$Map_File" ]; then
      _error "zap: No block map ($Label). Create with -c"
      exit 1
    fi
    # Drive or parition, the device and the map must agree.
    if ! resource_matches_map "$Device" "$Map_File";
       then
      _error "zap: Existing block map ($Label) but not for $Device"
      get_commandline_from_map "$Map_File"
      exit 1
    fi
    _info "zap: Umount and prevent automount..."
    if ! unmount_device "$Device"; then
      _error "zap: Unmount failed"
      exit 1
    fi

    zap_from_mapfile "$Device" \
                     "$Map_File" \
                     "$Zap_Block_List" \
                     $Preview_Zap_Regions
  fi

fi

cleanup
