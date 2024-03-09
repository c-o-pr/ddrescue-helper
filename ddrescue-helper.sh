#!/bin/bash
#/bin/bash --version

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
    -Z [DANGEROUS] Overwrite drive blocks at error regions specified by map data
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

  -p Report for HFS+ partition of files affected by error regions 
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

  -z Print a preview of error blocks to be zapped, allowing you to sanity check
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

error() {
  echo "*** $1" >&2
}

get_OS() {
  if which diskutil > /dev/null; then
    echo "macOS"
  else
    echo "Linux"
  fi
}

escalate() {
# XXX not used
  echo "Escalating privileges..."
  if ! sudo echo -n; then
    echo "sudo failed"
    exit 1
  fi
}

absolute_path() {
  # Run in a subshell to prevent hosing the current working dir.
  # XXX This breaks if current user cannot cd into a path element.
  (
    if [ -z "$1" ]; then return 1; fi
    if ! cd "$(dirname "$1")"; then return 1; fi
    case "$(basename $1)" in
        ..) echo "$(dirname $(pwd))";;
        .)  echo "$(pwd)";;
        *)  echo "$(pwd)/$(basename "$1")";;
    esac
  )
}

is_uuid() {
  # Older bash treats " as part of pattern
  [[ "$1" =~ ^[0-9A-F]+-[0-9A-F] ]]
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
  
  local res
  local max
  local c
  local t
  let max=3
  let c=1
  printf "zap_sequence: Processing $target %d (0x%X) %d:\n" "$block" "$block" "$count"
  while [ "$c" -le "$count" ]; do
    printf "%d (0x%X) read " "$block" "$block"
#    echo -n "$block read "
    let t=$(date +%s)+2
    read_block "$target" "$block" > /dev/null 2>&1
    let res=$?
    let t2=$(date +%s)
#    echo $t $t2
    if [ $res -ne 0 ] || [ $t -lt $t2 ]; then
      echo -n "FAILED ($res), write "
      write_block "$target" "$block"  > /dev/null 2>&1
      let res=$?
      if [ "$res" -ne 0 ] ; then
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
#    echo $block
    let block+=1
    let c+=1
    echo
  done
  echo "sequence done, $count"
}

zap_from_mapfile() {
  local device="$1"
  local map_file="$2"
  local zap_blocklist="$3" # side-effect
  local preview="${4:-true}"
  
  echo "$zap_blocklist"

  grep -v "^#" "$map_file" | \
  grep -E '0x[0-9A-F]+ +0x[0-9A-F]+' | \
  grep -e - -e / -e '*' | \
  ddrescue_map_bytes_to_blocks 512 \
  sort -n >| "$zap_blocklist"

  if [ ! -s "$zap_blocklist" ]; then
    echo "zap_from_mapfile: Missing or empty bad-block list"
    return 1
  fi
  if grep '[^0-9 ]' "$zap_blocklist"; then
    echo "zap_from_mapfile: Bad-block list should be a list of numbers"
    return 1
  fi

  local block
  local count
  local total_blocks
  let total_blocks=0
  if $preview; then
    echo "zap_from_mapfile: PREVIEW"
    echo "zap_from_mapfile: DEVICE BLOCK COUNT (hex)"
  fi
  cat "$zap_blocklist" | \
  ( \
  while read block count; do
    if [ "$block" == "" ] || [ "$block" -eq 0 ] || \
       [ "$count" == "" ] || [ "$count" -gt 500 ]; then
      echo "zap_from_mapfile: Bad block list: address is 0 or count > 500"
      return 1
    fi
    let total_blocks+=$count
    if $preview; then
      printf "$device %d %d (0x%X 0x%04X)\n" "$block" "$count" "$block" "$count"
    else
      zap_sequence "$device" "$block" "$count"
    fi
  done;
  if $preview; then echo "zap_from_mapfile: ZAP TOTAL = $total_blocks"; fi
  echo "zap_from_mapfile: done, total $total_blocks" 
  )
  
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

  if [ "$drive" == "" ]; then exit 1; fi

  start_smart_selftest "$drive"

  # Fixed count
  let fixed_count=0
  finished=false
  while [ $finished == false ]; do

    while sudo smartctl -a "$drive" | grep -i -C 3 "in progress"; do
      sleep 10;
#      echo WAITING
    done

    let x=$(sudo smartctl -a "$drive" | grep "^#" | \
               sed -e 's/\# *//' -e 's/  .*//' | tail -1)

    echo "log events $x, handled $fixed_count"

    #
    # XXX ADD A EXECUTION COMPLETE STATUS CHECK
    # When no more errors are listed since last test, work is done
    # Otherwise restart the test
    #
    if [ "$fixed_count" -eq "$x" ]; then finished=true; continue; fi

    create_smartctl_error_blocklist "$drive" "$smart_blocklist"

#   zap_from_smart "$drive"

    start_smart_selftest "$drive"

    let fixed_count=$x
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
      echo "sanity_check_block_address: unknown device type $device_type"
      return 1
      ;;
  esac
}

ddrescue_map_bytes_to_blocks() {
  local blocksize="${1:-512}"

  # Convert hex map data for byte addresses and extents
  # into decimal blocks.
  # Input (512):
  #   Addr   Len
  #   0x800  0x200  extraneous
  # Output:
  #   4      1
  # 0 or 0 are skipped.
  #
  local addr
  local len
  while read addr len x; do
    addr=$(( addr / blocksize ))
    len=$(( len / blocksize ))
    # Edge case
    if  (( addr == 0 || len == 0 )); then continue; fi
    # decimal
    echo $addr $len
  done
}

parse_ddrescue_map_for_fsck() {
  local map_file="$1"
  local fsck_blocklist="$2" # side-effect

  # Pull a list of error extents from the map
  # convert them from byte to block addresses
  # and emit a list of corresponding blocks.
  #
  # The map file is a list of byte addresses.
  # EXTS just for debugging the calculation.
  local block
  local count
  grep -v '^#' "$map_file" | \
  grep -E '0x[0-9A-F]+ +0x[0-9A-F]+' | \
  grep -e - -e / -e '*' | \
  ddrescue_map_bytes_to_blocks | tee "$fsck_blocklist.EXTS" | \
  sort -n | \
  while IFS=" " read block count; do
    let block=$block-$partition_offset
    if [ "$block" == "" ] || [ "$block" -eq 0 ] || \
       [ "$count" == "" ] || [ "$count" -eq 0 ]; then break; fi
    for (( i = 0; i < count; i++ )); do
      echo $(( block + i ))
    done
  done 
}

parse_rate_log_for_fsck() {
  local rate_log="$1"
  local slow_blocklist="$2" # Output file name
  local slow_limit="$3" # Regions slower than this are selected

  local n
  local addr
  local rate
  local ave_rate
  local bad_areas
  local bad_size
  local interval
  local block
  local count
  grep -h -E "^ *[0-9]+  0x" "${rate_log}"-* | \
  while IFS=" " read n addr rate ave_rate bad_areas bad_size; do
    # Log entires are issued once per second Compute a sparse list of blocks
    # based on the rate for that second to cover the region with 10 samples at
    # evenly spaced intervals. Advanced Format drives are fundamentally 4096
    # byte formats, so place samples on mod 4096 byte intervals
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
  # EXTS just for debugging the calculation
  uniq | \
  sort -n | \
  ddrescue_map_bytes_to_blocks | tee "$slow_blocklist.EXTS" | \
  while read block count; do
    let block=$block-$partition_offset
    if [ "$block" == "" ] || [ "$block" -eq 0 ] || \
       [ "$count" == "" ] || [ "$count" -eq 0 ]; then break; fi
    for (( i = 0; i < count; i++ )); do
      echo $(( block + i ))
    done
  done >| "$slow_blocklist"
}

create_ddrescue_error_blocklist() {
  local device="$1"
  local map_file="$2"
  local fsck_blocklist="$3" # side-effect
  local blocksize="${4:-512}"

  # Translate a map file into a list of blocks that can be
  # used with fsck -B to list files.
  #
  # Check if map file is a drive-relative or partition relative.
  # If drive relative, compute the partition offset and subtract
  # it from the drive block adddresses, as fsck is partition-relative
  # addresssing.
  #
  # fsck_hfs expects block addresses to be drive relative
  # fsck is relative to partition, so if <device> is a drive
  # then compute offset.
  #
  # At this point we know <device> is a partition not a drive.
  local partition_offset
  local map_device
  let partition_offset=0
  map_device=$(get_device_from_ddrescue_map "$map_file")
  if [ "$device" != "$map_device" ]; then
    # Assume the map is for a drive, so compute offset.
    partition_offset=$(get_partition_offset "$device")
  fi
  echo "ERROR BLOCKLIST: $fsck_blocklist"
  parse_ddrescue_map_for_fsck "$map_file"  "$fsck_blocklist" >| "$fsck_blocklist"
  
  if [ ! -s "$fsck_blocklist" ]; then
    echo "create_ddrescue_error_blocklist: NO ERROR BLOCKS"
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
    echo "create_smartctl_error_blocklist: NO ERROR BLOCKS"
    exit 0
  fi
}

create_slow_blocklist() {
  local device="$1"
  local map_file="$2"
  local rate_log="$3"
  local slow_blocklist="$4" # Output file name
  local slow_limit="${5:-1000000}" # Regions slower than this are selected

  # This only makes sense for drives, not for regular files.
  # Create a list of block addresses for rate log entires with eads slower
  # rate_limit in bytes per second
  local partition_offset

  # fsck_hfs expects block addresses to be drive relative
  # fsck is relative to partition, so if <device> is a drive
  # then compute offset.
  #
  # At this point we know <device> is a partition.
  let partition_offset=0
  map_device=$(get_device_from_ddrescue_map "$map_file")
  if [ "$device" != "$map_device" ]; then
    # Assume the map is for a drive, so compute offset.
    partition_offset=$( diskutil info "$device" | grep "Partition Offset" | \
      sed -E 's/^.*\(([0-9]*).*$/\1/' )
    echo "PARTITION OFFSET: $partition_offset"
    if [ "$partition_offset" == "" ] || [ "$partition_offset" -eq 0 ]; then
      echo "Something went wrong calculating partition offset"
      return 1
    fi
  fi

  echo "SLOW BLOCKLIST ($slow_limit bytes per sec): $slow_limit"
  parse_rate_log_for_fsck "$rate_log" "$slow_blocklist" "$slow_limit" >> \ 
    "$slow_blocklist"

  if [ ! -s "$slow_blocklist" ]; then
    echo "create_slow_blocklist: NO SLOW BLOCKS"
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
    echo "make_ddrescue_helper: ddrescue not found on PATH"
    return 1
  fi

  # Don't let an old helper script bollacks the work
  if [ -s "$helper_script" ]; then
    if ! rm -f "$helper_script"; then
      echo "make_ddrescue_helper: error, coouldn't replace exosting helper"
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
  local c
  let c=0
  # Get name of latest rate log; squelch error if none.
  last_log="$(ls -1 -t  ${rate_log}-* | head -1)" 2> /dev/null
  if [ "$last_log" == "" ]; then
    # XXX If more than 1000 rate logs the naming gets janky but it
    # will still work.
    echo "${rate_log}-000"
  else
    # xxx-000 -> c=0+1 --> xxx-001
    let c=${last_log##*-}; let c++
    echo $(printf "${rate_log}-%03d" $c)
  fi
}

# Make sure that missing paramters don't lead to
# a disaster with ddrescue
#if [ ${#args[@]} -lte 5 ]; then

missing=false
args=("$@")
for (( i=0; i<=4; i++ )); do
  if [ "${args[$i]}" == "" ]; then missing=true; fi
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

let tries=0
let max=10
finished=false
while ! $finished && [ "$tries" -lt "$max" ]; do
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
  echo "run_ddrescue: $(pwd)"
  sudo "$helper_script" "$copy_source" "$copy_dest" "$map_file" \
       "$event_log" "$rate_log" \
       "$trim" "$scrape"
  return $?
}

########################
# DEVICE LOGIC FUNCTIONS
########################

resource_exists() {
  [ -f "$1" ] || [ -L "$1" ] || [ -b "$1" ] || [ -c "$1" ]
}

get_inode() {
  local path="$1"
  if [ ! -f "$path" ]; then return 1;  fi
  case $(get_OS) in
    macOS)
      stat -f %i "$path" 2> /dev/null
      ;;
    Linux)
      return 1
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
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

get_commandline_from_map() {
  local map_file="$1"
  if [ ! -s "$map_file" ]; then
    echo "get_commandline_from_map: no map file"
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
    echo "resource_matches_map: no map file: $map_file" > /dev/stderr
    return 1
  fi
}

get_partition_uuid() {
  local dev="$1"
  # XXX Not used.
  case $(get_OS) in
    macOS)
      diskutil info "$dev" | \
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
  local dev="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$dev" | \
        grep "Volume UUID:" | \
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

get_volume_name() {
  local device="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$device" | \
        grep "Volume Name:" | \
        sed -E 's/^.+: +(.+)$/\1/'
      ;;
    Linux)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

get_fs_type() {
  local part="$1"

  case $(get_OS) in
    macOS)
      diskutil info "$part" | \
        grep "Type (Bundle):" | \
        sed -E 's/^.+: *([a-z]+) *$/\1/'
      ;;
    Linux)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

is_mounted() {
  local dev="$1"
  local mounted

  case $(get_OS) in
    macOS)
      mounted=$(diskutil info "$dev" | \
                grep "Mounted:" | \
                sed -E 's/^.+: +([^ ].+)$/\1/')
      [ "$mounted" == "Yes" ]
      ;;
    Linux)
      return 1
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
      lsblk -f "$device" | grep -q "hfsplus"
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
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

get_partition_offset() {
  local device="$1"

  case $(get_OS) in
    macOS)
      local offset
      offset=$( diskutil info "$device" | grep "Partition Offset" | \
                sed -E 's/^.*\(([0-9]*).*$/\1/' )
      echo "PARTITION OFFSET: $offset" >&2
      if [ "$offset" == "" ] || [ "$offset" -eq 0 ]; then
        echo "Something went wrong calculating partition offset" >&2
        echo "0"
        return 1
      fi
      echo "$offset"
      return 0
      ;;
    Linux)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

device_is_boot_drive() {
  local device="$1"
  local boot_drive

# XXX
#  local x
#      x=$( diskutil list /dev/disk1 | \
#             grep "Physical Store" | \
#             sed -E 's/.+(disk[0-9]+).+$/\1/')
#      if [ "$x" != "" ]; then
#        if [[ $(strip_parition_id "$device" =~ "$x" ]]; then
#           return 1
#        fi
#      else
#      fi
# XXX

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
      if [ "$(strip_partition_id "$device")" == "$boot_drive" ]; then
        return 0
      fi
      return 1
      ;;
    *)
      return 0
      ;;
  esac
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
  if [ "$x" == "" ]; then
    error "get_device_from_ddrescue_map: map device = \"\"" > /dev/stderr
    exit 1
  fi
  echo "$x"
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

  # Outputs a list of drive partitions strings stripped of /dev/
  # E.g., "disk21s2 disk21s3" or "sdb2 sdb3"
  # The first partition on the drive is assumed to be
  # If <device> is a drive, all it's partitions are returned
  # including partitions within containers.
  # Comntainers may not be nested.

  # XXX return values are on stdout
  # XXX ensure debug goes to stderr
  # XXX        mapfile partitions < \
  # XXX         <( diskutil list "$device" | \
  # XXX            grep '^ *[2-9][0-9]*:' | \
  # XXX            sed -E 's/^.+(disk[0-9]+s[0-9]+).*$/\1/' )

  case $(get_OS) in

    macOS)
      # Single partition vs a drive with possible multiple parts
      # device will be a /dev spec, but diskutil list doesn't output "/dev/"
      #
      # Parse out container disks (physical stores) and
      # Follow containers to the synthesized drive.
      # (not-container v. container)
      # "Container diskxx" -> Contains
      # "Physical Store" -> Contained
      # Multiple containers are allowed.
      # Containers cannot be nested.

      echo "PARTITION LIST INCLUDES ESP: $include_efi" >&2
#      echo "list_partitions: $device" >&2
      local p=""
      local c
      local v

      # The device is either a drive or a specific partition
      if [ "$device" == "$(strip_partition_id "$device")" ]; then

        echo "list_partitions: $device, device is entire drive" >&2
        # The EFI service parition is optionally included in the list
        # It is never auto-mounted by default
        # grep -v means invert match
        if $include_efi; then
          p=( $(diskutil list "$device" | \
            grep -v -e "Container disk" | \
            grep '^ *[1-9][0-9]*:' | \
            sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        else
          p=( $(diskutil list "$device" | \
            grep -v -e "EFI EFI" -e "Container disk" | \
            grep '^ *[1-9][0-9]*:' | \
            sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        fi
        # Get drive's containers, if any
        c=( $(diskutil list "$device" | \
          grep "Container disk" | \
          sed -E 's/^.+Container (disk[0-9]+).+$/\1/') )

      else
      
        echo "list_partitions: $device, device is a partition" >&2
        # Get the one conmtainer, if any
        p=( $(diskutil info "$device" | \
          grep "APFS Container:" | \
          sed -E 's/^.+(disk[0-9]+)$/\1/') )
#        echo "list_partitions: p=${p[@]}" >&2

        # No container, just a basic partition
        if [ "$p" == "" ]; then
          # Return supplied device minus "/dev/" to agree with
          # output of diskutil for other cases
          echo "${device#/dev/}"
          return 0
        else
          # Is a container, so process it
          c=( $(diskutil list "$p" | \
            grep "Container disk" | \
            sed -E 's/^.+Container (disk[0-9]+).+$/\1/') )
#          echo "list_partitions: c=${c[@]}" >&2
          # continue on to process the container
        fi

      fi

#      echo "list_partitions: p=${p[@]}" >&2
#      echo "list_partitions: c=${c[@]}" >&2

      # For all containers, process their contents as volumes
      v=""      
      if [ "$c" != "" ]; then
        for x in ${c[@]}; do
          # Contained volumes begin at continaer's partition index 1
          v=( ${v[@]} $(diskutil list "$x" | \
                  grep '^ *[1-9][0-9]*:' | \
                  sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        done
#        echo "list_partitions: v=${v[@]}" >&2
      fi

      if [ "$p" == "" -a "$v" == "" ]; then
        echo "list_partitions: $device has no eligible partitions" >&2
      else
        echo ${p[@]} ${v[@]}
      fi

      return 0
      ;;
    Linux)
      # diskutil list
      #lsblk -o NAME,FSTYPE,LABEL,MOUNTPOINTS,UUID "$device"
      # diskutil info
      #sudo blkid -o export --probe --info  "$device"
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

#######################
# MOUNT, UNMOUNT & FSCK
#######################

add_to_fstab() {
  case $(get_OS) in
    macOS)
      local volume_uuid="$1"
      local fs_type="$2"
      local volume_name="${3:-(name unspecified)}"
      local device="${4:-(device unspecified)}"

      if [ "$#" -lt 2 ]; then
        # fstab entires must list the correct filesystem type or
        # they won't be honored by the system.
        error "add_to_fstab: error misssing parameters"
        return 1
      fi
      if grep -q "^UUID=$volume_uuid" /etc/fstab; then
        # XXX Add update of particulars
        echo "add_to_fstab: $volume_uuid already exists"
        return 0
      fi

      echo "add_to_fstab: $volume_uuid $volume_name"
      # Juju with vifs to edit /etc/fstab
      #
      # G (got to end)
      # A (append at end of line)
      # :wq (write & quit
      # THERE'S A NEEDED <ESC> CHARACTER EMBEDDED BEFORE :wq
      #
      # XXX Convert to ex(1)
      EDITOR=vi
      sudo vifs <<EOF1 > /dev/null 2>&1
GA
UUID=$volume_uuid none $fs_type rw,noauto # "$volume_name" $device:wq
EOF1
      if [ $? -ne 0 ]; then
        error "add_to_fstab: vifs failed"
        return 1
      fi
      return 0
      ;;
    Linux)
      # get mount info and savein fstab
      # sudo systemd-ummount device
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

remove_from_fstab() {
  case $(get_OS) in
    macOS)
      local volume_uuid="$1"
#      local volume_name="$2"
#      local fs_type="$3"

      if ! grep -q "^UUID=$volume_uuid" /etc/fstab; then
        echo "remove_from_fstab: $volume_uuid not found"
        return 0
      fi
      # Juju with vifs to edit /etc/fstab
      # /<pattern> (go to line with pattern)
      # dd (delete line)
      # :wq (write & quit
      echo "remove_from_fstab: $volume_uuid"      
      EDITOR=vi
      sudo vifs <<EOF2 > /dev/null 2>&1
/^UUID=$volume_uuid
dd:wq
EOF2
      if [ $? -ne 0 ]; then
        error "remove_from_fstab: vifs failed"
        return 1
      fi
      ;;
    Linux)
      # get mount info and savein fstab
      # sudo systemd-ummount device
      return 1
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
  local partitions
  local volume_uuid
  local volume_name
  local fs_type
  local result
  
  let result=0
  case $(get_OS) in
    macOS)
      # Single partition vs a drive with possible multiple parts
      # device will be a /dev spec, but diskutil list doesn't include "/dev/"
      local p
      local r
      partitions=( $(list_partitions "$device") )
      echo "unmount_device: unmounting ${partitions[@]}"
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
#        echo -n "$part "

        # If no volume UUID, there's no meaning to fstab entry.
        # Volume likely read-only or not at all.
        volume_uuid="$(get_volume_uuid $part)"
        if [ -z "$volume_uuid" ]; then continue; fi

        volume_name="$(get_volume_name $part)"
        fs_type=$(get_fs_type "$part")        

        add_to_fstab "$volume_uuid" "$fs_type" "$volume_name" "$part"
        let result+=$?

        sudo diskutil umount "$part"
#        let result+=$?
      done
      echo "/etc/fstab:"
      cat /etc/fstab; echo
      return $result
      ;;
    Linux)
      # get mount info and savein fstab
      # sudo systemd-ummount device
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

mount_device() {
  local device="$1"

  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  local partitions
  local volume_uuid
  local volume_name
  local result

  let result=0
  case $(get_OS) in
    macOS)
#      echo "$device" "$(strip_partition_id "$device")"
      partitions=( $(list_partitions "$device") )
#      echo ${partitions[@]}
      echo "mount_device: mounting ${partitions[@]}"
      local p
      local r
      let r=0
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
#        echo -n "$part "

        volume_uuid="$(get_volume_uuid $part)"
        volume_name="$(get_volume_name $part)"

        remove_from_fstab "$volume_uuid" "$volume_name"
        let result+=$?

        sudo diskutil mount "$part"
        let result+=$?
      done
      echo "/etc/fstab:"
      cat /etc/fstab; echo
      return $result
      ;;
    Linux)
      # find saved mount info in fstab and remove, if can't find then
      #   get LABEL, UUD, GID, USERNAME
      # sudo systemd-mount -o uid=UID,gid=GID,rw device /media/USER/LABEL
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

fsck_device() {
  local device="$1"
  local find_files="${2:-false}"
  local blocklist="$3"

  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  local partitions
  local volume_uuid
  local result
  local nr_checked
  local fs_type
  let result=0

  if $find_files && [ "$blocklist" == "" -o ! -f "$blocklist" ]; then 
    echo "fsck_device; missing block list for find files"
    return 1
  fi

  # If <device> is a specific partition, check it.
  # If a whole drive, check them all.
  case $(get_OS) in
    macOS)
      partitions=( $(list_partitions "$device" true) )
#      echo "$device" "$(strip_partition_id "$device")"
#      echo ${partitions[@]}
      let nr_checked=0
      local p
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
        fs_type=$(get_fs_type "$part")
        echo "fsck_device: $part" "$fs_type"
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
      if ! which fsck.hfs; then
        echo "Need a version of fsck for HFS+"
        return 1
      fi
      sudo fsck.hfs -f -y "$device"
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
Preview_Zap_Regions=false
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
      # With -N ddrescue will mark the block map at a read error as extending
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
      ;;
    *)
      usage
      error "$(basename "$0"): Unknown option $1"
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
  echo "$(basename "$0"): Nothing to do (-h for usage)"
  exit 0
fi

# USAGE 1

if $Do_Mount || $Do_Unmount || $Do_Fsck; then

  if \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Zap_Blocks || \
     false; then
    error "Incompatible options (1)"
    exit 1
  fi

  if [ $# -ne 1 ]; then
    error "Missing or extra parameter (1)"
    exit 0
  fi

  Device="$1"

  if $Do_Unmount; then
    if $Do_Mount; then
      error "unmount: Incompatible options (1a)"
      exit 1
    fi
    if ! is_device "$Device" false; then
      error "unmount: No such device $Device"
      exit 1
    fi
    echo "unmount: Disable automount..."
    if ! unmount_device "$Device"; then
      error "unmount: Unmount(s) failed"
      exit 1
    fi
    exit 0
  fi

  if $Do_Mount; then
    if $Do_Unmount || $Do_Fsck; then
      error "mount: Incompatible options (1b)"
      exit 1
    fi

    # Various use-cases can leave an orphan UUID in /etc/fstab
    # The user could remove it with vifs(8). 
    # This just makes it simpler.
    # Allow "UUID=" in string
    if is_uuid "${Device/UUID=}"; then
      # Just remove it from /etc/fstab
      remove_from_fstab "${Device/UUID=}"
      echo "/etc/fstab:"
      cat /etc/fstab; echo
      exit
    fi
    if ! is_device "$Device" false; then
      error "mount: No such device $Device"
      exit 1
    fi
    echo "mount: Enable automount and mount..."
    if ! mount_device "$Device"; then
      error "mount: errors occurred"
      exit 1
    fi
    exit 0
  fi

  if $Do_Fsck; then
    if $Do_Mount; then
      error "fsck: Incompatible options (1c)"
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
    error "smartscan: Incompatible options (2)"
    exit 1
  fi
  
  if [ $# -ne 1 ]; then
    error "smartscan: Missing or extra parameters (2)"
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
  echo "smartscan: Deprecated, doesn't work"
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
    error "copy: Incompatible options (2)"
    exit 1
  fi

  if ! which ddrescue; then
    error "ddrescue(1) not found on PATH"
    error 
    error "You can obtain ddrescue using homebrew or macports"
    error "If you are not familiar with packages on macUS, use Homebrew."
    error "https://brew.sh/"
    exit 1
  fi

  if [ $# -ne 3 ]; then
    error "copy: Missing or extra parameters (2)"
    exit 1
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    error "copy: Command line args reversed?"
    exit 1
  fi

  # GLOBALS
  Label="$1" # Name for metadata folder including the ddresxcue map.
  Copy_Source="$2"
  Copy_Dest="$3"

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Blklist="$Label.fsck-blocklist"
  Zap_Blklist="$Label.zap-blocklist"
  Smart_Blklist="$Label.smart-blocklist"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log"
  Files_Log="$Label.files-log"
  Metadata_Path=""
  
  continuing=false

  # Verify paths don't collide
  let res=0
  if ! absolute_path "$Label" > /dev/null; then
    error "copy: Invalid label path $Label"
    let res=+1
  else
    Metadata_Path="$(absolute_path "$Label")"
  fi
  if ! absolute_path "$Copy_Source" > /dev/null; then
    error "copy: Invalid source path $Copy_Source"
    let res=+1
  else
    Copy_Source="$(absolute_path "$Copy_Source")"
  fi
  if ! absolute_path "$Copy_Dest" > /dev/null; then
    error "Invalid destinationpath $Copy_Dest"
    let res=+1
  else
    Copy_Dest="$(absolute_path "$Copy_Dest")"
  fi
  echo "copy: Metadata path: $Metadata_Path"
#  echo "copy: Source path: $Copy_Source"
#  echo "copy: Dest path: $Copy_Dest"
  if [ $res -gt 0 ]; then exit 1; fi

  if [ "$Copy_Source" == "$Copy_Dest" ] || \
     [ "$Copy_Source" == "$Metadata_Path" ] || \
     [ "$Copy_Dest" == "$Metadata_Path" ]; then
    error "copy: <label>, <source> and <destination> paths must differ"
    exit 1
  fi
  
  # Map_File remains relative to the metadata directory, no harm no foul.
  # Source and destination paths are absolute to avoid hazards.
  if ! mkdir -p "$Label"; then
    error "copy: Can't create a data dir for \"$Label\""
    exit 1
  fi
#  echo "copy: Matadata directory: ${Label}"
  if ! cd "$Label"; then echo "Setup error (cd $Label)"; exit 1; fi

  # Verify Copy_Source is eligible
  if is_device "$Copy_Source" false; then
    if device_is_boot_drive "$Copy_Source"; then
      error "copy: Boot drive can't be used."
      exit 1
    fi
  else
    if [ "$?" == "2" ]; then
      # Specs "/dev/" but no such device.
      error "copy: $Copy_Source: device not found"
      exit 1
    fi
    # Is file
    #
    if [ -d "$Copy_Source" ]; then
      error "copy: Source cannot be a directory: $Copy_Source"
      exit 1
    fi
    if ! resource_exists "$Copy_Source"; then
      error "copy: No such file $Copy_Source"
      exit 1
    fi
    if _t="$(get_symlink_target "$Copy_Source")"; then
      error "copy: Source cannot be symlink: $Copy_Source -> $_t"
      exit 1
    fi
    if _t="$(get_alias_target "$Copy_Source")"; then
      error "copy: Source cannot be alias: $Copy_Source -> $_t"
      exit 1
    fi
    echo "copy: Source is a file: $Copy_Source"
  fi
    
  # Verify Copy_Dest is eligible
  if is_device "$Copy_Dest" false; then
    if device_is_boot_drive "$Copy_Dest"; then
      error "copy: Boot drive can't be used."
      exit 1
    fi
    # Continue
  else
    if [ "$?" == "2" ]; then
      # Specs "/dev/" but no such device.
      error "copy: $Copy_Dest: device not found"
      exit 1
    fi
    # Is file
    if [ -d "$Copy_Dest" ]; then
      error "copy: Destionation cannot be a directory: $Copy_Dest"
      exit 1
    fi
    if [ "$Copy_Dest" == "/dev/null" ]; then
      echo "copy: Destination is /dev/null (scanning)"
    else
      if _t="$(get_symlink_target "$Copy_Dest")"; then
        error "copy: Destination cannot be symlink: $Copy_Dest -> $_t"
        exit 1
      fi
      if _t="$(get_alias_target "$Copy_Dest")"; then
        error "copy: Destination cannot be alias: $Copy_Dest -> $_t"
        exit 1
      fi
      Opt_Scrape=true
      echo "copy: Destination is a file: $Copy_Dest"
    fi
  fi

  # Determine status: first-run or continuing.
  if [ -s "$Map_File" ]; then
    
    if ! resource_matches_map "$Copy_Source" "$Map_File"; then
      # XXX Can't distingush between source and dest in the map.
      # XXX IF src /dst were reversed this would still pass.
      error "copy: Existing block map ($Label) but not for $Copy_Source"
      get_commandline_from_map "$Map_File"
      exit 1
    fi
    if resource_matches_map "$Copy_Dest" "$Map_File"; then
      if [ -s "$Copy_Dest" ]; then
        # XXX Fair assumption
        # XXX Could compare the first two blocks of source / dest to verify
        continuing=true;
      else
        error "copy: Existing block map ($Label) but missing destination file $Copy_Dest"
        exit 1          
      fi
      # Contimue
    else
      error "copy: Existing block map ($Label) not for this destination"
      get_commandline_from_map "$Map_File"
      exit 1
    fi

    #
    # For files, check mtimes and reject if source is newer than dest
    #
    if [ -f "$Copy_Source" ] && [ -f "$Copy_Dest" ] && [ $continuing ]; then
      if [ $(stat -f %m "$Copy_Source") -gt $(stat -f %m "$Copy_Dest") ]; then
        error "copy: Block map exists and source is newer than destinmation, quitting"
        exit 1
      fi
    fi
  fi

  # Unlikely edge case of hard links to same file
  if [ "$(get_inode "$Copy_Source")" == "$(get_inode "$Copy_Dest")" ]; then
    error "copy: source & destination are same file (inode: $(get_inode "$Copy_Source"))"
    exit 1
  fi

  if $continuing; then
    echo "RESUMING COPY"
  elif is_device "$Copy_Dest" false || \
       [[ ! "$Copy_Dest" =~ ^/dev/null$ && -s "$Copy_Dest" ]]; then
    echo 'copy: *** WARNING DESTRUCTIVE ***'
    read -r -p "copy: OVERWTIE ${Copy_Dest}? [y/N] " response
    if [[ ! $response =~ ^[Yy]$ ]]; then
       echo "copy: ...STOPPED."
       exit 1
    fi
  fi

  if is_device "$Copy_Source" && ! unmount_device "$Copy_Source"; then
    error "copy: Unmount failed $Copy_Source"
    exit 1
  fi
  if is_device "$Copy_Dest" && ! unmount_device "$Copy_Dest"; then
    error "copy: Unmount failed $Copy_Dest"
    exit 1
  fi

  if ! run_ddrescue "$Copy_Source" "$Copy_Dest" "$Map_File" \
            "$Event_Log" "$Rate_Log" "$Opt_Trim" "$Opt_Scrape"; then
    error "copy: something went wrong"
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
    error "Incompatible options (3)"
    exit 1
  fi

  # Need a label and metadata
  if [ $# -ne 2 ]; then
    error "Missing or extra parameters (3)"
    exit 1
  fi

  # GLOBALS
  Label="$1" # Name for metadata folder including the ddresxcue map.
  Device="$2"
  # Device is required becuase a although a map contains a command-line record
  # of the output device, which could be extracted, the map can be for a whole
  # drive, while a report must be for a partition.

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Blklist="$Label.error-blocklist"
  Slow_Fsck_Blklist="$Label.slow-blocklist"
  Zap_Blklist="$Label.zap-blocklist"
  Smart_Blklist="$Label.smart-blocklist"
  Slow_Blklist="$Label.slow-blocklist"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log" # Incremeted if exists
  Error_Files_Report="$Label.ERROR-FILES-REPORT"
  Slow_Files_Report="$Label.SLOW-FILES-REPORT"

  if ! cd "$Label" > /dev/null 2>&1; then
    error "No metadata found ($Label)"; exit 1;
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    error "Command line args reversed?"
    exit 1
  fi

  # Prints device details if not a plain file
  if ! is_device "$Device" false; then
    error "Reports require a partition device, not a regular file"
    exit 1
  fi

  # Don't accept the startup drive or regaulr files
  if device_is_boot_drive "$Device"; then
    error "Boot drive can't be used."
    exit 1
  fi

  # Check existing mapfile to see if it lists <device> as device.
  #
  # For printing files, the mapfile for the whole drive is allowed
  # is allowed for a device that's a partition.
  #
  if [ -s "$Map_File" ]; then
    if ! resource_matches_map "$Device" "$Map_File"; then
      if $Do_Error_Files_Report || $Do_Slow_Files_Repor; then
        #
        # Accept whole drive map for a partition device
        #
        x="$(strip_partition_id "$Device")"
        if ! resource_matches_map "$x" "$Map_File"; then
          error "report: Existing block map ($Label) but not for $Device"
          get_commandline_from_map "$Map_File"
          exit 1
        fi
      else
        error "report: Existing block map ($Label) but not for $Device"
        get_commandline_from_map "$Map_File"
        exit 1
      fi
    fi
  fi

  if $Do_Error_Files_Report || $Do_Slow_Files_Report; then

    if [ ! -s "$Map_File" ]; then
      error "report: No ddrescue block map ($Label). Create with -c"
      exit 1
    fi
    if ! is_hfsplus "$Device"; then
      error "report: Must be an hfsplus partition"
      exit 1
    fi
    if ! resource_matches_map "$Device" "$Map_File" &&
       ! resource_matches_map "$(strip_partition_id "$Device")" "$Map_File";
       then
      error "report: Existing block map ($Label) but not for $Device"
      get_commandline_from_map "$Map_File"
      exit 1
    fi

    if $Do_Error_Files_Report; then
      create_ddrescue_error_blocklist "$Device" "$Map_File" "$Error_Fsck_Blklist"
#      cat "$Error_Fsck_Blklist"

      fsck_device "$Device" true "$Error_Fsck_Blklist" | \
        tee "$Error_Files_Report"
      echo "report: files affected by errors: $Label/$Error_Files_Report"
    elif $Do_Slow_Files_Report; then
      create_slow_blocklist "$Device" "$Map_File" "$Rate_Log" "$Slow_Fsck_Blklist"
#      cat "$Slow_Fsck_Blklist"

      fsck_device "$Device" true "$Slow_Fsck_Blklist" | \
        tee "$Slow_Files_Report"
      echo "report: files affected by slow reads: $Label/$Slow_Files_Report"
    else
      error "report: MAINLINE GLITCH, SHOULD NOT HAPPEN"
    fi

    # Report on stdout and saved in report file
    exit
  fi

  if $Do_Zap_Blocks; then
    if [ ! -s "$Map_File" ]; then
      error "zap: No block map ($Label). Create with -c"
      exit 1
    fi
    # Drive or parition, the device and the map must agree.
    if ! resource_matches_map "$Device" "$Map_File";
       then
      error -n "zap: Existing block map ($Label) but not for $Device"
      get_commandline_from_map "$Map_File"
      exit 1
    fi
    echo "zap: Umount and prevent automount..."
    if ! unmount_device "$Device"; then
      error "zap: Unmount failed"
      exit 1
    fi

    zap_from_mapfile "$Device" "$Map_File" \
                     "$Zap_Blklist" $Preview_Zap_Regions
  fi

fi

cleanup