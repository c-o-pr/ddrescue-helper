# DDRESCUE-HELPER

`ddrescue-helper.sh` is a bash script for running GNU `ddrescue` on macOS and Linux.

`ddrescue-helper.sh` makes using GNU `ddescue` easier:
- It hides details of the GNU `ddrescue` command,
- ensures that source and destination volumes are unmounted during COPY, and
- performs simple consistency checks.

The script is controlled by command line options offering the following functionality:

`-u -m -f` UNMOUNT, MOUNT, and FSCK volumes on a partition or whole-drive basis. Unmount is persistent based on `/etc/fstab` entry for the volume UUID. This prevents disturbance of volume structures while recovery is in progress

`-c` COPY (or SCAN) a drive, partition, or single file using GNU `ddescue`. This creates a domain map and read-rate log (metadata) which are stored in directory named by a user-supplied LABEL. 

Unmount is performed automatically upon copy. Mount and fsck must be performed explicitly.

`-p -s` REPORT files affected by read-errors and slow-reads using GNU `ddescue` domain map metadata and helper tools for supported filesystems.

On macOS REPORT works with HFS+.\
On Linux REPORT works with NTFS, ext2/3/4, and HFS+.

`-Z` ZAP device blocks associated with read-errors to try to make those blocks readable. This offers the potential to regain access to a filesystem that is otherwise unmountable, or access an affected file in situ.

Options allow preview of the block addresses to be ZAPPED, and 4K blocks rather than the default 512-byte blocks for use with Advanced Format Drives.

`-q` PLOT a simple graph of read-rates over time.

## ABOUT GNU DDRESCUE

GNU `ddescue` is a utility for copying drives, partitions, or files in a way that gracefully handles media read-errors, allowing as much data as possible to be recovered from the source. It's restartable and continues with previous progress until all device blocks are accounted for.

A side effect of running GNU `ddescue` is the creation of two kinds of metadata for the copy source:
1. A domain map of device extents with read-errors.
2. A read-rate log of read performance measured second-by-second.

`ddrescue-helper.sh` takes advantage of this metadata for its features.

# DDRESCUE COMMAND DETAILED DESCRIPTION

There are THREE MODES of `ddrescue-helper.sh` operation:

### 1. UNMOUNT, MOUNT, and FSCK a drive or partition.

`ddrescue_helper.sh -u | -m | -f <device>`

`-u` prevents auto-mount after unmount.

`-m` re-enables auto-mount after mount and remounts.

`-f` looks up the volume type of device and runs the appropriate form of `fsck`. This may be appropriate to check / repair volume integrity after making a copy or zapping.

`-u, -m` include updating `/etc/fstab` (using `vifs(8)` on macOS). On Linux fstab changes are observed by `udev` and may cause automatic mount / umount events.

> [!NOTE]
> With `-m`, you can supply a volume UUID as `<device>`to remove an entry from `/etc/fstab` (no attempt to mount is made). Or, you can edit `/etc/fstab` by hand (on macOS use `vifs(8)`.)
>
> If `<device>` is a partition, only it is affected. If `<device>` is a drive, all partitions are affected. Only partitions with volume UUIDs can be persistently unmounted using this script, but this is the common case.
>
> UNMOUNT ignores the GPT EFI Service Partition as it is not mounted by default.
>
> If you need a general purpose mount inhibitor for macOS which works for all devices, including disk images, see [Disk Arbitrator](https://github.com/aburgh/Disk-Arbitrator/).
> Note: Disk Arbitrator hasn't been updated since 2017. On macOS Ventura it works to properly inhibit auto-mounts, but a UI bug prevents its Quit from working, so you have to kill it by hand.
>
> On macOS, containers are observed.

### 2. COPY / SCAN

Runs `ddrescue` to scan a device or recover data, generating a domain map of read-errors and a rate-log which records device regions that experienced read slowdown. The domain map and rate-log are stored in a folder named with <label>.

`ddrescue_helper.sh -c [-X] <label> <source> /dev/null`

- SCAN a drive, partition or file to create the domain map and rate-log. SCAN builds the domain map and rate-log without saving device data, so you can run REPORT, PLOT, and ZAP.

`-X`: Enable GNU `ddescue` scraping during SCAN, scraping is disabled by default to save some time getting block list for use with REPORTS. For COPY, scraping is enabled by default to recover as much data as possible.

`ddrescue_helper.sh -c [-M] <label> <deivce> <device>`

- COPY a drive or partition to another device.

`ddrescue_helper.sh -c [-M] <label> <deivce> <file>`

- COPY drive or partition to a file (image).

`ddrescue_helper.sh -c [-M] <label> <file> <file>`

- COPY a file to another file.

COPY is destructive to data on `<destination>`.

`-M` is passed to GNU `ddescue` as the "re-trim" option. This marks all failed blocks as untrimmed, causing them to be retried.

> [!NOTE]
> COPY/SCAN be stopped with ^C, then resumed by re-running the helper command.
>
> About "scraping": By default. GNU `ddescue` uses large reads to speed copy progress. When it gets a read-error it marks a large area as an error and continues to to copy further data as fast as possible. A subsequent read pass "trims" the large read area from its leading and trailing edges down to the an extent bounded by unreadable blocks. In a third "scrape" pass, each block in the trimmed extent is read to collect as much data as possible. If there are localized series of bad blocks, which is the typical case, scraping during SCAN can be time consuming and maybe not worth the time because affected files can be large relative to the trimmed extent (REPORT) and ZAP will read test each block in any extent. See the GNU `ddescue` manual.

### 3 REPORT affected files, PLOT performance and ZAP blocks

These operations utilize the GNU `ddescue` domain-map metadata produced by COPY / SCAN.

`ddrescue_helper.sh -p | -s <label> <device>`

`-p` REPORT files affected by read-errors.

`-s` REPORT files affected by slow reads, less than 1 MB/s.

`ddrescue_helper.sh -q <label>`

`-q` PLOT a graph of read performance.

REPORT works for macOS HFS+, and for Linux ext2/3/4. NTFS, and HFS+ (you may need to install support packages; see DEPENDENCIES).

> [!TIP]
> REPORT is partition (volume) oriented. If you have GNU `ddescue` metadata for a whole drive, you can use it. A partition offset will be automatically calculated.
>
> PLOT `-q` can give you a sense of the overall health of a drive. If it has large slow regions, that may be a sign of impending head failure. PLOT outputs to a dumb terminal using Gnuplot, so no reader is needed to view a plot.

`ddrescue_helper.sh -z | -Z [ -K ] <label> <target>`

`<target>` is a device or file associated with metadata saved in `<label>`.

`-z` ZAP PREVIEW. Print a list of blocks that will be affected -Z but don't ZAP. If the list is large (thousands) it's likely not productive to attempt zapping.

`-Z` ZAP blocks listed as bad in the domain map in an attempt to make them readable. ZAP first performs a block read, and if the read reports failure it then performs a block write. The risk to existing data is low because the ZAPPED block is unreadable to begin with.

`-K` ZAP using 4096-byte blocks instead of 512-byte blocks. For use with 4K Advanced Format drives. The `smartmontools` package provides detailed information on drive capabilities.

ZAP can allow recovery of access to areas with bad blocks, and may enable access to a volume that can't be accessed due to a read-error in a critical data structure.

> [!NOTE]
> ZAP is for trying to make a drive with errors readable so that it can be used in situ by other tools. If your goal is to recover data, use COPY.
>
> ZAP `-z` can be used on file source as well as a drive or partition.
>
> When ZAPPING a 4K Advanced Format drive, use -K to work with 4096 byte blocks. This may be more effective at overcoming read-errors.
>
> When COPYING or ZAPPING, read-errors cannot be repaired, but a small error region may be tolerable as compared to alternative of losing access to the whole file (e.g., a small content loss in a media file may be acceptable.)
>

# COMMAND EXAMPLES
```
######
# If working with a drive or partition,
# discover /devs using "diskutil list" (macOS) or "lsblk" (Linux).
# If working with a files, use file names.
######

# Display help
ddrescue-helper.sh -h

# COPY /dev/src to /dev/dst, creating metadata saved in a dir named ./X
ddrescue-helper.sh -c X /dev/src /dev/dst

# COPY source to a file (image)
ddrescue-helper.sh -c X /dev/src src.img

# COPY file to file
ddrescue-helper.sh -c X file1 /dev/null

# It's wise to place file2 on another device.
ddrescue-helper.sh -c X file1 /Volumes/XYZ/file2

# SCAN /dev/src, only creating metadata
ddrescue-helper.sh -c X /dev/src /dev/null

# Review ddrescue output for the SCAN or COPY.
# The file X/X.map is ddrescue's block list. It is human readable.
more X/X.map

# REPORT which files are affected by read-errors on partition id=2...
# On macOS, filesystem must be HFS+
# On Linux, filesystem can be ext2/3/4. NTFS, and HFS+
# If the metadata in X is for the entire drive (e.g., /dev/src),
# the block offsets for the partition are automatically calculated.
ddrescue-helper.sh -p X /dev/src2

# REPORT which files are affected by slow reads, less that 1 MB/s.
# 1 MB/s is an arbitrary rate hard-coded into the script. This should be
# an option.
ddrescue-helper.sh -s X /dev/src2

# PLOT read-rate over time for the SCAN or COPY of source. No access to
# the /dev/src is needed, the existing rate-log is used for the plot.
ddrescue-helper.sh -q X

# Preview a list of read-error blocks that can be ZAPPED
# (blocks are 512 bytes)
ddrescue-helper.sh -z X /dev/src

ZAP read-error blocks 
ddrescue-helper.sh -Z X /dev/src

# ZAP 4096 byte blocks for Advanced Format drive (-K)
ddrescue-helper.sh -Z -K X /dev/src

# FSCK a /dev after a COPY or ZAP
ddrescue-helper.sh -f /dev/target

# Remove prohibition on mount of /dev/src and re-mount.
# WARNING: If a COPY was made and the destination device is still connected,
# it's volume UUIDs will be the same as sources and it may become auto-mounted
# when prohibition is lifted.
ddrescue-helper.sh -m /dev/src

# Remove orphaned volume reference from /etc/fstab
ddrescue-helper.sh -m <UUID>

# Or edit /etc/fstab by hand (e.g., vifs)
```

## DEPENDENCIES

### macOS Dependencies

Homebrew or Macports: `ddrescue` `gnuplot`

- macOS FSCK natively supports: HFS+, MSDOS, ExFAT and APPS.

### Linux Dependencies

- Standard repos: `gddrescue`, `dosfstools`, `exfatprogs`, `hfsutils`, `ntfsprogs`, and `gnuplot`.

Key Linux system dependencies are `udev` and `systemd` to handle device mounts. These subsystems have been common on Linux for 10+ years.

## NOTES & WARNINGS

> [!IMPORTANT]
> The script was developed using old bash v3.2 to make it compatible with macOS. It should work with all newer bash.
>
> It's been tested on Mac OS 10.14 Mojave on macOS Ventura, Ubuntu 23.10 and Mint 21.2.

> [!CAUTION]
> This script helps you, it does not think for you. Consider every action you take with this helper.
>
> Working with a /dev implies access to critical format data structures.
>
> COPYING a /dev to another /dev wipes the destination.
>
> Copying /dev to /dev when device sizes don't match is inherently tricky. Device layout has important implications om further recovery and use. This topic is beyond the scope of this documentation. Thoroughly consider what you are doing at a systems level.
>
> ZAP only operates on blocks marked as unreadable by GNU `ddescue` domain map, and it read-tests blocks before attempting to overwrite, so it's safe. But a ZAP of /dev can set in motion other failure modes. Be ready to deal with the consequences.
>
> ZAP of a file only affects the data for that file, so this is relatively safe.
>
> This script has been coded with care, but unexpected behaviors are possible. Shell scripts are pesky because they rely heavily on text substitution.
>
> __USE AT YOUR OWN RISK__

## IS CONTINUING TO USE A DRIVE WITH MEDIA ERRORS SANE?

My experience is that commodities spinning hard drives (especially large cheap drives) have unreliable areas that only get exposed when the drive is used very close to full for a long time. I will make a wild guess that the drive makers solve a binning problem by tolerating a spread of defects in shipped product and deferring the exposure of these defects for as long as possible. The gambit is that customers won't become aware of the problem areas until the drive is well out of warranty and so old that accountability for failure is irrelevant. The implication of this wild assessment is that a well-used drive can be expected to suffer from some errors when heavily used, but still has life it in if you can find a way to deal with the problem areas. For example, one way to work around bad spots is to set-aside files that cover them. Another is to ZAP.

By running a scan over an entire drive, such defects can be side-stepped by setting aside affected files or ZAPPING block make the area readable. This may allow continued use of a drive with minor errors.

The wise have backups and simply replace a problem drive.

The frugal or bereft may want to work with janky devices at hand.

Making a terrible mistake is possible, but the skilled may be rewarded.

# BACKGROUND ON DEVELOPMENT

The idea for this helper came about from dealing with read-errors occurring during local backups of spinning drives. As mentioned above, I have found that as spinning drives fill and age, they become prone to small bad regions.

I keep backups, and I prefer to replace a drive with any errors. But for reasons stinginess, I wanted to keep using some drive affected by small number of bad blocks for as long as possible. One way I found to do this is to set aside files with read errors so the bad region doesn't get re-used and recover the affected file from a backup.

Eventually I ran into a case where filesystem metadata was affected and a drive
became unmountable. To recover from this, I started by looking at SMART
self-test logs to report bad blocks. SMART self-tests can run in the
background while the drive is in use and the log can be queried on a live drive.
This seemed promising, but due to vendor inconsistencies with SMART, and that
many of my data drives are attached by USB, which prevents access to SMART
capabilities, I couldn't figure out how to build a helper based on SMART.

[As an interesting aside, I discovered that when a USB drive is passed through to an Ubuntu VM via Parallels virtual machine, `smartctl(8)` works as if the drive were locally attached by SATA, so I wonder what keeps SMART from working with native USB drives?]

Linux has `badblocks(8)` to scan for bad blocks. `badblocks` has nice integration with ext2/3/4 filesystem, where bad-block list can be ingested by `fsck` to prevent those blocks from being allocated by the filesystem. Linux also has `hdparm(8)`, which can write single blocks to try to force them to become readable.

But my primary system is a hackintosh and my data is on Apple HFS+. `badblocks`
and `hdparm` are not available on macOS, even via 3rd-party ports.

Another option is `dd(1)`. This old-school utility is available on every Unix variant and can write single blocks. Using it I found I could write a disk block with a read error and read it back (this is not just a matter of caching, although from a certain point of view it may not matter). This allowed me to regain access to an unmountable drive and recover needed contents without making a full drive copy.

Entrée GNU `ddrescue`. This is an indispensable tool for recovering data from failing drives. As it works, it creates a domain map of unreadable extents pared down to specific bad blocks. Compared to SMART, it's far simpler and more consistent to use, it's drive hardware agnostic, and you can control scope from recovery of a whole drive, a partition, or a file, then parse the domain map into a bad block list for use with `dd`. This gave rise to ZAP capability.

When making a partition or full drive copy, it's very important that the source and destination filesystem metadata remains in a consistent state until the copy is complete. Not only must the devices be unmounted, but copying may be interrupted by a timeout, spontaneous drive disconnection, a system crash, or you way want to intentionally stop a copy. This necessitates a prohibition on auto-mount so that copying may be resumed. Before re-mounting a volume, it's wise to check it for consistency. This gave rise to UNMOUNT, MOUNT and FSCK.

While working with a problem HFS+ drive, I came across the -B option for `fsck.hfs(8)`, which accepts a list of block addresses and reports which files the blocks belong to. It turns out that tools exist to do this for NTFS and ext2/3/4. GNU `ddescue` can also generate a rate-log, which, similar to the domain map, can be converted into a block list and fed to filesystem tools to find files affected by drive regions with slow reads. This gave rise to the REPORT capability.

PLOT is merely a parsing of the GNU `ddescue` rate-log into a bar-graph formatted for a dumb terminal using gnuplot.

I hacked all these ideas together to make `ddrescue_helper.sh`.

# TODOs

A growing list of fixes and improvements are under consideration.

## TODOS FOR USABILITY

**General**

- [ ] XXX Review Linux systemd/udev dependencies for mount/umount.
- [ ] ADD Option to purge caches before COPY source file to file (purge auto before COPY file to /dev/null).
- [ ] ADD report of irrelevant command-line options.
- [ ] ADD Mount device to chosen dir.
- [ ] ADD auto-detection and installation of supporting tools on Linux.
- [ ] ADD selectable rate limit for -P.
- [ ] ADD Output a uniquely-named summary of unreadable blocks in output of -Z, inc failed retry.
- [ ] ADD Save the ddrescue work summaries for each run so that progress can be examined.
- [ ] ADD Input a list of files to copy (source) and a tree of metadata.
- [ ] ADD pass additional options to ddrescue.
- [ ] ADD Option to ZAP even if READ test succeeds.
- [x] XXX Test zap of a file (works).
- [x] ADD 4K block size option to ddrescue for 4K Advanced Format Drives.
- [x] ADD System detection of ddrescue version or options: ADDED check for direct I/O capability but not a comprehensive version review.
- [x] ADD ZAP slow reads.
- [x] XXX Normalize get_fs_type.
- [x] XXX The warning for ZAP overlapping format data structures needs to be device format aware-- drive versus volume.
- [x] ADD Improve situational awareness of the EFI service partition re MBR
- [x] ADD fsck whole drive format vs. volumes.
- [x] ADD -p -z -Z checks for unmanageably large numbers of problem blocks in the map.
- [x] ADD zap preview and confirmation.
- [x] ADD -z print a summary of LBA extents affected by read-errors This is a sanity check for -Z. Large areas of errors indicates a failed drive and zapping is impractical.
- [x] ADD prettify the output of -Z and save it in a log.
- [x] XXX Fix src/dst relative file path naming to be per CWD not the label folder.
- [x] ADD Sanity checks for src/dst aliases and symlinks.
- [x] ADD Check for source file is newer than dest file.
- [x] ADD Check for <file> to <file> if destination is directory.
- [x] XXX identical source / dest check needs to consider different paths to same resource.
- [x] XXX -s Slow reads extent spread for coverage vs block quantity.
- [x] XXX -p -s Adjust partition offset based on device specified.
- [x] ADD rate-log reporting for slow areas and related files.
- [x] ADD check for map match to source / desk.

**Drive Format**

- [ ] ADD option to save and restore of partition table via file saved with metadata.
- [ ] ADD HFS+ Alternate Volume Header recovery.
- [ ] ADD Partition superblock recovery.
- [x] ADD MBR vs GPT awareness?

***Mac & Filesystem Support***

- [ ] XXX Investigate limits of APFS partition cloning.
- [ ] ADD Force use of /dev/rdisk on macOS for speed.
- [ ] ADD help for changing volume LABELs and partition/volume UUIDs
/System/Library/Filesystems/TYPE.fs/Contents/Resources/TYPE.util -s rdisk21s10
No "/dev", -s to set new random UUID.
- [x] ADD APFS fsck.
- [x] ADD FAT, exFAT fsck.

**Linux Mainline**

- [x] ADD Linux zap (via hdparm).
- [x] ADD -m -u -c -p -s -z on Linux.

**Linux FAT, ExFAT**

- [x] ADD FAT, ExFAT file lookup and fsck (optional dostools).

**Linux NTFS**

- [ ] ADD option to copy using ntfsclone.
- [ ] ADD Linux ddrutility support to full partition / drive copy for NTFS.
- [x] ADD NTFS fsck (ntfsprogs: ntfsfix).
- [x] ADD NTFS reports (ntfsprogs: ntfscluster).

**Linux EXT2/3/4**

- [ ] ADD Option to pass error blocklist to fsck -l (set aside blocks).
- [x] ADD ext2,3,4 file lookup and fsck.
- [x] ADD ext2,3,4 reports.

## TODOS DOCUMENTATION

- [ ] ADD Explain Linux vs macOS differences in ZAP, and implications of 
read vs write failure. macOS appears to read / write some other area of the drive besides the requested blocks. Linux seems to work as expected. 
- [ ] ADD Explain about ZAP extend and macOS likely requesting greater than 1 block for dd single block input.
- [ ] ADD Explanations about how to read the map, the support metadata, and the thinking about blocklists, extents, and blocksize considerations.
- [ ] ADD Explanations about modern vs older versions of Linux.
- [ ] ADD Explanation about APFS and bootdrive exclusions.
- [ ] ADD help with removal of stale fstab entires for the destination after copy is complete.
- [ ] ADD Explain GPT vs other partitioning implications.
- [ ] XXX Explain unmount on macOS & Linux, incl volume UUIDs, read-only,
interactions with systemd, etc.
- [ ] XXX Assistance for thinking about corrupted volumes.
- [ ] ADD Explain volume UUID edge-cases.
- [ ] XXX After cloning a drive or partition, the clone(s) are distinguished only be /dev/ entry. The /dev/ entries for the partitions are likely to be re-enumerated if the drive is disconnected (e.g, USB) and the drive entry may be as other devices come and go. When mounting remove the fstab entry only if it includes the /dev/ entry as well as the UUID.
- [ ] XXX Explain the importance of unmount and hazards of remount.
- [ ] ADD Explanation of the ESP.
- [ ] ADD basics of ddrescue, and device specification, inc. hazards
- [ ] XXX Device id in OS may change between runs.
- [ ] XXX Encrypted drives not considered.
- [ ] XXX -u works for device with intact accessible partition volume metadata but drive errors on metadata may cause a lockup before processing. Cover this in the usage notes.

## TODOS ROBUSTNESS

- [ ] XXX Do not purge caches by default for ZAP as these may assist recovery steps down range.
- [ ] XXX Double check alignment of extents in ZAP.
- [ ] ADD A set of pre-defined block contents to be used with ZAP instead 
of /dev/zero.
- [ ] ADD ZAP part table area and recover partition table from backup for case of apparently unformatted drive.
- [ ] ADD Other file system types alternate format recovery options.
- [ ] ADD Linux UUID reset (macOS tools are unreliable).
- [ ] ADD Consistency checks for volume names matching map metadata.
- [ ] XXX For partitions, check that device partition label matches the map.
- [ ] XXX Devices must be "/dev/" specced although this could be inferred--normalize.
- [ ] XXX Verify LABEL tolerates whitespace or disallow.
- [ ] XXX Ensure no volume metadata dependencies for pathological case.
- [ ] ADD /dev/ specific fstab entries to prevent auto-mount; including adding and removal without a corresponding drive present.
- [ ] ADD Detection of Linux systemd support for auto-unmounting.
- [ ] XXX Reports inconsistent about inclusion of all blocks vs. summary between macOS and Linux.
- [ ] ADD improve signal handling for suspend / resume / abort of helper. currently ^C doesn't work after ^Z.
- [ ] ADD comparison of data between ZAP write and re-read.
- [ ] XXX Option handling is bone-headed, refactor.
- [ ] XXX is_device() (actual) needs to be distinguished from is /dev
- [ ] XXX CHECK FOR EXISTING MATCHING MAP -- CAN'T DETECT source v. destination reversal or ambiguity.
- [ ] XXX The -Z zap read test relies on dd exit status. Better to inspect the block read for contents?
- [ ] ADD Regression test suite.
- [ ] ADD A metadata side store for source / dest paths as these can't easily be parsed out of the map file due to ambiguous whitespace.
- [ ] XXX When a partition is cloned, its volume UUID needs to be updated, but no utility to does this in Ventura+ (Linux?). CCC used to offer a helper; now it's a UI option.
- [ ] ADD Provision for a global persistent no-mount that is not dependent on reading device data so that OS doesn't make a bad volume worse before copying.
- [ ] ADD zap blocklist sanity check for drive/part metadata regions, per device format.
- [ ] XXX For -p -s Figure out a way to look up src/dst devices from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] XXX Fix volume -u -m UUID edge case handling to Linux only.
- [x] XXX Use stat(1) to check for src/dst hard links.
- [x] ADD copy destination overwrite confirmation.

## TODOs Code
- [ ] XXX Replace vi(1) with ex(1) in macOS -m -u.
- [ ] XXX For -p -s Figure out a way to look up target device from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] shellcheck review (first pass).
- [x] Refactor blocklist creation to better separate ext2/3/4 report
generation which requires block address to be in filesystem blocks not
device blocks, while partition offsets are always device blocks.

## TODOS DRIVE LOGIC

- [ ] XXX Revisit SMART scanning.
- [x] XXX Revisit dd --odirect / --idirect options.
- [x] XXX -Z Blocksize and zap alignment on 4K Advanced Format drives???

# SUPPORTING DOCUMENTATION

**Macports package manager**
https://www.macports.org/install.php

**Homebrew — Package Manager for macOS (or Linux)**
https://brew.sh/

**GNU ddrescue Manual**
https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

**man pages**
diskutil(8), fsck(8), fstab(5), lsblk(8), mount(8), dd(1)