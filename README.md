# DDRESCUE-HELPER

**`ddrescue-helper.sh`** is Mac-oriented (for now) helper script (bash) that makes running ddrewscue easier by assisting with:
- `Unmount` (persistent), `mount` and `fsck` of volumes
- `ddrescue` copy (or scan) of storage devices or files 

It also uses ddrescue metadata to:
- Report files affected by errors or slow reads (for macOS HFS+ volumes)
- Zap sectors in error regions to try to trigger a spinning drive to re-allocate.

This helper is currently macOS and HFS+ volume oriented. But is written to be extended to other file systems and Linux.

### GNU DDRESCUE

GNU ddrescue is an indispensible tool for copying storage devices (drives, paritions, or files) in a way that gracefully handles read errors, allowing as much data as possible to be recovered from the source.

A side effect of running ddrescue is the creation of two kinds of metadata for the copy source:
- Map of areas with read errors and their extent
- Read rate log

GNU ddrescue can be installed on macOS using `macports` or `homebrew`

# DDRESCUE-HELPER BACKGROUND AND PURPOSE

The idea of for this helper script came about from dealing with media errors occuring during local backups of spinning drives containing single HFS+ data volumes, and trying to adapt to these errors and continue to use problematic drives by setting files that cover the errors. This worked until I ran into a situation where a media error affected volume metadata (inodes and journal) resulting the volume to become inaccessible. Working with the volume caused the system to hang and eventually crash.

As spinning drives fill up and age they become prone to bad regions. A common way of dealing with read errors is with backups and drive replacement.

While I prefer to replace a drive with any errors, for reasons of frugality I've wanted to keep using drives affected by very small number of bad blocks.

Dealing with device errors is a drive, file-system and data specific chore, involving a range of factors:

a) Knowing what files are affected by read errors.

b) Recovering as much data as possible when no backup exists.

c) Preventing re-use of bad drive regions.

d) Triggering a drive to re-allocate bad blocks.

e) Checking and repairing filesystem structure to recover from corruption associated with bad blocks.

`ddrescue-helper.sh` assists as follows:

- Simplifies operating ddrescue by hiding standard options.
- Keeps ddrescue metadata in a named folder and checks that existing map agrees with the specific source and destination.
- Persistently unmounts volumes on a drive to ensure that drive or partition isn't changed by the OS while rescue copy is running.
- Performs drive-to-drive, drive-to-image (file), or file-to-file copying. 
  - Scanning a drive (copying to /dev/null) creates the ddrescue "map" read errors and a read-rate log for slow areas without needing a copy destination.
  - In the case of specific files, when recovery from a backup isn't possible, a small error region may be tolerable (e.g., video) compared to losing access to the whole file. 
- Copies and scans can be stopped with ^C and continued by rerunning the same command.
- For macOS HFS+ volumes, a report of affected files can be generated from the ddrewscue meteadata.
- The bad blocks in the error map can be zapped to trigger the drive to re-allocate them. This can allow an drive that's inaccessible due to read errors in filesystem metadata to be accessed and repaired to regain access its contents.
- Runs fsck on a drive.


# IS CONTINUING TO USE A DRIVE WITH MEDIA ERRORS SANE?

My expeirence is that large (4TB+) commodities spinning hard drives have unreliable areas that only get exposed when the drive is used very close to full for a long time. I will make a wild-ass guess that the drive makers solve a binning problem by tolerating a spread of defects in shipped product and deferring the exposure of these defects for as long as possible. The gambit is that customers won't become aware of the problem areas until the drive is well out of warranty and so old that accountability for failure is irrelevant. The implication of this wild assessment is that a well-used drive can be expected to suffer from some errors when heavily used, but still has life it in if you can find a way to deal with the problem areas. For example, one way to work around bad spots is to set-aside large files that cover them. Another is to encourage the drive to re-allocate bad sectors.

By running a scan over an entire drive, such defects can be side-stepped by setting aside affected files and zapping bad-blocks to re-allocate according to the drives spare provisioning. This allows a troublesome drive to continue to be used.

# WARNING

THIS SCRIPT CAN IRRETREIVABLY DAMAGE DATA AND IS FOR WORKING WITH ERROR PRONE DRIVES. USE WITH CAUTION.

THIS SCRIPT HAS BEEN CODED WITH CARE, BUT UNEXPECTED BEHAVIORS ARE POSSIBLE. BASH IS PESKY BECAUSE IT RELIES HEAVILY ON TEXT SUBSTITUTION.

THE WISE DATA HOARDER WILL HAVE GOOD BACKUPS AND SIMPLY REPLACE A PROBLEM DRIVE.

THE FRUGAL OR BEREFT MAY HAVE NEED TO WORK WITH JANKY DEVICES AT HAND.

__—USE AT YOUR OWN RISK—__

MAKING A TERRIBLE MISTAKE IS LIKELY

# USAGE SUMMARY

There are three modes of operation:

#### 1. Unount, mount, and fsck a drive or partition.

`ddrescue_helper.sh -m | -u | -f <device>`
 
Unmount/mount includes updating /etc/fstab (vifs on Mac) to prevent auto-mount. This makes a device ready to be copied without interference from the auto-mount capabilities of the OS.

-f looks up the volume type of device and runs the appropriate form of fsck

#### 2. Scan, copy using ddrescue.

`ddrescue_helper.sh -c [-N] <label> <deivce> /dev/null`

`ddrescue_helper.sh -c [-N] <label> <deivce> <device>`

`ddrescue_helper.sh -c [-N] <label> <deivce> <file>`

`ddrescue_helper.sh -c [-N] <label> <file> <file>`

- Scan a drive or partition creating error map and rate log.
- Copy a drive or partition to another device.
- Image a drive or partition to a file.
- Copy a file.

Errors are tolerated and as much data as possible is copied.

Generates a read map of blocks listing errors and a rate log which indicates device regions that experienced an IO slowdown. The map and rate log are stored in a folder named <label>

XXX If files are relative paths, they located relative to the contents of the <label> folder created by this helper. E.g., a simple filename for destination will place it in the folder named by <label>.
  
#### 3 Print affected files and zap blocks

`ddrescue_helper.sh -p | -s | -z | -Z <label> <device>`

Use the block map generated by copy to print a list of files affected by read errors (HFS+ only) and zap blocks in areas affected by errors to nudge the drive to reallocate these areas. This is destructive to those blocks, but it can allow recovery of space from large media, and can enable fsck to repair a volume that was stuck at a read timeout.

This helper is macOS / HFS+ centric, but the script is made in a way to let support be added for Linux and other filesystems.

# TODOs

**Usability**

- [ ] ADD Check for <file> to <file> if destination is directory and reuse
file name.
- [ ] ADD auto unmount of destination drive and help with removal of stale fstab entires for the destination after copy is complete.
- [ ] ADD /dev/ specific fstab entries to prevent automount; including adding and removal without a corresponding drive present.
- [ ] ADD help for changing volume LABELs and partition/volume UUIDs
/System/Library/Filesystems/TYPE.fs/Contents/Resources/TYPE.util -s rdisk21s10
No "/dev", -s to set new random UUID
- [ ] ADD Only auto unmount for copy not scan ?? maybe not
- [ ] ADD Save the ddrecue work summaries for each run so that progress can be re-examined.
- [ ] ADD Input a list of files to copy (source).
- [ ] ADD Option to remove metadata by <label>
- [ ] ADD Comsistency checks for volume names and helper metadata
- [ ] XXX fsck robustness assistance for corrupted volumes
- [ ] ADD GPT / MBR / table recovery
- [ ] ADD Partition superblock recovery
- [ ] XXX Fix src/dst relative file path naming to be per CWD not the label folder
- [ ] XXX Devices must be /dev qualified although this could be inferred
- [ ] XXX Verify Label tolerates whitespace or disallow.
- [ ] ADD selectable rate limit for -P
- [ ] ADD zap preview and confirmation
- [ ] ADD prettify the output of -Z and save it in a log
- [ ] ADD a summary of unreadable blocks in output of -Z, inc failed retry
- [ ] ADD improve signal handling for suspend / resume / abort of helper. currently ^C doesn't work after ^Z
- [x] XXX indentical source / dest check needs to cosnider different paths to same resource
- [x] XXX -s Slow reads block spread for best coverage.
- [x] XXX -p -s Adjust partition offset based on device specified
- [x] ADD rate log reporting for slow areas and related files
- [x] ADD check for map match to source / desk

**Documentation**

- [ ] XXX After cloning a drive or partition, the duplicates are distinguished only be /dev/ entry. The /dev/ entries for the partitions are likely to be reenumerated if the drive is disconnected (e.g, USB) and the drive entry may be as other devices come and go. When mounting remove the fstab entry only if it includes the /dev/ entry as well as the UUID. 
- [ ] XXX Explain the importance of unmount.
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
- [ ] ADD -p -z checks for unmanagebly large numbers of problem blocks in the map
- [ ] XXX For -p -s Figure out a way to look up target device from map file, when input/output devices and Label could include whitespace. Anchor matches using "/dev/".
- [x] ADD copy destination overwrite comnfirmation

**Linux & Filesystem Support**

- [ ] ADD Linux ddrutility support to full partition / drive copy for NTFS
- [ ] XXX Test -m -u -c -p -s -z Z on Linux
- [ ] ADD ext2,3,4 file lookup and fsck
- [ ] ADD FAT, NTFS file lookup and fsck
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

**GNU ddrescue Manual**
https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html

**macOS diskutil**
https://ss64.com/mac/diskutil.html

**dd(1)**
https://man7.org/linux/man-pages/man1/dd.1.html

**ddrutility**
https://sourceforge.net/p/ddrutility/wiki/Home/

