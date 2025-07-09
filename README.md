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
- **Automatic partition detection**: Finds and mounts the root filesystem partition automatically
- **Intelligent file conflict handling**: Detects and manages file overwrites with multiple resolution options
- **Safe operation**: Uses loop devices for safe image manipulation
- **Permission preservation**: Maintains file permissions and directory structure
- **Interactive and automated modes**: Supports both manual review and automated deployment
- **Error handling**: Comprehensive error checking and automatic cleanup
- **UUU integration**: Optimised for NXP UUU flashing workflow
- **Detailed reporting**: Shows exactly what files were added, modified, or skipped

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
./wic-editor.sh -i <input_wic[.gz]> -o <output_wic[.gz]> [-d <custom_files_dir>] [-f] [-y]
```

### Options
- `-i`: Input WIC image file (compressed `.wic.gz` or uncompressed `.wic`)
- `-o`: Output WIC image file (compressed `.wic.gz` or uncompressed `.wic`)
- `-d`: Directory containing custom files to add (default: `custom_files`)
- `-f`: Force overwrite existing files without prompting
- `-y`: Answer 'yes' to all prompts (non-interactive mode)
- `-h`: Show help message

### Examples

#### For NXP i.MX8MM EVK (UUU workflow)
```bash
# Typical usage with uncompressed WIC image
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic

# With custom files directory
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic -d my_custom_files

# Force overwrite without prompting
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic -f

# Non-interactive mode (answer 'yes' to all prompts)
./wic-editor.sh -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic -y
```

#### With compressed images
```bash
# Compressed to compressed
./wic-editor.sh -i rootfs.wic.gz -o rootfs_modified.wic.gz

# Compressed to uncompressed with force overwrite
./wic-editor.sh -i rootfs.wic.gz -o rootfs_modified.wic -f

# Uncompressed to compressed in non-interactive mode
./wic-editor.sh -i rootfs.wic -o rootfs_modified.wic.gz -y
```

#### File Conflict Handling
```bash
# Interactive mode (default) - prompts for each file conflict
./wic-editor.sh -i input.wic -o output.wic

# Force overwrite all conflicting files
./wic-editor.sh -i input.wic -o output.wic -f

# Non-interactive mode - automatically overwrites conflicting files
./wic-editor.sh -i input.wic -o output.wic -y

# Combine force and non-interactive for fully automated operation
./wic-editor.sh -i input.wic -o output.wic -f -y
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
5. **Partition detection**: Automatically finds root filesystem partition (largest ext4 partition)
6. **Filesystem mounting**: Mounts root partition for file operations
7. **File conflict detection**: Scans for existing files that would be overwritten
8. **File addition**: Copies custom files with conflict resolution options
9. **Cleanup and packaging**: Unmounts filesystem, detaches loop device, creates output image
10. **Compression**: Applies compression if output filename ends with `.gz`

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

### Adding Configuration Files (with Overwrite Handling)
```bash
# Add configuration files to /etc (will prompt for conflicts)
mkdir -p custom_files/etc
cp my_config.conf custom_files/etc/

# Force overwrite any existing config files
./wic-editor.sh -i input.wic -o output.wic -f
```

### Replacing System Files
```bash
# Replace existing system files (e.g., hostname, hosts)
mkdir -p custom_files/etc
echo "my-device-name" > custom_files/etc/hostname
echo "127.0.0.1 my-device-name" >> custom_files/etc/hosts

# Use interactive mode to review conflicts
./wic-editor.sh -i input.wic -o output.wic
```

### Installing Custom Applications
```bash
# Add application to /opt (typically no conflicts)
mkdir -p custom_files/opt/my_app
cp -r my_application/* custom_files/opt/my_app/

# Add application with potential system integration
mkdir -p custom_files/etc/systemd/system
cp my_app.service custom_files/etc/systemd/system/

# Use force mode for system integration files
./wic-editor.sh -i input.wic -o output.wic -f
```

### Modifying Existing Services
```bash
# Modify existing systemd service
mkdir -p custom_files/etc/systemd/system
cp modified_service.service custom_files/etc/systemd/system/existing_service.service

# Review changes interactively
./wic-editor.sh -i input.wic -o output.wic
# When prompted, choose option 3 to see differences before deciding
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