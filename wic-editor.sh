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

set -e  # Exit on any error (but we'll disable this for debugging)

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: WIC Editor requires root privileges to mount filesystems and manage loop devices"
    echo "Please run with sudo:"
    echo "  sudo $0 $*"
    exit 1
fi

# Disable exit on error for debugging
set +e

# Configuration
ORIGINAL_WIC=""
CUSTOM_FILES_DIR="custom_files"
OUTPUT_WIC=""
WORK_DIR="wic_work"
MOUNT_DIR="wic_mount"
INPUT_COMPRESSED=false
FORCE_OVERWRITE=false
INTERACTIVE=true
TARGET_PARTITION=""
PARTITION_SELECTION_MODE="auto"
DELETE_FILES=""
SHOW_HELP=false
LIST_PARTITIONS_ONLY=false

# Function to display usage
usage() {
    SHOW_HELP=true  # Set flag to prevent cleanup messages
    echo "Usage: $0 -i <input_wic[.gz]> -o <output_wic[.gz]> [-d <custom_files_dir>] [-p <partition>] [-m <mode>] [-r <files_to_delete>] [-f] [-y]"
    echo "  -i: Input WIC image file (compressed .wic.gz or uncompressed .wic)"
    echo "  -o: Output WIC image file (compressed .wic.gz or uncompressed .wic)"
    echo "  -d: Directory containing custom files to add (default: custom_files)"
    echo "  -p: Target partition (number, label, or 'list' to show available partitions)"
    echo "  -m: Partition selection mode: auto, manual, largest, label, filesystem"
    echo "  -r: Comma-separated list of files/directories to delete from target partition"
    echo "  -f: Force overwrite existing files without prompting"
    echo "  -y: Answer 'yes' to all prompts (non-interactive mode)"
    echo "  -h: Show this help message"
    echo ""
    echo "Partition Selection Modes:"
    echo "  auto     - Find largest ext4 partition (default)"
    echo "  manual   - Interactively select partition"
    echo "  largest  - Select largest partition regardless of filesystem"
    echo "  label    - Select partition by label (use with -p)"
    echo "  filesystem - Select partition by filesystem type (use with -p)"
    echo ""
    echo "Examples:"
    echo "  $0 -i rootfs.wic.gz -o rootfs_modified.wic.gz"
    echo "  $0 -i input.wic -o output.wic -p 3"
    echo "  $0 -i input.wic -o output.wic -p list"
    echo "  $0 -i input.wic -o output.wic -m manual"
    echo "  $0 -i input.wic -o output.wic -m label -p rootfs"
    echo "  $0 -i input.wic -o output.wic -r '/etc/old_config,/var/log/*'"
    exit 0
}

# Function to cleanup on exit
cleanup() {
    # Don't clean up if we're just showing help or listing partitions
    if [ "$SHOW_HELP" = true ] || [ "$LIST_PARTITIONS_ONLY" = true ]; then
        return 0
    fi
    
    echo "Cleaning up..."
    
    # Unmount if mounted (check the actual mount point)
    if [ -d "$WORK_DIR/$MOUNT_DIR" ] && mountpoint -q "$WORK_DIR/$MOUNT_DIR" 2>/dev/null; then
        echo "Unmounting filesystem..."
        sudo umount "$WORK_DIR/$MOUNT_DIR" || true
    fi
    
    # Detach loop device if attached
    if [ -n "$LOOP_DEVICE" ] && [ -e "$LOOP_DEVICE" ]; then
        echo "Detaching loop device $LOOP_DEVICE..."
        sudo losetup -d "$LOOP_DEVICE" || true
    fi
    
    # Clean up work directory completely
    if [ -d "$WORK_DIR" ]; then
        echo "Removing work directory..."
        rm -rf "$WORK_DIR"
    fi
    
    # Clean up any temporary files we might have created
    rm -f /tmp/wic_editor_count_$
}

# Function to list all partitions with detailed information
list_partitions() {
    local loop_device="$1"
    
    echo "Available partitions in WIC image:"
    echo "=================================="
    
    # Get partition information using parted
    parted -s "$loop_device" print | grep "^ *[0-9]" | while read -r line; do
        partition_num=$(echo "$line" | awk '{print $1}')
        partition_device="${loop_device}p${partition_num}"
        
        if [ -e "$partition_device" ]; then
            # Get partition size
            size=$(echo "$line" | awk '{print $4}')
            
            # Get filesystem type
            fs_type=$(blkid -o value -s TYPE "$partition_device" 2>/dev/null || echo "unknown")
            
            # Get partition label
            label=$(blkid -o value -s LABEL "$partition_device" 2>/dev/null || echo "none")
            
            # Get UUID
            uuid=$(blkid -o value -s UUID "$partition_device" 2>/dev/null || echo "none")
            
            echo "Partition $partition_num:"
            echo "  Device: $partition_device"
            echo "  Size: $size"
            echo "  Filesystem: $fs_type"
            echo "  Label: $label"
            echo "  UUID: $uuid"
            echo ""
        fi
    done
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
        read -r -p "$message [Y/n]: " response < /dev/tty
        case "$response" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -r -p "$message [y/N]: " response < /dev/tty
        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Function to select partition interactively
select_partition_interactive() {
    local loop_device="$1"
    
    list_partitions "$loop_device"
    
    echo "Which partition would you like to modify?"
    read -r -p "Enter partition number: " partition_choice < /dev/tty
    
    # Validate partition choice
    partition_device="${loop_device}p${partition_choice}"
    if [ ! -e "$partition_device" ]; then
        echo "Error: Partition $partition_choice does not exist"
        return 1
    fi
    
    # Get filesystem type for confirmation
    fs_type=$(blkid -o value -s TYPE "$partition_device" 2>/dev/null || echo "unknown")
    
    echo "Selected partition $partition_choice ($fs_type filesystem)"
    if ! ask_confirmation "Proceed with this partition?" "y"; then
        echo "Partition selection cancelled"
        return 1
    fi
    
    echo "$partition_device"
}

# Function to find partition by label
find_partition_by_label() {
    local loop_device="$1"
    local target_label="$2"
    
    # Check each partition for matching label
    for part in "${loop_device}p"*; do
        if [ -e "$part" ]; then
            label=$(blkid -o value -s LABEL "$part" 2>/dev/null || echo "")
            if [ "$label" = "$target_label" ]; then
                echo "$part"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to find partition by filesystem type
find_partition_by_filesystem() {
    local loop_device="$1"
    local target_fs="$2"
    
    # Check each partition for matching filesystem
    for part in "${loop_device}p"*; do
        if [ -e "$part" ]; then
            fs_type=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "")
            if [ "$fs_type" = "$target_fs" ]; then
                echo "$part"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to find largest partition
find_largest_partition() {
    local loop_device="$1"
    local largest_partition=""
    local largest_size=0
    
    # Check each partition
    for part in "${loop_device}p"*; do
        if [ -e "$part" ]; then
            # Get partition size in bytes
            size=$(blockdev --getsize64 "$part" 2>/dev/null || echo "0")
            
            if [ "$size" -gt "$largest_size" ]; then
                largest_partition="$part"
                largest_size="$size"
            fi
        fi
    done
    
    echo "$largest_partition"
}

# Function to select target partition based on mode
select_target_partition() {
    local loop_device="$1"
    
    case "$PARTITION_SELECTION_MODE" in
        "auto")
            # Find largest ext4 partition (current behavior)
            local ROOT_PARTITION=""
            local LARGEST_SIZE=0
            
            for part in "${loop_device}p"*; do
                if [ -e "$part" ]; then
                    # Get filesystem type
                    local FS_TYPE
                    FS_TYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null || echo "unknown")
                    
                    # Get partition size
                    local SIZE
                    SIZE=$(blockdev --getsize64 "$part" 2>/dev/null || echo "0")
                    
                    # Look for ext4 filesystem (common for root partition)
                    if [ "$FS_TYPE" = "ext4" ] && [ "$SIZE" -gt "$LARGEST_SIZE" ]; then
                        ROOT_PARTITION="$part"
                        LARGEST_SIZE="$SIZE"
                    fi
                fi
            done
            
            if [ -z "$ROOT_PARTITION" ]; then
                echo "Error: Could not find ext4 partition automatically"
                echo "Use -m manual to select partition interactively"
                return 1
            fi
            
            echo "$ROOT_PARTITION"
            ;;
            
        "manual")
            select_partition_interactive "$loop_device"
            ;;
            
        "largest")
            find_largest_partition "$loop_device"
            ;;
            
        "label")
            if [ -z "$TARGET_PARTITION" ]; then
                echo "Error: Partition label required with -p option"
                return 1
            fi
            
            local partition
            partition=$(find_partition_by_label "$loop_device" "$TARGET_PARTITION")
            if [ -z "$partition" ]; then
                echo "Error: Partition with label '$TARGET_PARTITION' not found"
                return 1
            fi
            
            echo "$partition"
            ;;
            
        "filesystem")
            if [ -z "$TARGET_PARTITION" ]; then
                echo "Error: Filesystem type required with -p option"
                return 1
            fi
            
            local partition
            partition=$(find_partition_by_filesystem "$loop_device" "$TARGET_PARTITION")
            if [ -z "$partition" ]; then
                echo "Error: Partition with filesystem '$TARGET_PARTITION' not found"
                return 1
            fi
            
            echo "$partition"
            ;;
            
        *)
            echo "Error: Invalid partition selection mode: $PARTITION_SELECTION_MODE"
            return 1
            ;;
    esac
}

# Function to delete files from target partition
delete_files_from_partition() {
    local mount_dir="$1"
    local files_to_delete="$2"
    
    if [ -z "$files_to_delete" ]; then
        return 0
    fi
    
    echo "Deleting specified files from partition..."
    
    # Split comma-separated file list
    IFS=',' read -ra DELETE_LIST <<< "$files_to_delete"
    
    local files_deleted=0
    local files_not_found=0
    
    for file_pattern in "${DELETE_LIST[@]}"; do
        # Remove leading/trailing whitespace
        file_pattern=$(echo "$file_pattern" | xargs)
        
        # Handle relative paths (add leading slash if missing)
        if [[ "$file_pattern" != /* ]]; then
            file_pattern="/$file_pattern"
        fi
        
        # Full path in mounted filesystem
        full_path="$mount_dir$file_pattern"
        
        echo "  Processing: $file_pattern"
        
        # Handle wildcards with find
        if [[ "$file_pattern" == *"*"* ]]; then
            # Use find for wildcard patterns
            base_dir=$(dirname "$full_path")
            pattern=$(basename "$file_pattern")
            
            if [ -d "$base_dir" ]; then
                # Use a temporary file to count deletions since we're in a subshell
                local temp_count_file="/tmp/wic_editor_count_$"
                echo "$files_deleted" > "$temp_count_file"
                
                find "$base_dir" -name "$pattern" -type f -print0 | while IFS= read -r -d '' found_file; do
                    relative_file=${found_file#"$mount_dir"}
                    
                    if [ "$FORCE_OVERWRITE" = true ] || ask_confirmation "Delete file: $relative_file?" "n"; then
                        rm -f "$found_file"
                        echo "    Deleted: $relative_file"
                        # Update count in temp file
                        local current_count
                        current_count=$(cat "$temp_count_file")
                        echo $((current_count + 1)) > "$temp_count_file"
                    else
                        echo "    Skipped: $relative_file"
                    fi
                done
                
                # Read back the count
                if [ -f "$temp_count_file" ]; then
                    files_deleted=$(cat "$temp_count_file")
                    rm -f "$temp_count_file"
                fi
            else
                echo "    Directory not found: $(dirname "$file_pattern")"
                ((files_not_found++))
            fi
        else
            # Handle exact file/directory paths
            if [ -f "$full_path" ]; then
                if [ "$FORCE_OVERWRITE" = true ] || ask_confirmation "Delete file: $file_pattern?" "n"; then
                    rm -f "$full_path"
                    echo "    Deleted: $file_pattern"
                    ((files_deleted++))
                else
                    echo "    Skipped: $file_pattern"
                fi
            elif [ -d "$full_path" ]; then
                if [ "$FORCE_OVERWRITE" = true ] || ask_confirmation "Delete directory: $file_pattern?" "n"; then
                    rm -rf "$full_path"
                    echo "    Deleted: $file_pattern (directory)"
                    ((files_deleted++))
                else
                    echo "    Skipped: $file_pattern (directory)"
                fi
            else
                echo "    Not found: $file_pattern"
                ((files_not_found++))
            fi
        fi
    done
    
    echo ""
    echo "File deletion summary:"
    echo "  Files deleted: $files_deleted"
    echo "  Files not found: $files_not_found"
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
        
        read -r -p "  Choose option [1-4]: " choice < /dev/tty
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
                return 1  # Return instead of exit to allow cleanup
                ;;
            "")
                echo "  No input received. Please choose 1-4."
                ;;
            *)
                echo "  Invalid option '$choice'. Please choose 1-4."
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
        relative_path="${src_file#"$src_dir"/}"
        dst_file="$dst_dir/$relative_path"
        
        # Check if destination file exists
        if [ -f "$dst_file" ]; then
            conflicts_found=true
            if handle_file_conflict "$src_file" "$dst_file" "$relative_path"; then
                # User chose to overwrite
                echo "  Copying: $relative_path (overwrite)"
                cp -p "$src_file" "$dst_file"
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
                mkdir -p "$dst_dir_path"
            fi
            
            # Copy new file
            echo "  Copying: $relative_path (new file)"
            cp -p "$src_file" "$dst_file"
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

# Set up trap for cleanup on exit and signals
trap cleanup EXIT INT TERM

# Parse command line arguments
while getopts "i:o:d:p:m:r:fyh" opt; do
    case $opt in
        i) ORIGINAL_WIC="$OPTARG" ;;
        o) OUTPUT_WIC="$OPTARG" ;;
        d) CUSTOM_FILES_DIR="$OPTARG" ;;
        p) TARGET_PARTITION="$OPTARG" ;;
        m) PARTITION_SELECTION_MODE="$OPTARG" ;;
        r) DELETE_FILES="$OPTARG" ;;
        f) FORCE_OVERWRITE=true ;;
        y) INTERACTIVE=false ;;
        h) SHOW_HELP=true; usage ;;
        *) echo "Error: Invalid option"; exit 1 ;;
    esac
done

# Special handling for partition listing
if [ "$TARGET_PARTITION" = "list" ]; then
    LIST_PARTITIONS_ONLY=true
    
    if [ -z "$ORIGINAL_WIC" ]; then
        echo "Error: Input WIC file required to list partitions"
        SHOW_HELP=true  # Set flag to prevent cleanup messages
        exit 1
    fi
    
    # Just list partitions and exit
    echo "Listing partitions in $ORIGINAL_WIC..."
    
    # Create temporary work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Prepare WIC image
    if [[ "$ORIGINAL_WIC" == *.gz ]]; then
        gunzip -c "../$ORIGINAL_WIC" > working.wic
    else
        cp "../$ORIGINAL_WIC" working.wic
    fi
    
    # Set up loop device
    LOOP_DEVICE=$(losetup -f --show working.wic)
    partprobe "$LOOP_DEVICE"
    
    # List partitions
    list_partitions "$LOOP_DEVICE"
    
    # Cleanup
    losetup -d "$LOOP_DEVICE"
    cd ..
    rm -rf "$WORK_DIR"
    
    exit 0
fi

# Handle partition number specification
if [ -n "$TARGET_PARTITION" ] && [ "$PARTITION_SELECTION_MODE" = "auto" ]; then
    # If user specified a partition number, switch to that mode
    if [[ "$TARGET_PARTITION" =~ ^[0-9]+$ ]]; then
        PARTITION_SELECTION_MODE="manual"
    else
        # Assume it's a label or filesystem type
        PARTITION_SELECTION_MODE="label"
    fi
fi

# Validate required arguments
if [ -z "$ORIGINAL_WIC" ] || [ -z "$OUTPUT_WIC" ]; then
    echo "Error: Input and output files are required"
    SHOW_HELP=true  # Set flag to prevent cleanup messages
    exit 1
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
if [ -n "$CUSTOM_FILES_DIR" ] && [ ! -d "$CUSTOM_FILES_DIR" ]; then
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
LOOP_DEVICE=$(losetup -f --show working.wic)
echo "Loop device: $LOOP_DEVICE"

# Step 4: Probe partitions
echo "Probing partitions..."
partprobe "$LOOP_DEVICE"

# Step 5: Find and select the target partition
echo "Selecting target partition..."
if [ "$PARTITION_SELECTION_MODE" = "manual" ] && [ -n "$TARGET_PARTITION" ] && [[ "$TARGET_PARTITION" =~ ^[0-9]+$ ]]; then
    # User specified a partition number directly
    ROOT_PARTITION="${LOOP_DEVICE}p${TARGET_PARTITION}"
    
    if [ ! -e "$ROOT_PARTITION" ]; then
        echo "Error: Partition $TARGET_PARTITION does not exist"
        exit 1
    fi
    
    # Get filesystem type for confirmation
    FS_TYPE=$(blkid -o value -s TYPE "$ROOT_PARTITION" 2>/dev/null || echo "unknown")
    echo "Selected partition $TARGET_PARTITION ($FS_TYPE filesystem)"
    
    if [ "$FS_TYPE" != "ext4" ] && [ "$FS_TYPE" != "ext3" ] && [ "$FS_TYPE" != "ext2" ]; then
        echo "Warning: Partition filesystem is $FS_TYPE, not ext4"
        if [ "$INTERACTIVE" = true ] && ! ask_confirmation "Continue anyway?" "n"; then
            echo "Operation cancelled"
            exit 1
        fi
    fi
else
    # Use partition selection function
    ROOT_PARTITION=$(select_target_partition "$LOOP_DEVICE")
    
    if [ -z "$ROOT_PARTITION" ]; then
        echo "Error: Could not determine target partition"
        exit 1
    fi
    
    # Get filesystem type for display
    FS_TYPE=$(blkid -o value -s TYPE "$ROOT_PARTITION" 2>/dev/null || echo "unknown")
    echo "Selected partition: $ROOT_PARTITION ($FS_TYPE filesystem)"
fi

# Step 6: Create mount point and mount the target partition
echo "Creating mount point and mounting target partition..."
mkdir -p "$WORK_DIR/$MOUNT_DIR"
mount "$ROOT_PARTITION" "$WORK_DIR/$MOUNT_DIR"
echo "Mounted $ROOT_PARTITION at $WORK_DIR/$MOUNT_DIR"

# Step 7: Delete specified files if requested
if [ -n "$DELETE_FILES" ]; then
    delete_files_from_partition "$WORK_DIR/$MOUNT_DIR" "$DELETE_FILES"
fi

# Step 8: Add custom files to the target partition
echo "Adding custom files to target partition..."
if [ -d "../$CUSTOM_FILES_DIR" ]; then
    echo "Custom files directory found: ../$CUSTOM_FILES_DIR"
    # Use the conflict handling function with full path
    if copy_files_with_conflict_handling "../$CUSTOM_FILES_DIR" "$WORK_DIR/$MOUNT_DIR"; then
        echo "File copying function returned successfully"
    else
        echo "File copying function failed"
    fi
else
    echo "Warning: Custom files directory '../$CUSTOM_FILES_DIR' is empty or doesn't exist"
fi

echo "File copying completed successfully - continuing to next step"

# Step 9: Sync and unmount
echo "Starting filesystem sync and unmount..."
sync

echo "Unmounting filesystem..."
# Use absolute path to avoid directory confusion
MOUNT_PATH="$(pwd)/$WORK_DIR/$MOUNT_DIR"
echo "Unmounting: $MOUNT_PATH"

if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
    if ! umount "$MOUNT_PATH"; then
        echo "Warning: Failed to unmount cleanly, forcing unmount..."
        umount -f "$MOUNT_PATH" || umount -l "$MOUNT_PATH" || true
    fi
else
    echo "Mount point not found or already unmounted"
fi

# Verify unmount
if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
    echo "Warning: Mount point still active after unmount attempt"
    # Try to find what's using it
    echo "Processes using the mount point:"
    lsof "$MOUNT_PATH" || true
    fuser -v "$MOUNT_PATH" || true
else
    echo "Filesystem unmounted successfully"
fi

echo "Unmount phase completed"

# Step 10: Create the output file BEFORE detaching loop device
echo "Creating final output image..."

# Change back to original directory before creating output
cd ..

# Store the full path to the output file
OUTPUT_FULL_PATH="$(pwd)/$OUTPUT_WIC"

if [ "$OUTPUT_COMPRESSED" = true ]; then
    echo "Compressing modified WIC image..."
    echo "Output file: $OUTPUT_FULL_PATH"
    gzip -c "$WORK_DIR/working.wic" > "$OUTPUT_WIC"
else
    echo "Copying uncompressed WIC image..."
    echo "Output file: $OUTPUT_FULL_PATH"
    cp "$WORK_DIR/working.wic" "$OUTPUT_WIC"
fi

# Verify output file was created
if [ -f "$OUTPUT_WIC" ]; then
    echo "Output file created successfully: $OUTPUT_WIC"
    echo "Size: $(du -h "$OUTPUT_WIC" | cut -f1)"
else
    echo "Error: Output file was not created!"
    exit 1
fi

# Step 11: Detach loop device
echo "Detaching loop device..."
echo "Current loop devices before detachment:"
losetup -l | grep "$LOOP_DEVICE" || echo "Loop device not found in losetup -l"

if ! losetup -d "$LOOP_DEVICE"; then
    echo "Warning: Failed to detach loop device cleanly, continuing..."
    echo "Loop device status after failed detachment:"
    losetup -l | grep "$LOOP_DEVICE" || echo "Loop device not found"
fi

# Verify loop device is detached
if losetup -l | grep -q "$LOOP_DEVICE"; then
    echo "Warning: Loop device still active, force detaching..."
    losetup -D || true
fi

echo "Loop device detached successfully"
LOOP_DEVICE=""  # Clear variable to prevent cleanup from trying again

# Step 12: Final cleanup
echo "Final cleanup..."

# Go back to original directory
cd ..

# Force cleanup any remaining loop devices pointing to our working file
echo "Checking for remaining loop devices..."
remaining_loops=$(losetup -l 2>/dev/null | grep "working.wic" | awk '{print $1}')
if [ -n "$remaining_loops" ]; then
    echo "Found remaining loop devices:"
    echo "$remaining_loops"
    for loop in $remaining_loops; do
        if [ -n "$loop" ] && [ "$loop" != "LOOP" ]; then
            echo "Detaching remaining loop device: $loop"
            losetup -d "$loop" 2>/dev/null || true
        fi
    done
else
    echo "No remaining loop devices found"
fi

# Force unmount any remaining mount points
MOUNT_PATH="$(pwd)/$WORK_DIR/$MOUNT_DIR"
if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
    echo "Force unmounting remaining mount point: $MOUNT_PATH"
    umount -f "$MOUNT_PATH" 2>/dev/null || umount -l "$MOUNT_PATH" 2>/dev/null || true
fi

# Remove work directory
if [ -d "$WORK_DIR" ]; then
    echo "Removing work directory: $WORK_DIR"
    echo "Contents before removal:"
    ls -la "$WORK_DIR/" || true
    
    # Try to remove read-only files if any
    chmod -R u+w "$WORK_DIR" 2>/dev/null || true
    
    rm -rf "$WORK_DIR"
    if [ -d "$WORK_DIR" ]; then
        echo "Warning: Work directory still exists after removal attempt"
        echo "Attempting force removal with lazy unmount..."
        
        # Find and unmount any remaining mount points
        if command -v findmnt &> /dev/null; then
            findmnt -t ext4,ext3,ext2,vfat | grep "$WORK_DIR" | awk '{print $1}' | while read -r mount_point; do
                echo "Force unmounting: $mount_point"
                umount -l "$mount_point" 2>/dev/null || true
            done
        fi
        
        # Try again
        rm -rf "$WORK_DIR" 2>/dev/null || true
        
        if [ -d "$WORK_DIR" ]; then
            echo "Error: Unable to remove work directory. Manual cleanup may be required."
            echo "You can manually run: sudo rm -rf $WORK_DIR"
        fi
    else
        echo "Work directory successfully removed"
    fi
else
    echo "Work directory not found (already cleaned up)"
fi

# Clear the trap to prevent double cleanup
trap - EXIT

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

echo "Script completed successfully!"
