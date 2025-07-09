#!/bin/bash

# WIC Editor - WIC Image Modification Tool
# Copyright (C) 2025 Dynamic Devices Ltd
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Repository: https://github.com/DynamicDevices/wic-editor
# 
# This script unpacks WIC images, adds custom files, and repackages them
# Designed for embedded Linux development, specifically tested with NXP i.MX8MM EVK

set -e  # Exit on any error

# Configuration
ORIGINAL_WIC=""
CUSTOM_FILES_DIR="custom_files"
OUTPUT_WIC=""
WORK_DIR="wic_work"
MOUNT_DIR="wic_mount"
INPUT_COMPRESSED=false
FORCE_OVERWRITE=false
INTERACTIVE=true

# Function to display usage
usage() {
    echo "Usage: $0 -i <input_wic[.gz]> -o <output_wic[.gz]> [-d <custom_files_dir>] [-f] [-y]"
    echo "  -i: Input WIC image file (compressed .wic.gz or uncompressed .wic)"
    echo "  -o: Output WIC image file (compressed .wic.gz or uncompressed .wic)"
    echo "  -d: Directory containing custom files to add (default: custom_files)"
    echo "  -f: Force overwrite existing files without prompting"
    echo "  -y: Answer 'yes' to all prompts (non-interactive mode)"
    echo "  -h: Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -i rootfs.wic.gz -o rootfs_modified.wic.gz -d my_custom_files"
    echo "  $0 -i imx-image-full-imx8mmevk.wic -o imx-image-full-imx8mmevk-modified.wic -f"
    echo "  $0 -i rootfs.wic -o rootfs_modified.wic -d custom_files -y"
    exit 1
}

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$WORK_DIR/$MOUNT_DIR" 2>/dev/null; then
        echo "Unmounting filesystem..."
        sudo umount "$WORK_DIR/$MOUNT_DIR" || true
    fi
    
    # Detach loop device if attached
    if [ -n "$LOOP_DEVICE" ] && [ -e "$LOOP_DEVICE" ]; then
        echo "Detaching loop device $LOOP_DEVICE..."
        sudo losetup -d "$LOOP_DEVICE" || true
    fi
    
    # Clean up work directory
    if [ -d "$WORK_DIR" ]; then
        echo "Removing work directory..."
        rm -rf "$WORK_DIR"
    fi
}

# Function to ask user for confirmation
ask_confirmation() {
    local message="$1"
    local default="$2"  # y or n
    
    if [ "$INTERACTIVE" = false ]; then
        echo "$message [auto-answering: y]"
        return 0
    fi
    
    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " response
        case "$response" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -p "$message [y/N]: " response
        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Function to handle file conflicts
handle_file_conflict() {
    local src_file="$1"
    local dst_file="$2"
    local relative_path="$3"
    
    echo "File conflict detected: $relative_path"
    echo "  Existing file: $dst_file"
    echo "  New file: $src_file"
    
    # Show file information
    echo "  Existing file info:"
    ls -la "$dst_file" 2>/dev/null || echo "    (file info unavailable)"
    echo "  New file info:"
    ls -la "$src_file" 2>/dev/null || echo "    (file info unavailable)"
    
    if [ "$FORCE_OVERWRITE" = true ]; then
        echo "  Action: Overwriting (forced)"
        return 0
    fi
    
    echo "  Options:"
    echo "    1) Overwrite existing file"
    echo "    2) Keep existing file (skip)"
    echo "    3) Show file differences"
    echo "    4) Abort operation"
    
    while true; do
        if [ "$INTERACTIVE" = false ]; then
            echo "  Auto-selecting: Overwrite existing file"
            return 0
        fi
        
        read -p "  Choose option [1-4]: " choice
        case "$choice" in
            1) 
                echo "  Action: Overwriting existing file"
                return 0
                ;;
            2)
                echo "  Action: Keeping existing file"
                return 1
                ;;
            3)
                echo "  File differences:"
                if command -v diff &> /dev/null; then
                    diff -u "$dst_file" "$src_file" 2>/dev/null || echo "    (files are binary or diff unavailable)"
                else
                    echo "    (diff command not available)"
                fi
                echo ""
                ;;
            4)
                echo "  Aborting operation"
                exit 1
                ;;
            *)
                echo "  Invalid option. Please choose 1-4."
                ;;
        esac
    done
}

# Function to copy files with conflict handling
copy_files_with_conflict_handling() {
    local src_dir="$1"
    local dst_dir="$2"
    local conflicts_found=false
    local files_copied=0
    local files_skipped=0
    
    echo "Analysing files for conflicts..."
    
    # Find all files in source directory
    while IFS= read -r -d '' src_file; do
        # Get relative path from source directory
        relative_path="${src_file#$src_dir/}"
        dst_file="$dst_dir/$relative_path"
        
        # Check if destination file exists
        if [ -f "$dst_file" ]; then
            conflicts_found=true
            if handle_file_conflict "$src_file" "$dst_file" "$relative_path"; then
                # User chose to overwrite
                echo "  Copying: $relative_path (overwrite)"
                sudo cp -p "$src_file" "$dst_file"
                ((files_copied++))
            else
                # User chose to skip
                echo "  Skipping: $relative_path (keeping existing)"
                ((files_skipped++))
            fi
        else
            # Create directory if it doesn't exist
            dst_dir_path=$(dirname "$dst_file")
            if [ ! -d "$dst_dir_path" ]; then
                sudo mkdir -p "$dst_dir_path"
            fi
            
            # Copy new file
            echo "  Copying: $relative_path (new file)"
            sudo cp -p "$src_file" "$dst_file"
            ((files_copied++))
        fi
    done < <(find "$src_dir" -type f -print0)
    
    echo ""
    echo "File operation summary:"
    echo "  Files copied: $files_copied"
    echo "  Files skipped: $files_skipped"
    
    if [ "$conflicts_found" = false ]; then
        echo "  No file conflicts detected - all files were new"
    fi
}

# Parse command line arguments
while getopts "i:o:d:h" opt; do
    case $opt in
        i) ORIGINAL_WIC="$OPTARG" ;;
        o) OUTPUT_WIC="$OPTARG" ;;
        d) CUSTOM_FILES_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$ORIGINAL_WIC" ] || [ -z "$OUTPUT_WIC" ]; then
    echo "Error: Input and output files are required"
    usage
fi

# Check if input file exists
if [ ! -f "$ORIGINAL_WIC" ]; then
    echo "Error: Input file '$ORIGINAL_WIC' not found"
    exit 1
fi

# Check if input is compressed
if [[ "$ORIGINAL_WIC" == *.gz ]]; then
    INPUT_COMPRESSED=true
    echo "Detected compressed input file"
else
    INPUT_COMPRESSED=false
    echo "Detected uncompressed input file"
fi

# Determine output compression
OUTPUT_COMPRESSED=false
if [[ "$OUTPUT_WIC" == *.gz ]]; then
    OUTPUT_COMPRESSED=true
fi

# Check if custom files directory exists
if [ ! -d "$CUSTOM_FILES_DIR" ]; then
    echo "Error: Custom files directory '$CUSTOM_FILES_DIR' not found"
    exit 1
fi

# Check for required tools
for tool in gunzip gzip losetup parted; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Required tool '$tool' not found"
        exit 1
    fi
done

echo "Starting WIC Editor process..."
echo "Input: $ORIGINAL_WIC"
echo "Output: $OUTPUT_WIC"
echo "Custom files: $CUSTOM_FILES_DIR"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Step 1: Prepare the WIC image for processing
echo "Preparing WIC image..."
if [ "$INPUT_COMPRESSED" = true ]; then
    echo "Decompressing WIC image..."
    gunzip -c "../$ORIGINAL_WIC" > working.wic
else
    echo "Copying uncompressed WIC image..."
    cp "../$ORIGINAL_WIC" working.wic
fi

# Step 2: Analyse the WIC image partitions
echo "Analysing WIC image partitions..."
parted -s working.wic print

# Step 3: Set up loop device for the WIC image
echo "Setting up loop device..."
LOOP_DEVICE=$(sudo losetup -f --show working.wic)
echo "Loop device: $LOOP_DEVICE"

# Step 4: Probe partitions
echo "Probing partitions..."
sudo partprobe "$LOOP_DEVICE"

# Step 5: Find the root filesystem partition
# Typically the largest partition or the one with ext4 filesystem
echo "Finding root filesystem partition..."
ROOT_PARTITION=""
LARGEST_SIZE=0

# Check each partition
for part in ${LOOP_DEVICE}p*; do
    if [ -e "$part" ]; then
        # Get filesystem type
        FS_TYPE=$(sudo blkid -o value -s TYPE "$part" 2>/dev/null || echo "unknown")
        
        # Get partition size
        SIZE=$(sudo blockdev --getsize64 "$part" 2>/dev/null || echo "0")
        
        echo "Partition: $part, Type: $FS_TYPE, Size: $SIZE bytes"
        
        # Look for ext4 filesystem (common for root partition)
        if [ "$FS_TYPE" = "ext4" ] && [ "$SIZE" -gt "$LARGEST_SIZE" ]; then
            ROOT_PARTITION="$part"
            LARGEST_SIZE="$SIZE"
        fi
    fi
done

if [ -z "$ROOT_PARTITION" ]; then
    echo "Error: Could not find root filesystem partition"
    exit 1
fi

echo "Root filesystem partition: $ROOT_PARTITION"

# Step 6: Create mount point and mount the root partition
echo "Creating mount point and mounting root partition..."
mkdir -p "$MOUNT_DIR"
sudo mount "$ROOT_PARTITION" "$MOUNT_DIR"

# Step 7: Add custom files to the root filesystem
echo "Adding custom files to root filesystem..."
if [ -d "../$CUSTOM_FILES_DIR" ]; then
    # Use the new conflict handling function
    copy_files_with_conflict_handling "../$CUSTOM_FILES_DIR" "$MOUNT_DIR"
else
    echo "Warning: Custom files directory '../$CUSTOM_FILES_DIR' is empty or doesn't exist"
fi

# Step 8: Sync and unmount
echo "Syncing filesystem..."
sudo sync

echo "Unmounting filesystem..."
sudo umount "$MOUNT_DIR"

# Step 9: Detach loop device
echo "Detaching loop device..."
sudo losetup -d "$LOOP_DEVICE"
LOOP_DEVICE=""  # Clear variable to prevent cleanup from trying again

# Step 10: Create the final output image
echo "Creating final output image..."
if [ "$OUTPUT_COMPRESSED" = true ]; then
    echo "Compressing modified WIC image..."
    gzip -c working.wic > "../$OUTPUT_WIC"
else
    echo "Copying uncompressed WIC image..."
    cp working.wic "../$OUTPUT_WIC"
fi

# Step 11: Cleanup
cd ..
rm -rf "$WORK_DIR"

echo "WIC Editor process complete!"
echo "Repository: https://github.com/DynamicDevices/wic-editor"
echo "Modified image saved as: $OUTPUT_WIC"
echo ""
echo "You can now use this modified image with the uuu tool."
echo "For NXP i.MX8MM EVK, update your uuu script to use the new image:"
echo "  FB: flash -raw2sparse all $OUTPUT_WIC"

# Show file sizes for comparison
if [ -f "$ORIGINAL_WIC" ] && [ -f "$OUTPUT_WIC" ]; then
    echo ""
    echo "File size comparison:"
    echo "Original: $(du -h "$ORIGINAL_WIC" | cut -f1)"
    echo "Modified: $(du -h "$OUTPUT_WIC" | cut -f1)"
fi