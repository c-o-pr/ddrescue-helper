# DDRESCUE-HELPER (DDH)

GNU ddrescue is an indispensible tool for copying storage devices (drives, paritions, or files) in a way that gracefully accomodates read errors and allows as much data as possible to be recovered from the source.

A side effect of running ddrescue is the creation of two kinds of metadata for the copy source:
- Map of areas with read errors and their extent
- Read rate log

`ddrescue-helper.sh` is Mac-oriented (for now) helper script (bash) that makes running ddrewscue easier by assisting with:
- Unmount, mount and fsck of devices
- Copying or scanning devices or files

It also applies ddrescue metadata to:
- Report files affected by errors or slow reads (for macOS HFS+ volumes),
- Zap sectors in error regions to try to trigger a spinning drive to re-allocate.

This helper is currently macOS and HFS+ volume oriented. But is written to be extended to other file systems and Linux. 

# BACKGROUND AND PURPOSE

The idea of for this script came about from dealing with media errors occuring during local backups of spinning drives containing single HFS+ data volumes, and trying to adapt to these errors and continue to use problematic drives by setting files that cover the errors. This worked until I ran into a situation where a media error affected volume metadata (inodes and journal) resulting the volume to become inaccessible. Working with the volume caused the system to hang and eventually crash.

As spinning drives fill up and age they become prone to bad regions. A common way of dealing with read errors is with backups and drive replacement.

While I prefer to replace a drive with any errors, for reasons of frugality I've wanted to keep using drives affected by very small number of bad blocks.

Coping with bad regions is a drive, file-system and data specific chore. With a range of parameters:

A) Knowing what data (e.g., files) are affected by read errors.

B) Recovering as much data as possible when no baackup exists.

C) Preventing re-use of bad drive regions.

D) Triggering a drive to re-allocate bad blocks.

E) Checking and repairing filesystem metadata to recover from corruption associated with bad blocks.

`ddrescue-helper.sh` assists as follows:

Simplifies operating ddrescue, by hiding standard options and keeping ddrescue metadata in a named folder. 

Superficially checks that existing map meta-data agrees with the specificed source and destination.

Includes copying drive-to-drive, drive-to-image (file), or file-to-file. 
When recovery of a file from backup isn't possible, for some files, like video, a small error region may be tolerable compared to losing the whole file. Copying file-to-file can recover the bulk of the file, whereas an OS copy will give up/

Scanning a drive (copying to /dev/null) creates the ddrescue "map" read errors and a read-rate log for slow areas without needing a copy destination.

Copies and scans can be stopped with ^C and restarted to continue.

For HFS+ volumes, use error map or rate-log to generate a report of affected files.

Persistently unmount volumes on a drive to ensures that a full drive copy or partiion isn't changed by the OS while the copy is running.

The bad blocks in the error map can be zapped to trigger the drive to re-allocate them. This can allow a corrupt filesystem to be repaired and regain access to the volume contents.

# IS CONTINUTUNG TO USE A DRIVE WITH MEDIA ERRORS SANE?

My expeirence is that large (4TB+) commodities spinning hard drives have unreliable areas that only get exposed when the drive is used very close to full for a long time. I will make a wild-ass guess that the drive makers solve a binning problem by tolerating a spread of defects in shipped product and deferring the exposure of these defects for as long as possible. The gambit is that customers won't become aware of the problem areas until the drive is well out of warranty and so old that accountability for failure is irrelevant. The implication of this wild assessment is that a well-used drive can be expected to suffer from some errors when heavily used, but still has life it in if you can find a way to deal with the problem areas. For example, one way to work around bad spots is to set-aside large files that cover them. Another is to encourage the drive to re-allocate bad sectors.

By running a scan over an entire drive, such defects can be accomodated by setting aside affected files and zapping bad-blocks to re-allocate according to the drives spare provisioning.

# WARNINGS

THE WISE DATA HOARDER WILL HAVE GOOD BACKUPS AND SIMPLY REPLACE A PROBLEM DRIVE. BUT THE FRUGAL OR BEREFT MAY HAVE NEED TO WORK WITH CRANKY DEVICES AT HAND.

THIS SCRIPT HAS BEEN CODED WITH CARE, BUT UNEXPECTED BEHAVIORS ARE POSSIBLE. BASH IS PESKY BECAUSE IT RELIES HEAVILY ON TEXT SUBSTITUTION.

# USAGE SUMMARY

There are three modes of operation:

1. Unount, mount, and fsck a drive or partition.

`ddrescue_helper.sh -m | -u | -f <device>`
 
Unmount/mount includes updating /etc/fstab (vifs on Mac) to prevent auto-mount. This makes a device ready to be copied without interference from the auto-mount capabilities of the OS.

-f looks up the volume type of device and runs the appropriate form of fsck

2. Scan, copy using ddrescue.

`ddrescue_helper.sh -c [-N] <label> <deivce> /dev/null`
`ddrescue_helper.sh -c [-N] <label> <deivce> <device>`
`ddrescue_helper.sh -c [-N] <label> <deivce> <file>`
`ddrescue_helper.sh -c [-N] <label> <file> <file>`

- Scan a drive or partition generating the block.
- Copy a drive or partition to another device.
- Image a drive or partition to a file.
- Copy a file to another file.

Errors are tolerated and as much data as possible is copied.

Generates a read map of blocks listing errors and a rate log which indicates device regions that experienced an IO slowdown. The map and rate log are stored in a folder named <label>

XXX If files are relative paths, they located relative to the contents of the <label> folder created by this helper. E.g., a simple filename for destination will place it in the folder named by <label>.
  
3. `ddrescue_helper.sh -p | -s | -z | -Z <label> <device>`

Use the block map generated by copy to print a list of files affected by read errors (HFS+ only) and zap blocks in areas affected by errors to nudge the drive to reallocate these areas. This is destructive to those blocks, but it can allow recovery of space from large media, and can enable fsck to repair a volume that was stuck at a read timeout.

This helper is macOS / HFS+ centric, but the script is made in a way to let  support be added for Linux and other filesystems.

# TODOs

**Usability**

- [ ] XXX Fixed relative file path naming to be per CWD not the label folder.
- [ ] ADD Only auto unmount for copy not scan ?? maybe not
- [ ] ADD Save the ddrecue work summaries for each run so that progress can be re-examined.
- [ ] ADD Input a list of files to copy (source).
- [ ] ADD Option to remove metadata by <label>
- [ ] ADD Comsistency checks for volume names and helper metadata
- [ ] XXX fsck robustness assistance for corrupted volumes
- [ ] ADD GPT / MBR / table recovery
- [ ] ADD Partition superblock recovery

- [ ] ADD selectale rate limit for -P
- [ ] ADD zap preview and confirmation

- [ ] XXX Devices must be /dev qualified although this could be inferred
- [ ] XXX Verify Label tolerates whitespace or disallow.

- [ ] ADD prettify the output of -Z and save it in a log
- [ ] ADD a summary of unreadble blocks in output of -Z, inc failed retry
- [ ] ADD improve signal handling for suspend / resume / abort of helpe. currently ^C doesn't work after ^Z

- [x] XXX -s Slow reads block spread for best coverage.
- [x] XXX -p -s Adjust partition offset based on device specified
- [x] ADD rate log reporting for slow areas and related files
- [x] ADD check for map match to source / desk

**Documentation**

- [ ] ADD Explanation of the ESP
- [ ] ADD basics of ddrescue, and device specification, inc. hazards
- [ ] XXX Device id in OS may change between runs (doc)
- [ ] XXX Encrypted drives not considered (doc)
- [ ] XXX -u works for device with intact accessible partition volume metadata but drive errors on metadata may cause a lockup before processing. Cover this in the usage notes

**Robustness**

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

