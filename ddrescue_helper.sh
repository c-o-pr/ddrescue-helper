#!/bin/bash

usage() {
  cat << USAGE
$(basename "$0") Usage:

  WARNING! DESTRUCTIVE TO DATA!
  
  BEFORE USING REVIEW THE DOCUMENTATION FOR GNU ddrescue.
  
  STUDY THIS USAGE CAREFULLY BEFORE USING -Z

  -m | -u | -f <device>
    -> unmount / mount / fsck

  -c [ -X ] <label> <source> <destination>
    -> copy

    <destination> = /dev/null to scan <source> producing a map.

  -p | -s | -z | -Z <label> <device>
    -> print affected files reports / zap-blocks

    -p report files affected by read errors in map data.
    -s report files affected by slow reads in rate log.
    -z print a summary of LBA extents affected by read errors
       This is a sanity check for -Z. Large areas of errors
       indicates a failed drive and zapping is impractible.
    -Z Overwrite drive blocks at error regions specified by map data
       to help trigger <device> to re-allocate underlying sectors.

  <label> Name for a directory created to contain ddrescue map and log data.

  <device> /dev entry for an block storage device.
    IMPORTANT: See description below.

    On macOS, use the "r" form of the device special file to get full speed
    direct drive access (e.g., /dev/rdisk2).

    If <device> is a whole drive, all its volumes are affected.

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

  -m Undo autmount prevention and remount partition(s) on <device>.

  -f Fsck. Check and repair partitions (HFS+).

  -c Copy <source> to <destination> using ddrescue to build a map of
     unreadable (bad) blocks.

     Metadata including the block map for the copy is placed in a subdir
     named <label> in the current working dir.

     <destination> can be /dev/null, in which case the effect is a "scan"
     for read errors on <source> producing a block map which can be used
     with -p and -Z.

     If existing block map data for <label> is present,
     copying resumes until ddrescue determines the disposition
     of all blocks in target (ddescue "finished").

     Existing block map data is checked to pertain to the specfied
     <source> and <destinatio>.

     Copy implies unmount (-u) <source> and <destination>.
     Mounting (-m) after copy must be performed explicitly.

     The block map file created by -c can be used by -p and -Z.

     By default -c when <destination> is /dev/null (scan) doesn't scrape
     to avoid waiting for additional reads in likely bad areas that aren't
     likely to change afftect files reporting. Enable scan scrape with -X.

  -X ddrescue Scrape during scan.

  -Z Zap blocks blocks listed as error by an existing block map.
     Uses dd to write specific discrete blocks in an attempt
     to make make the drive re-allocate them.

     Map data from an unfinished copy can be used with -Z.

  -p Print report of HFS+ partition's files affected by error regions 
     listed in the ddrescue map for <label>. Affected files can be
     restored from backup or rescued individually using this helper.

  -s Print report of HFS+ partition's files affected by regions of
     slow reads listed in the ddrescue rate log for <label>
     (less than 5 MB/s). Affected files can be set aside to avoid
     further dependency on that drive region.

     For print, <device> must a HFS+ partition (e.g. /dev/rdisk2s2),
     but block map data can wither for the partition or for the
     whole drive (e.g. /dev/rdisk2). If <device> is for a partition,
     but the map is for a whole ddrive, the necessary offset for
     proper location of files will be automatically calculated.

     Map data from an unfinished copy can be used with -p and -s with the
     obvious caveat of missing infomration.

  REQUIRES
  GNU ddrescue:
    (macports | brew install ddrescue -- Linux: apt install gddrescue)
  fsck_hfs (mac builtin)
  fsck.hfs (Linux hfstools)

  SEE GNU ddrescue manual
    https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

  SOURCE
    https://github.com/c-o-pr/ddrescue-helper

USAGE
}

# XXX See README.md

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

get_OS() {
  if which diskutil > /dev/null; then
    echo "macOS"
  else
    echo "Linux"
  fi
}

escalate() {
# XXX not needed
  echo "Escalating privileges..."
  if ! sudo echo -n; then
    echo "sudo failed"
    exit 1
  fi
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
  sudo dd bs=512 count=1 if=/dev/zero of="$target" \
    oseek="$block" oflag=sync,direct conv=notrunc
}

zap_sequence() {
  local target="$1"
  local block="$2"
  local count="$3"
  local res
  local max
  local c

  let max=3
  let c=1
  echo -n "Processing $target, $block, $count "
  while [ "$c" -le "$count" ]; do
    echo -n "$block read "
    let t=$( date +%s )+1
    read_block "$target" "$block" > /dev/null 2>&1
    let res=$?
    let t2=$( date +%s )
#    echo $t $t2
    if [ $res -ne 0 ] || [ $t -le $t2 ]; then
      echo -n "write "
      write_block "$target" "$block"  > /dev/null 2>&1
      let res=$?
      if [ "$res" -ne 0 ] ; then
        echo "FAILED"
        sleep 0.2
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
  echo "done"
}

zap_from_mapfile() {
  local target="$1"
  local map_file="$2"
  local zap_blklist="$3" # side-effect

  echo "$zap_blklist"

  cat "$map_file" | \
    grep -v \# | \
    grep -e - -e / -e \* | \
    ddrescue_map_bytes_to_blocks 512 \
    sort -n | \
    >| "$zap_blklist"

  if [ ! -s "$zap_blklist" ]; then
    echo "Missing or empty bad-block list"
    return 1
  fi
  if grep '[^0-9 ]' "$zap_blklist"; then
    echo "Bad-block list should be a list of numbers"
    return 1
  fi

  cat "$zap_blklist" | while read blk cnt; do
    if [ "$blk" == "" ] || [ "$blk" -eq 0 ] || \
       [ "$cnt" == "" ] || [ "$cnt" -gt 500 ]; then
      echo "Bad block list: address is 0 or count > 500"
      return 1
    fi
    zap_sequence "$device" "$blk" "$cnt"
  done

  return 0
}

zap_from_smart() {
  return 1
}

############################################
# FUNCTIONS SUPPORTING SMART BLOCK REPORTING
############################################

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
  local smart_blklist="$2" # side-effect

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

    create_smartctl_blklist "$drive" "$smart_blklist"

#   zap_from_smart "$drive"

    start_smart_selftest "$drive"

    let fixed_count=$x
  done
}

######################################################
# FUNCTIONS SUPPORTING BLOCK LISTS FOR REPORTS AND ZAP
######################################################

sanity_check_blklist() {
  local blklist="$1"
  local device="$2"

  # XXX NOT YET USED
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
  local blksize="${1:-512}"

  # Convert hex map data for byte addresses and extents
  # into decimal blocks.
  # Input:
  #   Addr   Len
  #   0x800  0x200  extraneous
  # Output:
  #   4      1
  #
  # 0 or 0 are skipped.
  #
  local addr
  local len
  while IFS=" " read addr len x; do

    addr=$(( $addr / blksize ))
    len=$(( $len / blksize ))

    if  (( addr == 0 || len == 0 )); then continue; fi

    # decimal
    echo $addr $len

  done
}

create_ddrescue_error_blklist() {
  local device="$1"
  local map_file="$2"
  local fsck_blklist="$3"
  local blksize="${4:-512}"

  # The map file is a list of byte addresses.

  # Translate a map file into a list of blocks that can be
  # used with fsck -B to list files.

  # Check if map file is a drive-relative or partition relative.
  # If drive relative, compute the partition offset and subtract
  # it from the drive block adddresses, as fsck is partition-relative
  # addresssing.

  local blk
  local cnt
  local partition_offset
  local map_device

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
  
#  echo "$fsck_blklist"

  cat "$map_file" | \
    grep -v \# | \
    grep -e - -e / -e \* | \
    ddrescue_map_bytes_to_blocks | tee "$fsck_blklist.regions" | \
    sort -n | \
    while IFS=" " read blk cnt; do
      let blk=$blk-$partition_offset
      if [ "$blk" == "" ] || [ "$blk" -eq 0 ] || \
         [ "$cnt" == "" ] || [ "$cnt" -eq 0 ]; then break; fi
      for (( i = 0; i < cnt; i++ )); do
        echo $(( blk + i ))
      done
    done >| "$fsck_blklist"
}

create_smartctl_blklist() {
  local device="$1"
  local smart_blklist="$2" # Output file name

  echo "Creating a UNIQUE bad block list from smartcrl event log"
  # Only errors may include repeated blocks, eliminate dups
  sudo smartctl -l selftest "$device" | \
    grep "#" | sed 's/.* //' | grep -v -- "-" | \
    uniq | sort -n > "$smart_blklist"
}

create_slow_blklist() {
  local device="$1"
  local map_file="$2"
  local rate_log="$3"
  local slow_blklist="$4" # Output file name
  local slow_limit="${5:-$5000000}" # Regions slower than this are selected

  # This only makes sense for drives, not for regular files.
  # Create a list of block addresses for rate log entires with eads slower
  # rate_limit in bytes per second
  local partition_offset
  local n
  local addr
  local rate
  local ave_rate
  local bad_areas
  local bad_size
  local interval
  local blk
  local cnt

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

#  echo "$slow_blklist"  
  echo -n "" >| "$slow_blklist"
#  echo "# Slower than $slow_limit bytes per sec" >| "$slow_blklist"
  cat "$rate_log-"* | \
    grep "^ *[0-9]" | \
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
    uniq | \
    ddrescue_map_bytes_to_blocks | tee "$slow_blklist.TMP" | \
    sort -n | \
    while IFS=" " read blk cnt; do
      let blk=$blk-$partition_offset
      if [ "$blk" == "" ] || [ "$blk" -eq 0 ] || \
         [ "$cnt" == "" ] || [ "$cnt" -eq 0 ]; then break; fi
      for (( i = 0; i < cnt; i++ )); do
        echo $(( blk + i ))
      done
    done >> "$slow_blklist"
}

################################
# FUNCTIONS FOR RUNNING ddrescue 
################################

make_ddrescue_helper() {
  # Cteate a temp helper script so ddrescue to be restarted
  # after a read timeout withoout a sudo password request
  # XXX PASS SIGNAL TO SCAN SCRIPT
  local helper_script="${1:-ddrescue.sh}"

  if ! which ddrescue; then
    echo "make_ddrescue_helper: need GNU ddrescue to copy"
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

next_rate_log() {
  local rate_log="$1"
  
  # ddrescue overwrites the rate log for any run that makes progress,
  # so give each run is own log file, named xxx-0...xxx-N
  # If ddrescue is "Finished" no rate log is output from subsequent runs. 

  local last_log
  local c
  # Get name of latest rate log; squelch if none.
  last_log="$(ls -1 -t  ${rate_log}-* | head -1)" 2> /dev/null
  if [ "$last_log" == "" ]; then
    rate_log="$rate_log-0"
  else
    # xxx-0 -> c=0+1 --> xxx-1
    let c=${last_log##*-}; let c++
    echo "$rate_log-$c"
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
  ddrescue $opts  --log-rates="$(next_rate_log $rate_log)" \
    "$source" "$device" "$map_file"
  sleep 1
  if grep -F "Finished" "$map_file"; then finished=true; fi
done
if ! $finished; then
  echo "*** COPY INCOMPLETE: aborted after $max tries"
  exit 1
fi
exit 0
EOF
  chmod 755 "$helper_script"
}

copy() {
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
  echo "copy: running ddrescue in $(pwd)"
  sudo "$helper_script" "$copy_source" "$copy_dest" "$map_file" \
       "$event_log" "$rate_log" \
       "$trim" "$scrape"
  return $?
}


########################
# DEVICE LOGIC FUNCTIONS
########################

resource_exists() {
  [ -f "$1" ] || [ -b "$1" ] || [ -c "$1" ]
}

resource_matches_map() {
  local device="$1"
  local map_file="$2"

  if [ -s "$map_file" ]; then
    if grep -q "# Mapfile. Created by GNU ddrescue" "$map_file"; then
       grep -q " $device " "$map_file"
    else
      return 1
    fi
  else
#    echo "resource_matches_map: no map file: $map_file" > /dev/stderr
    return 1
  fi
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

  # device is specifies /dev so make sure it exists
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
    echo "get_device_from_ddrescue_map: map device = \"\"" > /dev/stderr
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
      echo "INCLUDE ESP: $include_efi" 1>&2
#      echo "list_partitions: $device" 1>&2

      # Parse out container disks (physical stores) and
      # Follow containers to the synthesized drive.
      # (not-container v. container)

      if [ "$device" == "$(strip_partition_id "$device")" ]; then
        echo "$device is a whole drive" 1>&2
      else
        echo "$device is a partition" 1>&2
      fi

# Determine if partition contains or is contained
# "Container diskxx" -> Contains
# "Physical Store" -> Contained
# Multiple containers are allowed.
# Containers cannot be nested.

      # Find devices partitions, containers, and contained volmumes 
      local p
      local c
      local v
      # EFI service partition never auto-mounted by OS default
      # grep -v means DO NOT MATCH
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

      c=( $(diskutil list "$device" | \
        grep "Container disk" | \
        sed -E 's/^.+Container (disk[0-9]+).+$/\1/') )

#      echo "list_partitions: p=${p[@]}" 1>&2
#      echo "list_partitions: c=${c[@]}" 1>&2

      # For all containers, process their content volumes
      v=""      
      if [ "$c" != "" ]; then
        for x in ${c[@]}; do
          # Contained volumes begin at continaer's partition index 1
          v=( ${v[@]} $(diskutil list "$x" | \
                  grep '^ *[1-9][0-9]*:' | \
                  sed -E 's/^.+(disk[0-9]+s[0-9]+)$/\1/') )
        done
#        echo "list_partitions: v=${v[@]}" 1>&2
      fi

      if [ "$p" == "" -a "$v" == "" ]; then
        echo "list_partitions: device has no eligible partitions" 1>&2
      else
        echo ${p[@]} ${v[@]}
      fi

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

#######################
# MOUNT, UNMOUNT & FSCK
#######################

unmount_device() {
  local device="$1"
  local partitions
  local volume_uuid
  local volume_name
  local fs_type
  local result

  # Unmount and disable auto-remoount of device
  # If device is drive, do so for all its partitions

  let result=0
  case $(get_OS) in
    macOS)
      # Single partition vs a drive with possible multiple parts
      # device will be a /dev spec, but diskutil list doesn't include "/dev/"
      local p
      local r
      partitions=( $(list_partitions "$device") )
#      echo unmount_device 1: "$device" "$(strip_partition_id "$device")"
      echo "unmount_device: unmouonting ${partitions[@]}"
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
#        echo -n "$part "
        volume_uuid="$(get_volume_uuid $part)"
        volume_name="$(get_volume_name $part)"
        fs_type=$(get_fs_type "$part")
        if ! grep -q "^UUID=$volume_uuid" /etc/fstab; then
          echo "unmount_device: adding $volume_uuid $volume_name to /etc/fstab"
          # Juju with vifs to edit /etc/fstab
          # G (got to end)
          # A (append at end of line)
          # :wq (write & quit
          EDITOR=vi
          let r=0
          # fstab entires must list the correct volume type or
          # they won't be honored by the system.
          #
          # THERE'S A NEEDED <ESC> CHARACTER EMBEDDED BEFORE :wq
          sudo vifs <<EOF1 > /dev/null 2>&1
GA
UUID=$volume_uuid none $fs_type rw,noauto # $volume_name $part:wq
EOF1
          let r+=$?
          if [ $r -ne 0 ]; then echo "unmount_device: *** vifs failed"; fi
          let result+=$r
        fi
        if is_mounted "$part"; then
          sudo diskutil umount "$part"
          let result+=$?
        else
          echo "unmount_device: $part is not mounted"
        fi
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
  local partitions
  local volume_uuid
  local volume_name
  local result

  let result=0
  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  case $(get_OS) in
    macOS)
      local p
      local r
#      echo "$device" "$(strip_partition_id "$device")"
      partitions=( $(list_partitions "$device") )
#      echo ${partitions[@]}
      echo "mount_device: mouonting ${partitions[@]}"
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
#        echo -n "$part "
        volume_uuid="$(get_volume_uuid $part)"
        volume_name="$(get_volume_name $part)"
        if grep -q "^UUID=$volume_uuid" /etc/fstab; then
          # Juju with vifs to edit /etc/fstab
          # /<pattern> (go to line with pattern)
          # dd (delete line)
          # :wq (write & quit
          echo "mount_device: removing $volume_uuid $volume_name from /etc/fstab"
          EDITOR=vi
          let r=0
          sudo vifs <<EOF2 > /dev/null 2>&1
/^UUID=$volume_uuid
dd:wq
EOF2
          let r+=$?
          if [ $r -ne 0 ]; then echo "mount_device: *** vifs failed"; fi
          let result+=$r
        fi
        if ! is_mounted "$part"; then
          sudo diskutil mount "$part"
          let result+=$?
        fi
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
  local blklist="$3"

  # Enable automount and remount device
  # If device is drive, do so for all its partitions
  local partitions
  local volume_uuid
  local result
  local nr_checked
  local fs_type
  let result=0

  if $find_files && [ "$blklist" == "" -o ! -f "$blklist" ]; then 
    echo "fsck_device; missing block list for find files"
    return 1
  fi

  case $(get_OS) in
    macOS)
      partitions=( $(list_partitions "$device" true) )
#      echo "$device" "$(strip_partition_id "$device")"
#      echo ${partitions[@]}
      let nr_checked=0
      local p
      for (( p=0; p<${#partitions[@]}; p++ )); do
        local part=/dev/"${partitions[$p]}"
#        echo -n "$part "
        fs_type=$(get_fs_type "$part")
        echo $fs_type
        case $fs_type in
          hfs)
            if ! $find_files; then
              sudo fsck_hfs -f -y "$part"
            else
              # On macOS -l "lock" must be used when mouonted write
#              cat $blklist
              sudo fsck_hfs -n -l -B "$blklist" "$device"
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
Do_Summarize_Zap_Regions=false
Do_Zap_Blocks=false
#
Opt_Trim=true
Opt_Scrape=false

while getopts ":cfhmpsuzXZ" Opt; do
  case ${Opt} in
    c)
      # Copy and build block map
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
      Do_Summarize_Zap_Regions=true
      ;;
    Z)
      # Overwite blocks in the device one at a time using an existing map
      Do_Zap_Blocks=true
      ;;
    *)
      usage
      echo "$(basename "$0"): Unknown option $1"
      exit 1
      ;;
  esac
done
# Move remaining args into postion at $1...
shift $((OPTIND - 1))

if ! $Do_Mount && ! $Do_Unmount && ! $Do_Fsck && \
   ! $Do_Copy && ! $Do_Smart_Scan && \
   ! $Do_Error_Files_Report && ! $Do_Slow_Files_Report && \
   ! $Do_Summarize_Zap_Regions && ! $Do_Zap_Blocks && \
   true; then
  echo "Nothing to do (-h for usage)"
  exit 0
fi

# USAGE 1

if $Do_Mount || $Do_Unmount || $Do_Fsck; then

  if \
     $Do_Copy || $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Summarize_Zap_Regions || $Do_Zap_Blocks || \
     false; then
    echo "Incompatible options (1)"
    exit 1
  fi

  if [ $# -ne 1 ]; then
    echo "Missing or extra parameter (1)"
    exit 0
  fi

  Device="$1"

  if ! is_device "$Device" false; then
    echo "No such device $Device"
    exit 1
  fi

  if $Do_Unmount; then
    if $Do_Mount; then
      echo "Incompatible options (1c)"
      exit 1
    fi
    echo "Umount and disable automount..."
    if ! unmount_device "$Device"; then
      echo "*** Unmount(s) failed"
      exit 1
    fi
  fi

  if $Do_Mount; then
    if $Do_Unmount || $Do_Fsck; then
      echo "Incompatible options (1-b)"
      exit 1
    fi
    echo "Enable automount and mount partition(s)..."
    if ! mount_device "$Device"; then
      echo "*** Mount(s) failed"
      exit 1
    fi
  fi

  if $Do_Fsck; then
    if $Do_Mount; then
      echo "Incompatible options (1-d)"
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
     $Do_Summarize_Zap_Regions || $Do_Zap_Blocks || \
     false; then
    echo "Incompatible options (2)"
    exit 1
  fi
  
  if [ $# -ne 1 ]; then
    echo "Missing or extra parameters (2)"
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
  echo "Deprecated, doesn't work"
  # Verify device is a drive not a partition
#    smart_scan_drive "$device" "$smart_blklist"

  exit 1
fi

if $Do_Copy; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck \
     $Do_Smart_Scan || \
     $Do_Error_Files_Report || $Do_Slow_Files_Report || \
     $Do_Summarize_Zap_Regions || $Do_Zap_Blocks || \
     false; then
    echo "Incompatible options (2)"
    exit 1
  fi

  if [ $# -ne 3 ]; then
    echo "Missing or extra parameters (2)"
    exit 1
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    echo "Command line args reversed?"
    exit 1
  fi

  # GLOBALS
  Label="$1" # Name for metadata folder including the ddresxcue map.
  Copy_Source="$2"
  Copy_Dest="$3"

  # File names used to hold the ddrewscue map file and block lists for
  # print and zap.
  Map_File="$Label.map"
  Error_Fsck_Blklist="$Label.fsck-blklist"
  Zap_Blklist="$Label.zap-blklist"
  Smart_Blklist="$Label.smart-blklist"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log"
  Files_Log="$Label.files-log"
  continuing=false

  if [ "$Copy_Source" == "$Copy_Dest" ]; then
    echo "<source> and <destination> must differ"
    exit 1
  fi
  # Check existing mapfile to see if it lists <sourcce> and <destination>.
  #

  if ! mkdir -p "$Label"; then
    echo "Can't create a data dir for \"$Label\""
    exit 1
  fi
  if ! cd "$Label"; then echo "Setup error (cd $Label)"; exit 1; fi

  # XXX Can't distingush between source and dest
  if [ -s "$Map_File" ]; then
    if ! resource_matches_map "$Copy_Source" "$Map_File"; then
      echo "Found exisiting block map ($Label) but not for this source"
      exit 1
    fi
    if ! resource_matches_map "$Copy_Dest" "$Map_File"; then
      echo "Found exisiting block map ($Label) but not for this destination"
      exit 1
    fi
  fi

  # Don't accept the startup drive
  # Prints device details if not a plain file
  if is_device "$Copy_Source" false; then
    if device_is_boot_drive "$Copy_Source"; then
      echo "Boot drive can't be used."
      exit 1
    fi
  else
    if [ "$?" == "2" ]; then
      echo "$Copy_Source: device not found"
      exit 1
    fi
    if ! resource_exists "$Copy_Source"; then
      echo "No such file $Copy_Source"
      exit 1
    fi
    echo "Copy source is a file: $Copy_Source"
  fi

  if is_device "$Copy_Dest" false; then
    if device_is_boot_drive "$Copy_Dest"; then
      echo "Boot drive can't be used."
      exit 1
    fi
    # Continue
  else
    # Is file
    if [ "$?" == "2" ]; then
      echo "$Copy_Dest: device not found"
      exit 1
    fi
    if [ "$Copy_Dest" == "/dev/null" ]; then
      echo "Copy destination is /dev/null (scanning)"
    else
      Opt_Scrape=true
      if resource_matches_map "$Copy_Dest" "$Map_File"; then
        if [ -s "$Copy_Dest" ]; then
          continuing=true;
        else
          echo -n "Exisiting ddrescue map ($Label) "
          echo "but missing it's destination file $Copy_Dest"
          exit 1          
        fi
        # Contimue
      fi
      echo "Copy destination is a file: $Copy_Dest"
    fi
  fi

  if is_device "$Copy_Source"; then
    if ! unmount_device "$Copy_Source"; then
      echo "Unmount failed $Copy_Source"
      exit 1
    fi
  fi
  if is_device "$Copy_Dest"; then
    if ! unmount_device "$Copy_Dest"; then
      echo "Unmount failed $Copy_Dest"
      exit 1
    fi
  fi

  if $continuing; then
    echo "RESUMING COPY"
  elif is_device "$Copy_Dest" false || \
       [[ ! "$Copy_Dest" =~ ^/dev/null$ && -s "$Copy_Dest" ]]; then
    echo '*** WARNING DESTRUCTIVE ***'
    read -r -p "OVERWTIE ${Copy_Dest}? [y/N] " response
    if [[ ! $response =~ ^[Yy]$ ]]; then
       echo "...Stopping"
       exit 1
    fi
  fi

  if ! copy "$Copy_Source" "$Copy_Dest" "$Map_File" \
            "$Event_Log" "$Rate_Log" "$Opt_Trim" "$Opt_Scrape"; then
    exit 1
  fi

fi

# USAGE 3

if $Do_Error_Files_Report || $Do_Slow_Files_Report || \
   $Do_Zap_Blocks || $Do_Summarize_Zap_Regions; then

  if \
     $Do_Mount || $Do_Unmount || $Do_Fsck || \
     $Do_Copy || $Do_Smart_Scan || \
     false; then
    echo "Incompatible options (3)"
    exit 1
  fi

  # Need a label and metadata
  if [ $# -ne 2 ]; then
    echo "Missing or extra parameters (3)"
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
  Error_Fsck_Blklist="$Label.error-blklist"
  Slow_Fsck_Blklist="$Label.slow-blklist"
  Zap_Blklist="$Label.zap-blklist"
  Smart_Blklist="$Label.smart-blklist"
  Slow_Blklist="$Label.slow-blklist"
  Event_Log="$Label.event-log"
  Rate_Log="$Label.rate-log" # Incremeted if exists
  Error_Files_Report="$Label.error-files-report"
  Slow_Files_Report="$Label.slow-files-report"

  if ! cd "$Label" > /dev/null 2>&1; then
    echo "No metadata found ($Label)"; exit 1;
  fi

  if [[ "$Label" =~ ^/dev ]]; then
    echo "Command line args reversed?"
    exit 1
  fi

  # Prints device details if not a plain file
  if ! is_device "$Device" false; then
    echo "Files reports require a partition device, not a regular file"
    exit 1
  fi

  # Don't accept the startup drive or regaulr files
  if device_is_boot_drive "$Device"; then
    echo "Boot drive can't be used."
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
          echo "Found exisiting block map ($Label) but it's not for this device"
          exit 1
        fi
      else
        echo "Found exisiting block map ($Label) but it's not for this device"
        exit 1
      fi
    fi
  fi

  if $Do_Error_Files_Report || $Do_Slow_Files_Report; then

    if [ ! -s "$Map_File" ]; then
      echo "No ddrescue block map ($Label). Create with -c"
      exit 1
    fi
    if ! is_hfsplus "$Device"; then
      echo "<device> must be an hfsplus partition"
      exit 1
    fi
    if ! resource_matches_map "$Device" "$Map_File" &&
       ! resource_matches_map "$(strip_partition_id "$Device")" "$Map_File";
       then
      echo -n "Found exisiting block map ($Label) "
      echo "but it's not for this device $Device"
      exit 1
    fi

    if $Do_Error_Files_Report; then
      create_ddrescue_error_blklist "$Device" "$Map_File" "$Error_Fsck_Blklist"
#      cat "$Error_Fsck_Blklist"

      fsck_device "$Device" true "$Error_Fsck_Blklist" | \
        tee "$Error_Files_Report"
      echo "Affected files report saved in $Label/$Error_Files_Report"
    elif $Do_Slow_Files_Report; then
      #
      # For an eligible device, report the device name and its 
      # files containing slow areas.
      # XXX
      # For other deivces and regular files, report the source file name the
      # log sorted by rate.
      #
      create_slow_blklist "$Device" "$Map_File" "$Rate_Log" "$Slow_Fsck_Blklist"
#      cat "$Slow_Fsck_Blklist"

      fsck_device "$Device" true "$Slow_Fsck_Blklist" | \
        tee "$Slow_Files_Report"
      echo "Affected files report saved in $Label/$Slow_Files_Report"
    else
      echo "MAINLINE: SHOULD NOT HAPPEN"
    fi

    # Report on stdout and saved in report file
    exit
  fi

  if $Do_Zap_Blocks; then
    if [ ! -s "$Map_File" ]; then
      echo "No block map ($Label). Create with -c"
      exit 1
    fi
    if ! resource_matches_map "$Device" "$Map_File" &&
       ! resource_matches_map "$(strip_partition_id "$Device")" "$Map_File";
       then
      echo -n "Found exisiting block map ($Label) "
      echo "but it's not for this device $Device"
      exit 1
    fi
    echo "Umount and prevent automount..."
    if ! unmount_device "$Device"; then
      echo "Unmount failed"
      exit 1
    fi

    if zap_from_mapfile "$Device" "$Map_File" "$Zap_Blklist"; then
      fsck_device "$Device"
    fi

  fi

fi

cleanup