# DDRESCUE-HELPER

**`ddrescue-helper.sh`** is a helper script for running GNU ddrescue.

It currently runs on macOS and Ubuntu.

# SUMMARY & PURPOSE

- Do you have spinning hard drives that are suffering from occasional read errors?
- Do you wish to keep using these drives?
- Do you want to know which files are affected by read errors or slow reads?
- Do you want to do a best-effort clone of a whole drive, a partition, or some files affected by read errors?
- Do you wonder if you can get the drive to re-allocate blocks causing read errors?

`Ddrescue-helper.sh` can help. It's a bash script for running GNU ddrescue on macOS and Ubuntu/Linux Mint that can:

- UNMOUNT, MOUNT, and FSCK volumes om a partition or whole drive basis.
  where unmount is persistent based on fstab entry for the volume UUID.
- COPY or SCAN a drive, partition or file using ddrescue, creating a BAD BLOCK MAP and READ RATE LOG (METADATA) which get stored in a named (LABELED) directory.
- REPORT files affected by read errors and slow-reads using copy/scan metadata.
  (macOS HFS+, Linux NTFS, ext2/3/4, and HFS+)
- ZAP device blocks associated with read errors to trigger a spinning drive to re-allocate them. This has the potential to regain access to a drive that is otherwise unmountable.

`Ddrescue-helper.sh` helps by hiding details of the ddrescue command, ensuring that source and destination volumes remain unmounted during clone operations, and performaning simple consistency checks to make using ddrescue easier and more effective.

> [!IMPORTANT]
> The script was developed using bash v3.2, on macOS Ventura.
> It's been tested on older Mac OS 10.14 Mojave.
> It's been tested on Ubuntu 23.10 and Mint 21.2., but the key Linux dependencies are on use of udev and systemd to handle devivce mounts, which has been common for 10 years.

### ABOUT GNU DDRESCUE

GNU `ddrescue` is a tool for copying storage devices (drives, partitions, or files) in a way that gracefully handles read errors and restarts, allowing as much data as possible to be recovered from the source.

A side effect of running ddrescue is the creation of two kinds of metadata for the copy source:
- A "domain" MAP of device regions with read errors and their extents;
- A rate log of read performance measured second-by-second.

GNU ddrescue can be installed on macOS using `macports` or `homebrew`

GNU ddrescue can be installed on Linux using the ordinary package managers.

### ABOUT FILESYSTEM SUPPORT PACKAGES FOR LINUX

For FSCK and REPORTS `ddrescue-helper.sh` depends on `hfsutils`, `exfatprogs`, `dosfstools`, and `ntfsprogs`. All are available as packages from the standard repositories, if they're not already installed.

# USAGE OVERVIEW

Dealing with drive media errors can involve working with a whole drive, specific partitions, or specific files. For example:

— Knowing a device or files are affected by read errors (REPORTS).

— Recovering as much data as possible when no backup exists (COPY).

— Preventing disturbance of volume structures while recovery is in progress (UNMOUNT).

— Triggering a drive to re-allocate bad blocks (ZAP).

— Checking and repairing filesystem structure to recover from corruption associated with re-allocated blocks (FSCK).

`ddrescue-helper.sh` assists as follows:

- Simplifies operation of GNU `ddrescue` by hiding standard options and performing consistency checks.

- Keeps `ddrescue` metadata in a named folder (LABEL) and checks that existing domain MAP agrees with command-specific source and destination.

- Persistently UNMOUNTs volumes to ensure that drive or partition isn't changed by the OS while a rescue copy is running. Re-mount a drive or partition and disable persistent auto-mount prevention.

- COPIES (or SCANs) drive-to-drive, drive-to-file (image), or file-to-file.

> [!NOTE]
> SCANNING a drive means copying to /dev/null to create the bad block "MAP" based on read errors and generate a read-rate log for slow areas. Scan surveys a source without rescuing any data.
>
> In the case of working with specific files, when recovery from a backup isn't possible, a small error region may be tolerable (e.g., a small content loss in a media file) as compared to alternative of losing access to the whole file.
>
> COPIES and SCANS can be stopped with ^C and resumed by rerunning the same helper command. It's also restartable after drive disconnection or system crash.

- For macOS HFS+ volumes and Linux ext2/3/4, NTFS, and HFS+ volumes, the helper can REPORT files by bad-blocks and slow reads.

- Bad blocks can be "ZAPPED" to trigger the drive to re-allocate them. This can regain access a volume that's inaccessible due to read errors in filesystem metadata.

- Run FSCK on a partition or all the partitions on a drive.

# WARNINGS

> [!CAUTION]
> THIS SCRIPT CAN OVERWRITE CRITICAL FORMAT STRUCTURES. However, ZAP only affects blocks with read errors it's not inherently hazardous.
>
> __USE AT YOUR OWN RISK__
>
> This script has been coded with care, but unexpected behaviors are possible. Shell scripts are pesky because they rely heavily on text substitution.
>
> THE WISE DATA HOARDER WILL HAVE BACKUPS AND SIMPLY REPLACE A PROBLEM DRIVE.
>
> The frugal or bereft may want to work with janky devices at hand.
>
> Making a terrible mistake is possible, but the skilled may be rewarded.

> [!IMPORTANT]
> IS CONTINUING TO USE A DRIVE WITH MEDIA ERRORS SANE?
>
> My experience is that commodities spinning hard drives (especially large cheap drives) have unreliable areas that only get exposed when the drive is used very close to full for a long time. I will make a wild-ass guess that the drive makers solve a binning problem by tolerating a spread of defects in shipped product and deferring the exposure of these defects for as long as possible. The gambit is that customers won't become aware of the problem areas until the drive is well out of warranty and so old that accountability for failure is irrelevant. The implication of this wild assessment is that a well-used drive can be expected to suffer from some errors when heavily used, but still has life it in if you can find a way to deal with the problem areas. For example, one way to work around bad spots is to set-aside large files that cover them. Another is to encourage the drive to re-allocate bad sectors.
>
> By running a scan over an entire drive, such defects can be side-stepped by setting aside affected files and zapping bad-blocks to re-allocate according to the drives spare provisioning. This may allow continued use of a drive with minor errors.

# COMMAND OPTIONS

There are THREE MODES of `ddrescue-helper.sh` operation:

### 1. UNMOUNT, MOUNT, AND FSCK A DRIVE OR PARTITION.

`ddrescue_helper.sh -u | -m | -f <device>`
 
`-u, -m` include updating `/etc/fstab` (using `vifs(8)` on macOS) to make devices ready to be copied without interference from the auto-mount capabilities of the OS. `-u` prevents auto-mount after unmount. `-m` re-enables auto-mount after mount. 

`-f` looks up the volume type of device and runs the appropriate form of `fsck`. This may be appropriate to check / repair volume integrity after making a copy or zapping.

> [!NOTE]
> If `<device>` is a partition, only it is affected. If `<device>` is a drive, all partitions are affected. Only partitions with volume UUIDs can be persistently unmounted using this script, but this is the common case.
>
> On macOS, containers are observed.
>
> With `-m`, you can supply a volume UUID as `<device>`to remove an entry from /etc/fstab (no attempt to mount is made). An `/etc/fstab` entry can become orphaned if unmounted with `-u` after which the partition is reformatted or overwritten as a copy destination. You also can run `vifs` to do anything you want to `/etc/fstab` by hand.
>
> If you need a general purpose mount inhibitor for macOS which works for all devices, including disk images, see [Disk Arbitrator](https://github.com/aburgh/Disk-Arbitrator/).
> Note: Disk Arbitrator hasn't been updated since 2017. On macOS Ventura it works to properly inhibit auto-mounts, but a UI bug prevents its Quit from working, so you have to kill it by hand.

### 2. SCAN, COPY

Runs `ddrescue` to scan a device or recover data, generating a MAP of read errors and a rate log which records device regions that experienced read slowdown. The MAP and rate log are stored in a folder named <label>

`ddrescue_helper.sh -c [-X] <label> <deivce> /dev/null`

`ddrescue_helper.sh -c <label> <deivce> <device>`

`ddrescue_helper.sh -c <label> <deivce> <file>`

`ddrescue_helper.sh -c <label> <file> <file>`

- SCAN a drive or partition to create error MAP and rate log. 

- COPY a drive or partition to another device.

- COPY drive or partition to a file (image).

- COPY a file to another file.

SCAN reads <source> to build the bad block MAP and rate log without saving device data.

COPY saves the data on <source> at <destination>. COPY is destructive to data on <destination>. Basic consistency checks are performed by the helper to avoid some basic hazards.

About `-X`: During SCAN, `ddrescue` scraping is disabled by default to save some time getting block list for use with REPORTS `-p` and `-s`. 

For COPY `-X` is implied to recover as much data as possible.

Scraping explanation: By default. `ddrescue` uses large reads to speed copy progress. When it gets a read error it marks the large area as an error and continues to obtain as much as fast as possible. A subsequent read pass "trims" the large read area from its leading and trailing edges down to the bad blocks. In a third pass, it "scrapes" each block in the trimmed area to collect as much data as possible leaving a preview MAP of bad blocks. If there are localized series of bad blocks, which is the typical case, scraping during SCAN can be time consuming and not worth the effort because files can be large relative to the bad region, and ZAP will test each block. `-X` enables `ddrescue` scraping for SCAN, to try to refine the resolution of small files affected by blocks. 
See the GNU ddrescue manual. 
  
### 3 REPORT AFFECTED FILES AND ZAP BLOCKS

These functions utilize the `ddrescue` block MAP data resulting from copy / scan.

`ddrescue_helper.sh -p | -s | -z <label> <device>`

`-p` REPORT files affected by read errors.

`-s` REPORT files affected by slow reads, less than 1MB/s ()

REPORT works on macOS HFS+ and on Linux for ext2/3/4. NTFS, HFS+.

`ddrescue_helper.sh -z | -Z <label> <device>`

`-z` ZAP PREVIEW. Print a list of blocks that will be affected -Z but don't ZAP. If the list is large (thousands) it's likely not productive to attempt zapping.

`-Z` ZAP blocks listed as bad in the `ddrescue` MAP in an attempt to trigger the drive to reallocate them. ZAP performs a block read, and if the read reports failure it then performs a block write. The risk to existing data is low because the block is already unreadable.

ZAP can allow recovery access to areas with bad blocks, and can enable fsck to repair a volume that is stuck at a read error.

> [!WARNING] 
> THERE ARE FEW SANITY CHECKS FOR ZAP — USE WITH CAUTION. HOWEVER IT WON'T LET YOU ZAP BLOCKS IN THE PRIMARY GUID PARTITION TABLE (DRIVE BLOCKS 0–39)
>
> ZAPPING TO A RAID SOUNDS LIKE A BAD IDEA.

> [!TIP] 
> If you have bad-block or slow-read metadata for an entire drive, you can use it with `-p` and `-s` which are partition (volume) oriented. The needed partition offset will be calculated automatically and applied to the blocks list used to generatie the reports.

# BACKGROUND & PURPOSE

The idea for this helper came about from dealing with media errors occurring during local backups of spinning drives. As spinning drives fill up and age they become prone to bad regions.

I keep backups, and I prefer to replace a drive with any errors. But for reasons of being cheap, I've wanted to keep using drives affected by small number of bad blocks for as long as possible. One way to do this is to set aside files that cover bad spots. But I ran into a case where filesystem metadata was affected and a drive became unmountable.

To recover from this, I started by looking at SMART self-test and logs to handle 
bad blocks. SMART self-tests can run in the background while the drive is in use and the log can be queried on a live drive. This seemed promising, but due to vendor inconsistencies with SMART, and that many of my data drives are attached by USB, which prevents access to SMART capabilities, I couldn't easily build a helper based on them.

As an interesting aside, I discovered that when a USB drive is passed through to an Ubuntu VM via Parallels virtual machine, `smartctl(8)` works as if the drive were locally attached by SATA, so I wonder what keeps SMART from working with native USB drives. 

Linux has `badblocks(8)` to scan for bad blocks, and `hdparm(8)` to write single blocks to re-MAP bad blocks. Linux `badblocks` has nice integration with ext2/3/4 filesystem, where bad-block list can be ingested by `fsck` to prevent those blocks from being allocated.

But my primary system is a hackintosh and my data is on Apple HFS+, so I prefer
to handle my drives in this context. `badblocks` and `hdparm` are not available,
on macOS, even via 3rd-party ports. 

`dd(1)` is an old-school utility available on every Unix variant that can write single blocks. Using it I found I could trigger re-allocation a bad sector on macOS, allowing me to regain access to the unmountable drive I mentioned above.

GNU ddrescue is an indispensable tool for recovering data from failing drives. As it works, it creates a MAP of unreadable blocks. Compared to SMART, it's far simpler and more consistent to use, unlike SMART it's drive hardware agnostic, and you can limit scope to a single partition or file, then parse the MAP domain into a bad block list for use with `dd`.

When making a full partition or drive copy, it's very important that the source and destination devices are disturbed, so that the filesystem metadata remains in a consistent state until the copy is complete. Further, a copy may be interrupted by a timeout, drive disconnection, a system crash, or you way want to intentionally interrupt it, so auto-mount must be prevented.

While working with a problem HFS+ drive, I came across the -B option for `fsck.hfs(8)`, which accepts a list of block addresses and reports which files the blocks belong to. It turns out that NTFS and ext2/3/4 `fsck` can do this too.

`ddrescue` can also generate a rate log, which like the bad block MAP, can be converted into a block list and fed to `fsck` to find files affected by drive regions with very slow reads.

From here I had all the parts and ideas came together for this helper.

# TODOs

This helper is macOS / HFS+ centric, but the script is made so support can be added for Linux and other filesystems.

## TODOs Usability

**General**

- [ ] ADD auto-detection and installation of supporting tools on Linux.
- [ ] XXX Test zap of a file
- [ ] ADD Linux UUID reset (macOS tools are unreliable)
- [ ] ADD Consistency checks for volume names matching map metadata
- [ ] ADD System detection of ddrescue version or options
- [ ] ADD Detection of Linux systemd support for auto-unmounting
- [ ] ADD selectable rate limit for -P
- [ ] XXX For partitions, check that device partition label matches the map.
- [ ] XXX Devices must be "/dev/" specced although this could be inferred
- [ ] XXX Verify LABEL tolerates whitespace or disallow.
- [ ] ADD a summary of unreadable blocks in output of -Z, inc failed retry
- [ ] ADD improve signal handling for suspend / resume / abort of helper. currently ^C doesn't work after ^Z
- [ ] ADD Save the ddrescue work summaries for each run so that progress can be examined.
- [ ] ADD Input a list of files to copy (source) and a tree of metadata.
- [ ] ADD pass additional options to ddrescue
- [ ] ADD Option to zap within the GPT, then copy the redudant GPT over the primary.
- [ ] ADD /dev/ specific fstab entries to prevent auto-mount; including adding and removal without a corresponding drive present.
- [ ] XXX Reports inconsistent about inclusion of all blocks vs. summary between macOS and Linux.
- [x] ADD Improve situational awareness of the EFI service partition re MBR
- [x] ADD fsck whole drive format vs. volumes.
- [x] ADD -p -z -Z checks for unmanageably large numbers of problem blocks in the map
- [x] ADD zap preview and confirmation
- [x] ADD -z print a summary of LBA extents affected by read errors This is a sanity check for -Z. Large areas of errors indicates a failed drive and zapping is impractical.
- [x] ADD prettify the output of -Z and save it in a log
- [x] XXX Fix src/dst relative file path naming to be per CWD not the label folder
- [x] ADD Sanity checks for src/dst aliases and symlinks
- [x] ADD Check for source file is newer than dest file
- [x] ADD Check for <file> to <file> if destination is directory
- [x] XXX identical source / dest check needs to consider different paths to same resource
- [x] XXX -s Slow reads extent spread for coverage vs block quantity.
- [x] XXX -p -s Adjust partition offset based on device specified
- [x] ADD rate log reporting for slow areas and related files
- [x] ADD check for map match to source / desk

**Drive Format**

- [ ] ADD GPT / MBR / table inspection & recovery
- [ ] ADD Partition superblock recovery
- [ ] ADD Save and restore partition table to metadata
- [x] ADD MBR vs GPT awareness?

***Mac & Filesystem Support***

- [ ] XXX Investigate limits of APFS partition cloning
- [ ] ADD Force use of /dev/rdisk on macOS for speed.
- [ ] ADD help for changing volume LABELs and partition/volume UUIDs
/System/Library/Filesystems/TYPE.fs/Contents/Resources/TYPE.util -s rdisk21s10
No "/dev", -s to set new random UUID
- [x] ADD APFS fsck
- [x] ADD FAT, exFAT fsck

**Linux Mainline**

- [ ] ADD Linux zap (via hdparm)
- [x] ADD -m -u -c -p -s -z on Linux

**Linux FAT, ExFAT**

- [x] ADD FAT, ExFAT file lookup and fsck (optional dostools)

**Linux NTFS**

- [ ] ADD option to copy using ntfsclone
- [ ] ADD Linux ddrutility support to full partition / drive copy for NTFS
- [x] ADD NTFS fsck (ntfsprogs: ntfsfix)
- [x] ADD NTFS reports (ntfsprogs: ntfscluster)

**Linux EXT2/3/4**

- [ ] ADD Option to pass error blocklist to fsck -l (set aside blocks) 
- [x] ADD ext2,3,4 file lookup and fsck
- [x] ADD ext2,3,4 reports

## TODOs Documentation

- [ ] ADD Explanations about how to read the map, the support metadata, and the thinking about blocklists, extents, and blocksize considerations.
- [ ] ADD Explanations about modern vs older versions of Linux.
- [ ] ADD Explanation about APFS and bootdrive exclusions
- [ ] ADD help with removal of stale fstab entires for the destination after copy is complete.
- [ ] ADD Explain GPT vs other partitioning implications.
- [ ] XXX Explain unmount on macOS & Linux, incl volume UUIDs, read-only,
interactions with systemd, etc.
- [ ] XXX Assistance for thinking about corrupted volumes
- [ ] ADD Explain volume UUID edge-cases
- [ ] XXX After cloning a drive or partition, the clone(s) are distinguished only be /dev/ entry. The /dev/ entries for the partitions are likely to be re-enumerated if the drive is disconnected (e.g, USB) and the drive entry may be as other devices come and go. When mounting remove the fstab entry only if it includes the /dev/ entry as well as the UUID. 
- [ ] XXX Explain the importance of unmount and hazards of remount.
- [ ] ADD Explanation of the ESP
- [ ] ADD basics of ddrescue, and device specification, inc. hazards
- [ ] XXX Device id in OS may change between runs
- [ ] XXX Encrypted drives not considered
- [ ] XXX -u works for device with intact accessible partition volume metadata but drive errors on metadata may cause a lockup before processing. Cover this in the usage notes

## TODOs Robustness

- [ ] XXX The -Z zap read test relies on dd exit status. Better to inspect the block read for contents
- [ ] ADD Regression test suite
- [ ] ADD A metadata side store for source / dest paths as these can't easily be parsed out of the map file due to ambiguous whitespace
- [ ] XXX When a partition is cloned, its volume UUID needs to be updated, but no utility to does this in Ventura+ (Linux?). CCC used to offer a helper; now it's a UI option.
- [ ] ADD Provision for a global persistent no-mount that is not dependent on reading device data so that OS doesn't make a baad volume worse before copying.
- [ ] ADD zap blocklist sanity check for drive/part metadata regions
- [ ] XXX For -p -s Figure out a way to look up src/dst devices from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] XXX Fix volume -u -m UUID edge case handling to Linux only.
- [x] XXX Use stat(1) to check for src/dst hard links
- [x] ADD copy destination overwrite confirmation

## TODOs Code
- [ ] XXX Replace vi(1) with ex(1) in macOS -m -u
- [ ] XXX For -p -s Figure out a way to look up target device from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] shellcheck review (first pass)
- [x] Refactor blocklist creation to better separate ext2/3/4 report
generation which requires block address to be in filesystem blocks not
device blocks, while partition offsets are always device blocks.

## TODOs Drive Logic

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