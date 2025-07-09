# WIC Editor

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![GitHub release](https://img.shields.io/github/release/DynamicDevices/wic-editor.svg)](https://github.com/DynamicDevices/wic-editor/releases)
[![GitHub issues](https://img.shields.io/github/issues/DynamicDevices/wic-editor.svg)](https://github.com/DynamicDevices/wic-editor/issues)
[![GitHub stars](https://img.shields.io/github/stars/DynamicDevices/wic-editor.svg)](https://github.com/DynamicDevices/wic-editor/stargazers)

**Repository**: https://github.com/DynamicDevices/wic-editor

A powerful tool for modifying WIC (Windows Imaging Component) images used in embedded Linux development. Originally designed for NXP i.MX8MM EVK boards using Yocto Project builds, but compatible with any WIC-based embedded Linux system.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [File Conflict Handling](#file-conflict-handling)
- [Common Use Cases](#common-use-cases)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## Overview

This script allows you to unpack a WIC image (compressed or uncompressed), add custom files to the root filesystem, and repackage it for flashing with tools like UUU (Universal Update Utility).

## Features

- **Flexible input/output**: Handles both compressed (`.wic.gz`) and uncompressed (`.wic`) images
- **Advanced partition detection**: Multiple methods to identify and select target partitions
- **Intelligent file conflict handling**: Detects and manages file overwrites with multiple resolution options
- **File deletion capabilities**: Remove unwanted files before adding new ones
- **Safe operation**: Uses loop devices for safe image manipulation
- **Permission preservation**: Maintains file permissions and directory structure
- **Interactive and automated modes**: Supports both manual review and automated deployment
- **Comprehensive partition analysis**: Detailed information about all partitions in WIC images
- **Error handling**: Comprehensive error checking and automatic cleanup
- **UUU integration**: Optimised for NXP UUU flashing workflow
- **Detailed reporting**: Shows exactly what files were added, modified, or deleted

## Requirements

### System Requirements
- Linux-based operating system
- `sudo` privileges (required for mounting filesystems)
- Sufficient disk space (approximately 3x the size of your WIC image)

### Required Tools
The following tools must be installed on your system:
- `gunzip` / `gzip` (usually part of gzip package)
- `losetup` (usually part of util-linux package)
- `parted` (disk partitioning tool)
- `mount` / `umount` (filesystem mounting tools)
- `blkid` (block device identification tool)

### Installation on Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install gzip util-linux parted mount
```

### Installation on CentOS/RHEL/Fedora
```bash
# CentOS/RHEL
sudo yum install gzip util-linux parted

# Fedora
sudo dnf install gzip util-linux parted
```

## Usage

### Basic Syntax
```bash
./wic-editor.sh -i <input_wic[.gz]> -o <output_wic[.gz]> [-d <custom_files_dir>] [-p <partition>] [-m <mode>] [-r <files_to_delete>] [-f] [-y]
```

### Options
- `-i`: Input WIC image file (compressed `.wic.gz` or uncompressed `.wic`)
- `-o`: Output WIC image file (compressed `.wic.gz` or uncompressed `.wic`)
- `-d`: Directory containing custom files to add (default: `custom_files`)
- `-p`: Target partition (number, label, or 'list' to show available partitions)
- `-m`: Partition selection mode: `auto`, `manual`, `largest`, `label`, `filesystem`
- `-r`: Comma-separated list of files/directories to delete from target partition
- `-f`: Force overwrite existing files without prompting
- `-y`: Answer 'yes' to all prompts (non-interactive mode)
- `-h`: Show help message

### Partition Selection Modes
- **`auto`** (default): Find largest ext4 partition
- **`manual`**: Interactively select partition
- **`largest`**: Select largest partition regardless of filesystem
- **`label`**: Select partition by label (use with `-p`)
- **`filesystem`**: Select partition by filesystem type (use with `-p`)

### Examples

### Examples

#### Getting Started with Unknown WIC Images
```bash
# First, list all partitions to understand the structure
./wic-editor.sh -i unknown-image.wic -p list

# Sample output shows:
# Partition 1: boot (FAT32, 100MB)
# Partition 2: rootfs (ext4, 2GB) 
# Partition 3: data (ext4, 1GB)
```

#### Basic Usage
```bash
# Auto-detect target partition (works for most images)
./wic-editor.sh -i input.wic -o output.wic

# With custom files directory
./wic-editor.sh -i input.wic -o output.wic -d my_custom_files
```

#### Partition Selection
```bash
# Select specific partition by number
./wic-editor.sh -i input.wic -o output.wic -p 2

# Interactive partition selection
./wic-editor.sh -i input.wic -o output.wic -m manual

# Select by partition label
./wic-editor.sh -i input.wic -o output.wic -m label -p rootfs

# Select by filesystem type
./wic-editor.sh -i input.wic -o output.wic -m filesystem -p ext4

# Select largest partition (any filesystem)
./wic-editor.sh -i input.wic -o output.wic -m largest
```

#### File Deletion
```bash
# Delete specific files before adding new ones
./wic-editor.sh -i input.wic -o output.wic -r "/etc/old_config.conf,/var/log/debug.log"

# Delete with wildcards
./wic-editor.sh -i input.wic -o output.wic -r "/tmp/*,/var/cache/*"

# Delete directories
./wic-editor.sh -i input.wic -o output.wic -r "/opt/old_app"

# Combined deletion and addition
./wic-editor.sh -i input.wic -o output.wic -r "/etc/hostname,/var/log/*" -d new_files
```

#### For NXP i.MX8MM EVK (UUU workflow)
```bash
# Auto-detect (typical usage)
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic

# List partitions first to understand structure
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -p list

# Select specific partition
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic -p 2

# Clean up old files and add new ones
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic \
  -r "/etc/hostname,/var/log/*" -d my_custom_files -f
```

#### With compressed images
```bash
# Compressed to compressed
./wic-editor.sh -i rootfs.wic.gz -o rootfs_modified.wic.gz -p 2

# Compressed to uncompressed with partition selection
./wic-editor.sh -i rootfs.wic.gz -o rootfs_modified.wic -m manual

# Uncompressed to compressed with file deletion
./wic-editor.sh -i rootfs.wic -o rootfs_modified.wic.gz -r "/tmp/*"
```

#### File Conflict and Automation
```bash
# Interactive mode (default) - prompts for each file conflict
./wic-editor.sh -i input.wic -o output.wic -p 2

# Force overwrite all conflicting files
./wic-editor.sh -i input.wic -o output.wic -p 2 -f

# Non-interactive mode - automatically overwrites conflicting files
./wic-editor.sh -i input.wic -o output.wic -p 2 -y

# Fully automated operation
./wic-editor.sh -i input.wic -o output.wic -p 2 -f -y
```

## Setup Instructions

### 1. Download and Setup Script
```bash
# Make the script executable
chmod +x wic_modify.sh
```

### 2. Prepare Custom Files
Create a directory structure that mirrors where you want files to be placed in the root filesystem:

```bash
mkdir custom_files
```

#### Example directory structure:
```
custom_files/
├── etc/
│   ├── my_config.conf
│   └── systemd/
│       └── system/
│           └── my_service.service
├── usr/
│   └── local/
│       └── bin/
│           └── my_script.sh
├── home/
│   └── root/
│       └── my_file.txt
└── opt/
    └── my_application/
        ├── app_binary
        └── config/
            └── app.conf
```

### 3. Run WIC Editor
```bash
# Interactive mode (default) - prompts for file conflicts
./wic-editor.sh -i your_image.wic -o your_image_modified.wic -d custom_files

# Automated mode - overwrites all conflicts
./wic-editor.sh -i your_image.wic -o your_image_modified.wic -d custom_files -f -y

# Force overwrite mode - overwrites conflicts but still shows progress
./wic-editor.sh -i your_image.wic -o your_image_modified.wic -d custom_files -f
```

### 4. Update UUU Script
If using with NXP UUU tool, update your UUU script file (e.g., `uuu.auto-imx8mmevk`):

```bash
# Change this line:
FB: flash -raw2sparse all imx-image-full-imx8mmevk.wic

# To:
FB: flash -raw2sparse all imx-image-full-imx8mmevk-modified.wic
```

## Script Workflow

1. **Input validation**: Checks if input files exist and required tools are available
2. **Image preparation**: Decompresses input if needed, creates working copy
3. **Partition analysis**: Uses `parted` to examine WIC image structure
4. **Loop device setup**: Creates loop device for safe image manipulation
5. **Partition detection/selection**: Automatically finds or interactively selects target partition
6. **Filesystem mounting**: Mounts target partition for file operations
7. **File deletion**: Removes specified files/directories if requested
8. **File conflict detection**: Scans for existing files that would be overwritten
9. **File addition**: Copies custom files with conflict resolution options
10. **Cleanup and packaging**: Unmounts filesystem, detaches loop device, creates output image
11. **Compression**: Applies compression if output filename ends with `.gz`

## Partition Detection and Selection

WIC Editor provides multiple ways to identify and select the target partition for modification:

### Automatic Detection (Default)
- Scans all partitions in the WIC image
- Finds the largest ext4 partition
- Assumes this is the root filesystem
- Works for 90% of embedded Linux images

### Interactive Selection
- Shows detailed information about all partitions
- Displays partition number, size, filesystem type, and label
- Allows you to choose the appropriate partition
- Confirms selection before proceeding

### Specific Selection Methods
- **By number**: Direct partition number specification
- **By label**: Searches for partition with specific label
- **By filesystem**: Finds first partition with specified filesystem type
- **Largest**: Selects largest partition regardless of filesystem

### Partition Information Display
When listing partitions, you'll see:
```
Partition 1:
  Device: /dev/loop0p1
  Size: 100MB
  Filesystem: vfat
  Label: boot
  UUID: 1234-5678

Partition 2:
  Device: /dev/loop0p2
  Size: 2GB
  Filesystem: ext4
  Label: rootfs
  UUID: abcd-ef12-3456-7890
```

## File Conflict Handling

The script intelligently handles file conflicts when custom files would overwrite existing files in the WIC image:

### Interactive Mode (Default)
When a file conflict is detected, the script will:
1. Show information about both files (existing and new)
2. Present options:
   - **Overwrite existing file**: Replace with your custom file
   - **Keep existing file**: Skip copying your custom file
   - **Show file differences**: Display diff between files (if available)
   - **Abort operation**: Stop the entire process

### Non-Interactive Modes
- **Force mode (`-f`)**: Automatically overwrites all conflicting files
- **Non-interactive mode (`-y`)**: Automatically answers 'yes' to all prompts
- **Combined (`-f -y`)**: Fully automated operation

### Conflict Resolution Examples

#### Interactive Session
```
File conflict detected: etc/hostname
  Existing file: /mnt/wic_mount/etc/hostname
  New file: ../custom_files/etc/hostname
  Existing file info:
    -rw-r--r-- 1 root root 12 Jan 15 10:30 /mnt/wic_mount/etc/hostname
  New file info:
    -rw-r--r-- 1 user user 15 Jan 20 14:45 ../custom_files/etc/hostname
  Options:
    1) Overwrite existing file
    2) Keep existing file (skip)
    3) Show file differences
    4) Abort operation
  Choose option [1-4]: 3
  File differences:
    --- /mnt/wic_mount/etc/hostname
    +++ ../custom_files/etc/hostname
    @@ -1 +1 @@
    -imx8mmevk
    +my-custom-hostname
  Choose option [1-4]: 1
  Action: Overwriting existing file
```

#### Summary Report
At the end of the operation, you'll see a summary:
```
File operation summary:
  Files copied: 15
  Files skipped: 2
```

## Common Use Cases

### Exploring Unknown WIC Images
```bash
# First step: understand the partition structure
./wic-editor.sh -i unknown-image.wic -p list

# Once you know the layout, select appropriate partition
./wic-editor.sh -i unknown-image.wic -o modified.wic -p 2
```

### System Configuration with Cleanup
```bash
# Remove old configs and add new ones
./wic-editor.sh -i system.wic -o updated.wic \
  -r "/etc/old_config.conf,/etc/deprecated/*" \
  -d new_system_configs
```

### Application Deployment
```bash
# Clean deployment: remove old app and install new version
./wic-editor.sh -i base.wic -o deployed.wic \
  -r "/opt/old_app" \
  -d new_app_files \
  -m label -p rootfs
```

### Development Workflow
```bash
# Interactive mode for careful development
./wic-editor.sh -i dev-image.wic -o test-image.wic -m manual

# Production deployment with automation
./wic-editor.sh -i prod-image.wic -o deployed.wic -p 2 -f -y
```

### Adding Startup Scripts
```bash
# Add systemd service
mkdir -p custom_files/etc/systemd/system
cp my_service.service custom_files/etc/systemd/system/
```

### Adding User Files
```bash
# Add files to root user's home directory
mkdir -p custom_files/home/root
cp my_files/* custom_files/home/root/
```

## Troubleshooting

### Permission Errors
- Ensure you have `sudo` privileges
- The script needs root access to mount filesystems

### No Root Partition Found
- Check that your WIC image contains an ext4 partition
- Verify the image isn't corrupted by testing with `parted -s your_image.wic print`

### Insufficient Disk Space
- Ensure you have at least 3x the size of your WIC image available
- Clean up temporary files in case of previous failed runs

### Custom Files Not Appearing
- Verify the directory structure in your custom files directory
- Check file permissions in the custom files directory
- Ensure the custom files directory exists and contains files
- Check the file operation summary for skipped files
- Verify you're targeting the correct partition

### Wrong Partition Selected
- Use `-p list` to see all available partitions
- Use `-m manual` for interactive selection
- Check partition labels with `-m label -p <label_name>`
- Verify filesystem type before proceeding

### Partition Not Found Errors
- Ensure partition number exists (use `-p list`)
- Check partition label spelling for label-based selection
- Verify filesystem type for filesystem-based selection

### File Deletion Issues
- Use absolute paths starting with `/` for file deletion
- Check file paths exist before deletion
- Use interactive mode to confirm deletions
- Wildcards require proper shell escaping

### File Conflicts Not Being Detected
- Ensure you're using the correct relative paths in your custom files directory
- Check that the script has permission to read both source and destination files
- Verify that the filesystem is properly mounted

### Unwanted File Overwrites
- Use interactive mode (default) to review each conflict
- Check the file operation summary to see what was overwritten
- Use the `-f` flag cautiously - it overwrites all conflicting files

### Loop Device Issues
- If script fails with loop device errors, manually clean up:
  ```bash
  sudo losetup -D  # Detach all loop devices
  ```

## Advanced Usage

### Automated Build Integration
For automated builds where you want to overwrite system files:

```bash
#!/bin/bash
# Build script example

# Build your Yocto image
bitbake my-image

# Modify the resulting WIC image with force overwrite
./wic-editor.sh -i deploy/images/imx8mmevk/my-image.wic \
                -o deploy/images/imx8mmevk/my-image-custom.wic \
                -d custom_overlay \
                -f -y

# Flash with UUU
uuu uuu.auto-imx8mmevk-custom
```

### Staged File Deployment
For complex deployments with multiple file sources:

```bash
# Stage 1: Base system modifications (force overwrite)
./wic-editor.sh -i original.wic -o stage1.wic -d base_system_changes -f

# Stage 2: Application files (interactive to review conflicts)
./wic-editor.sh -i stage1.wic -o stage2.wic -d application_files

# Stage 3: Final configuration (non-interactive)
./wic-editor.sh -i stage2.wic -o final.wic -d final_config -y
```

### Best Practices for File Conflicts

#### 1. **System Configuration Files**
When modifying system files like `/etc/hostname`, `/etc/hosts`, `/etc/fstab`:
```bash
# Use interactive mode to review changes
./wic-editor.sh -i input.wic -o output.wic

# When prompted, choose option 3 to see differences
# This helps you understand what you're changing
```

#### 2. **Service Files and Scripts**
For systemd services, init scripts, or configuration files:
```bash
# Prepare your custom files
mkdir -p custom_files/etc/systemd/system
cp my_custom.service custom_files/etc/systemd/system/

# Use interactive mode to review any existing service modifications
./wic-editor.sh -i input.wic -o output.wic
```

#### 3. **Development vs Production**
```bash
# Development: Interactive mode for careful review
./wic-editor.sh -i dev_image.wic -o dev_image_modified.wic

# Production: Automated mode for consistent deployment
./wic-editor.sh -i prod_image.wic -o prod_image_modified.wic -f -y
```

#### 4. **Backup Strategy**
```bash
# Always keep backups of critical configurations
mkdir -p backups/$(date +%Y%m%d)
cp important_configs/* backups/$(date +%Y%m%d)/

# Then proceed with modifications
./wic-editor.sh -i input.wic -o output.wic
```

## File Size Considerations

The script will display file size comparisons after completion:
- Original file size
- Modified file size
- The difference helps you understand the impact of your additions

## Security Considerations

- The script requires `sudo` privileges for mounting filesystems
- Files are copied with their original permissions
- **File overwrites**: In interactive mode, you can review each file before overwriting
- **Automated modes**: Use `-f` and `-y` flags cautiously as they can overwrite system files
- Ensure custom files don't contain sensitive information unless intended
- Validate custom files before adding them to the root filesystem
- **Backup recommendation**: Always keep a backup of your original WIC image

## Contributing

We welcome contributions to WIC Editor! Here's how you can help:

### Reporting Issues
- Use the [GitHub Issues](https://github.com/DynamicDevices/wic-editor/issues) page
- Include your system information and WIC image details
- Provide steps to reproduce the problem

### Contributing Code
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test thoroughly on your target hardware
4. Ensure compatibility with different WIC image formats
5. Add error handling for edge cases
6. Update documentation as needed
7. Commit your changes (`git commit -m 'Add some amazing feature'`)
8. Push to the branch (`git push origin feature/amazing-feature`)
9. Open a Pull Request

### Development Guidelines
- Follow existing code style and patterns
- Add comprehensive error handling
- Include appropriate comments
- Test on multiple WIC image types
- Update the README for new features

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

### Copyright

Copyright (C) 2025 Dynamic Devices Ltd

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Support

- **Documentation**: This README and inline help (`./wic-editor.sh -h`)
- **Issues**: Report bugs and request features via [GitHub Issues](https://github.com/DynamicDevices/wic-editor/issues)
- **Community**: Join discussions in the repository's Discussions section

## Acknowledgments

- Originally developed for NXP i.MX8MM EVK workflows
- Inspired by the need for safer WIC image modification
- Built for the embedded Linux and Yocto Project communities

## Version History

- **v1.0**: Initial release with basic WIC modification support
- **v1.1**: Added support for both compressed and uncompressed images
- **v1.2**: Improved error handling and cleanup procedures
- **v1.3**: Enhanced UUU integration and documentation
- **v1.4**: Added intelligent file conflict detection and resolution
- **v1.5**: Implemented interactive and automated modes for file handling
- **v1.6**: Added detailed file operation reporting and diff capabilities
- **v1.7**: Advanced partition detection with multiple selection modes
- **v1.8**: File deletion capabilities and comprehensive partition analysis