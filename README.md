# DDRESCUE-HELPER

**`ddrescue-helper.sh`** is a helper script for running GNU ddrescue.

It's currently oriented to macOS and HFS+ volumes. But is written to be extended to other file systems. Coding for Linux is under way.

It can:

- Unmount (persistent), re-mount, and fsck of volumes based on volume UUID.
- Copy (or scan) of storage devices to create a bad block map and rate log (metadata) which are stored in a named directory.
- Report files affected by errors or slow reads (for macOS HFS+ volumes)
- Zap sectors in error regions to try to trigger a spinning drive to re-allocate sectors.

By hiding details of the ddrescue command line, ensuring that source and destination volumes remain unmounted, and performaning simple consistency checks, it makes using ddrescue a bit easier.

> [!IMPORTANT]
> The script was developed using bash v3.2, which should be compatible with older systems. But it was made on macOS Ventura and hasn't been tested on other macOS versions. If Apple has changed output formats of information from `diskutil` it may not work properly.

### ABOUT GNU DDRESCUE

GNU ddrescue is a tool for copying storage devices (drives, partitions, or files) in a way that gracefully handles read errors and restarts, allowing as much data as possible to be recovered from the source.

A side effect of running ddrescue is the creation of two kinds of metadata for the copy source:
- A "domain map" of device regions with read errors and their extents;
- A rate log of read performance measured second-by-second.

GNU ddrescue can be installed on macOS using `macports` or `homebrew`

# USAGE OVERVIEW

Dealing with drive media errors can involve working with a whole drive, specific paritions, or specific files. For example:

— Knowing what files are affected by read errors.

— Recovering as much data as possible when no backup exists.

— Preventing disturbance of volume structures while recovery is in progress.

— Triggering a drive to re-allocate bad blocks.

— Checking and repairing filesystem structure to recover from corruption assciated with re-allocated blocks.

`ddrescue-helper.sh` assists as follows:

- Simplifies operating GNU ddrescue by hiding standard options and performing simple consistency checks.

- Keeps `ddrescue` metadata in a named folder and checks that existing domain map agrees with command-specific source and destination.

- Persistently unmounts volumes to ensure that drive or partition isn't changed by the OS while a rescue copy is running. Re-mount a drive or partition and disable persistent automount prevention.

- Copies (or scans) drive-to-drive, drive-to-file (image), or file-to-file.

> [!NOTE]
> Scanning a drive means copying to /dev/null to create the bad block "map" based on read errors and generate a read-rate log for slow areas. Scan surveys a source without rescuing any data.
>
> In the case of working with specific files, when recovery from a backup isn't possible, a small error region may be tolerable (e.g., a small content loss in a media file) as compared to alternative of losing access to the whole file.
>
> Copies and scans can be stopped with ^C and continued by rerunning the same command. Recovery is also restartable after drive disconnection or system crash.

- For macOS HFS+ volumes, a report of affected files can be generated from the ddrescue metadata for both bad-blocks and slow reads.

- Bad blocks can be "zapped" to trigger the drive to re-allocate them. This can regain access a volume that's inaccessible due to read errors in filesystem metadata.

- Run fsck on a whole drive or a partition.

# WARNINGS
> [!CAUTION]
> THIS SCRIPT CAN IRRETREIVABLY DAMAGE DATA INCLUDING LOSS OF ALL DRIVE ACCESS DUE TO OVERWRITING CRITICAL FORMAT STRUCTURES. 
>
> __USE AT YOUR OWN RISK__

This script has been coded with care, but unexpected behaviors are possible. Shell scripts are pesky because they rely heavily on text substitution.

THE WISE DATA HOARDER WILL HAVE BACKUPS AND SIMPLY REPLACE A PROBLEM DRIVE.

The frugal or bereft may want to work with janky devices at hand.

Making a terrible mistake is possible, but the skilled may be rewarded.

> [!IMPORTANT]
> IS CONTINUING TO USE A DRIVE WITH MEDIA ERRORS SANE?
>
> My experience is that large (TB+) commodities spinning hard drives have unreliable areas that only get exposed when the drive is used very close to full for a long time. I will make a wild-ass guess that the drive makers solve a binning problem by tolerating a spread of defects in shipped product and deferring the exposure of these defects for as long as possible. The gambit is that customers won't become aware of the problem areas until the drive is well out of warranty and so old that accountability for failure is irrelevant. The implication of this wild assessment is that a well-used drive can be expected to suffer from some errors when heavily used, but still has life it in if you can find a way to deal with the problem areas. For example, one way to work around bad spots is to set-aside large files that cover them. Another is to encourage the drive to re-allocate bad sectors.
>
> By running a scan over an entire drive, such defects can be side-stepped by setting aside affected files and zapping bad-blocks to re-allocate according to the drives spare provisioning. This may allow continued use of a drive with minor errors.

# COMMAND OPTIONS

There are THREE MODES of `ddrescue-helper.sh` operation:

### 1. UNMOUNT, MOUNT, AND FSCK A DRIVE OR PARTITION.

`ddrescue_helper.sh -u | -m | -f <device>`
 
`-u, -m` include updating `/etc/fstab` (using `vifs(8)` on macOS) to make devices ready to be copied without interference from the auto-mount capabilities of the OS. `-u` prevents auto-mount after unomount. `-m` re-enables auto-mount after mount. 

`-f` looks up the volume type of device and runs the appropriate form of `fsck`. This may be appropriate to check / repair volume integiru after making a copy or zapping.

> [!NOTE]
> With `-m`, you can supply a volume UUID as `<device>`to remove an entry from /etc/fstab (no attemt to mount is made). An `/etc/fstab` entry can become orphaned if unmounted with `-u` after which the parition is reformatted or overwritten as a copy destination. You also can run `vifs` to do anything you want to `/etc/fstab` by hand.
>
> If you need a general purpose mount inhibitor for macOS, which works for all devices, includeing disk images, see [Disk Arbitrator](https://github.com/aburgh/Disk-Arbitrator/).
> However, Disk Arbitrator hasn't been updated since 2017 and on macOS Ventura a bug prevents it its Quit from working, you have to kill it by hand.

### 2. SCAN, COPY

Runs `ddrescue` to scan a device or recover data, generating a map of read errors and a rate log which records device regions that experienced read slowdown. The map and rate log are stored in a folder named <label>

`ddrescue_helper.sh -c [-X] <label> <deivce> /dev/null`

`ddrescue_helper.sh -c <label> <deivce> <device>`

`ddrescue_helper.sh -c <label> <deivce> <file>`

`ddrescue_helper.sh -c <label> <file> <file>`

- Scan a drive or partition to create error map and rate log.

- Copy a drive or partition to another device.

- Image a drive or partition to a file.

- Copy a file.

`-X` enables `ddrescue` scraping for scan, to try to refine the resolution of affected blocks. Scan scraping is disabled by default to save some time getting block list for use with `-p` and `-s`. See the GNU ddrescue manual.

For copy `-X` is implied to recover as much data as possible.
  
### 3 PRINT AFFECTED FILES (HFS+) AND ZAP BLOCKS

These functions utilize the `ddrescue` block map data resulting from copy / scan.

`ddrescue_helper.sh -p | -s | -z <label> <device>`

`-p` Print a list of files affected by read errors (HFS+ only)

`-s` Print a list of files affected by slow reads, less than 1MB/s (HFS+ only)

`-z` Zap preview. Print a list of blocks that will be affected -Z but don't zap. If the list is large (100 or more) it's likely not productive to attempt zapping.

`ddrescue_helper.sh -Z <label> <device>`

`-Z` Zap blocks in an attempt to trigger the drive to reallocate them. This is destructive to those blocks, but it can allow recovery of space from large media, and can enable fsck to repair a volume that was stuck at a read timeout.

> [!WARNING] 
> THERE ARE NO SANITY CHECKS FOR ZAP — USE WITH GREAT CAUTION.

> [!TIP] 
> If you have bad-block or slow-read metadata for an entire drive, you can use it with `-p` and `-s` which are partition (volume) oriented. The needed partition offset will be calculated automatically and applied to the blocks list used to generatie the reports.

# BACKGROUND & PURPOSE

The idea for this helper came about from dealing with media errors occurring during local backups of spinning drives. As spinning drives fill up and age they become prone to bad regions.

I keep backups, and I prefer to replace a drive with any errors. But for reasons of being cheap, I've wanted to keep using drives affected by small number of bad blocks for as long as possible. One way to do this is to set aside files that cover bad spots. But I ran into a case where filesystem metadata was affected and a drive became unmountable.

To recover from this, I started by looking at SMART and `hdparm(8)` on Linux to find and re-map bad blocks. I also became aware of the `badblocks(8)` utility. 
These tools are interesting, but due to vendor inconsistencies with SMART, and that many of my data drives are attached by USB, which prevents access to SMART capabilities, I couldn't easily build a helper based on them. SMART long tests take a long time to run and aren't supported by many common drives.

My daily driver is a hackintosh and `hdparm` and `badblocks` are not available, even via 3rd-party ports.

[As an interesting aside, I discovered that when a USB drive is passed through to an Ubuntu VM via Parallels, `smartctl(8)` works as if it were locally attached by SATA.]

While there's no `hdparm` for macOS, I discovered that by careful use of `dd`, I can trigger a spinning drive to re-allocate a bad sector. Using this tactic allowed me to regain access to the unmountable drive I mentioned above, and `dd` is a widely available utility.

GNU ddrescue is an indispensable tool for recovering data from failing drives. And compared to SMART, it's far simpler and more consistent to use it to scan a drive or partition, then parse the the map domain into a bad block list for use with `dd`. 

Using `ddrescue` is just complicated enough to make it difficult to recall the command syntax, so a helper seems natural.

It's very important that when recovering data that the source and destination devices are not automounted so that they remain in a consistent state until the copy is complete. A copy may be interrupted by a timeout, drive disconnection or a system crash, or intentionally interrupted.

It so happens that my data drives are formatted HFS+. While working with a problem drive, I came across the -B option for `fsck.hfs(8)`, which accepts a list of block addresses and reports which files the blocks belong to.

Finally,`ddrescue` can also generate a rate log, which like the bad block map, can be converted into a block list and fed to `fsck.hfs` to find files affected by drive regions with very slow reads.

With this, all the pieces of the puzzle for how to cope with my cranky drives, came together, so I put all these ideas together into this `ddescue-helper.sh` script.

# TODOs

This helper is macOS / HFS+ centric, but the script is made so support can be added for Linux and other filesystems.

**Usability**

- [ ] XXX For partitions, a check that metadata device partition label matches the map.
- [ ] XXX fsck whole drive should check the overal drive as well as all partitions.
- [ ] ADD Improve situational awareness of the EFI service partition
- [ ] ADD -p -z checks for unmanageably large numbers of problem blocks in the map
- [ ] ADD Force use of /dev/rdisk on macOS for speed.
- [ ] ADD help with removal of stale fstab entires for the destination after copy is complete.
- [ ] ADD /dev/ specific fstab entries to prevent automount; including adding and removal without a corresponding drive present.
- [ ] ADD help for changing volume LABELs and partition/volume UUIDs
/System/Library/Filesystems/TYPE.fs/Contents/Resources/TYPE.util -s rdisk21s10
No "/dev", -s to set new random UUID
- [ ] ADD Only auto unmount for copy/zap not scan ?? maybe not
- [ ] ADD Save the ddrescue work summaries for each run so that progress can be examined.
- [ ] ADD Input a list of files to copy (source).
- [ ] ADD Option to remove metadata by <label>
- [ ] ADD Consistency checks for volume names and helper metadata
- [ ] XXX fsck robustness assistance for corrupted volumes
- [ ] ADD GPT / MBR / table recovery
- [ ] ADD Partition superblock recovery
- [ ] XXX Fix src/dst relative file path naming to be per CWD not the label folder
- [ ] XXX Devices must be "/dev/" specced although this could be inferred
- [ ] XXX Verify Label tolerates whitespace or disallow.
- [ ] ADD selectable rate limit for -P
- [ ] ADD zap preview and confirmation
- [ ] ADD prettify the output of -Z and save it in a log
- [ ] ADD a summary of unreadable blocks in output of -Z, inc failed retry
- [ ] ADD improve signal handling for suspend / resume / abort of helper. currently ^C doesn't work after ^Z
- [x] ADD Sanity checks for src/dst aliases and symlinks
- [x] ADD -z print a summary of LBA extents affected by read errors This is a sanity check for -Z. Large areas of errors indicates a failed drive and zapping is impractical.
- [x] ADD Check for source file is newer than dest file
- [x] ADD Check for <file> to <file> if destination is directory
- [x] XXX identical source / dest check needs to consider different paths to same resource
- [x] XXX -s Slow reads block spread for best coverage.
- [x] XXX -p -s Adjust partition offset based on device specified
- [x] ADD rate log reporting for slow areas and related files
- [x] ADD check for map match to source / desk

**Documentation**

- [ ] XXX After cloning a drive or partition, the duplicates are distinguished only be /dev/ entry. The /dev/ entries for the partitions are likely to be re-enumerated if the drive is disconnected (e.g, USB) and the drive entry may be as other devices come and go. When mounting remove the fstab entry only if it includes the /dev/ entry as well as the UUID. 
- [ ] XXX Explain the importance of unmount and hazards of remount.
- [ ] ADD Explanation of the ESP
- [ ] ADD basics of ddrescue, and device specification, inc. hazards
- [ ] XXX Device id in OS may change between runs (doc)
- [ ] XXX Encrypted drives not considered (doc)
- [ ] XXX -u works for device with intact accessible partition volume metadata but drive errors on metadata may cause a lockup before processing. Cover this in the usage notes

**Robustness**

- [ ] ADD A metadata side store for source / dest paths as these can't easily be parsed out of the mapfile due to ambiguous whitespace
- [ ] XXX When a partition is cloned, its volume UUID needs to be updated, but no utility to does this in Ventura+. CCC used to offer a helper; now it's a UI option.
- [ ] ADD Provision for a global persistent no-mount that is not dependent on reading device data so that OS doesn't make a baad volume worse before copying.
- [ ] ADD zap blocklist sanity check for drive/part metadata regions
- [ ] XXX For -p -s Figure out a way to look up src/dst devices from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] XXX Use stat(1) to check for src/dst hard links
- [x] ADD copy destination overwrite confirmation

**Linux & Filesystem Support**

- [ ] ADD Linux ddrutility support to full partition / drive copy for NTFS
- [ ] XXX Test -m -u -c -p -s -z Z on Linux
- [ ] ADD ext2,3,4 file lookup and fsck
- [ ] ADD FAT, NTFS file lookup and fsck, including ddrutility for sparse recovery of NTFS volumes.
- [ ] ADD pass additional options to ddrescue
- [ ] ADD badblocks(8) style integration for ext3/4

**Code**
- [ ] Replace vi(1) with ex(1) in -m -u
- [ ] XXX For -p -s Figure out a way to look up target device from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [ ] shellcheck review

**SMART / Drive Logic**

- [ ] XXX -Z Blocksize and zap alignment on 4K Advanced Format drives???
- [ ] XXX Revisit dd --odirect / --idirect options
- [ ] XXX Revisit SMART scanning

# Supporting Documentation

**Macports package manager**
https://www.macports.org/install.php

**Homebrew — Package Manager for macOS (or Linux)**
https://brew.sh/

**GNU ddrescue Manual**
https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

**macOS diskutil**
https://ss64.com/mac/diskutil.html

**dd(1)**
https://man7.org/linux/man-pages/man1/dd.1.html


