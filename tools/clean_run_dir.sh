#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" describe --tags 2>/dev/null || echo 'unknown')"
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Description:
# This script safely cleans up run directories on the HPC by removing:
# - fastq_pass directory
# - processing directory
#
# Usage:
#   ./tools/clean_run_dir.sh /path/to/run_directory
#   ./tools/clean_run_dir.sh --dry-run /path/to/run_directory
#   ./tools/clean_run_dir.sh --yes /path/to/run_directory
#
# Options:
#   --dry-run    Show what would be deleted without actually deleting
#   --yes        Skip confirmation prompt (use with caution!)
#   --help       Display this help message

# ANSI color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'   # Info
readonly COLOR_YELLOW='\033[0;33m'  # Warning
readonly COLOR_RED='\033[0;31m'     # Error
readonly COLOR_BLUE='\033[0;34m'    # Debug

# Enable strict error handling
set -euo pipefail

# --- Functions ---

_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="$timestamp [$level] $message"
    
    # Select color based on level
    local color=""
    case "$level" in
        INFO)    color="$COLOR_GREEN";;
        WARN)    color="$COLOR_YELLOW";;
        ERROR)   color="$COLOR_RED";;
        DEBUG)   color="$COLOR_BLUE";;
    esac

    # Write to terminal (with colors)
    if [[ -t 1 && -n "$color" ]]; then
        printf "${color}%s${COLOR_RESET}\n" "$log_line"
    else
        printf '%s\n' "$log_line"
    fi
}

show_help() {
    cat << EOF
Clean Run Directory Tool v.$VERSION
Author: $AUTHOR

Description:
  Safely removes fastq_pass and processing directories from a run directory.

Usage:
  $0 [OPTIONS] /path/to/run_directory

Options:
  --dry-run    Show what would be deleted without actually deleting
  --yes        Skip confirmation prompt (use with caution!)
  --help       Display this help message

Examples:
  # Interactive mode (with confirmation)
  $0 /scratch/mferre/workbench/250303_run01_solene

  # Dry run (preview only)
  $0 --dry-run /scratch/mferre/workbench/250303_run01_solene

  # Non-interactive mode (no confirmation)
  $0 --yes /scratch/mferre/workbench/250303_run01_solene

Safety Features:
  - Validates directory existence and permissions
  - Shows size of directories before deletion
  - Requires confirmation (unless --yes is specified)
  - Supports dry-run mode for safe preview
  - Prevents deletion of non-standard directories

EOF
}

validate_directory() {
    local dir="$1"
    
    if [[ ! -e "$dir" ]]; then
        _log ERROR "Directory does not exist: '$dir'"
        exit 1
    fi
    
    if [[ ! -d "$dir" ]]; then
        _log ERROR "Path is not a directory: '$dir'"
        exit 1
    fi
    
    if [[ ! -r "$dir" ]]; then
        _log ERROR "Directory is not readable: '$dir'"
        exit 1
    fi
    
    if [[ ! -w "$dir" ]]; then
        _log ERROR "Directory is not writable: '$dir'"
        exit 1
    fi
}

get_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "N/A"
    fi
}

get_dir_count() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -type f 2>/dev/null | wc -l | xargs
    else
        echo "0"
    fi
}

remove_directory() {
    local dir="$1"
    local dry_run="$2"
    
    if [[ ! -d "$dir" ]]; then
        _log WARN "Directory does not exist (skipping): '$dir'"
        return 0
    fi
    
    local size
    local count
    size=$(get_dir_size "$dir")
    count=$(get_dir_count "$dir")
    
    _log INFO "Target: '$dir'"
    _log INFO "  Size: $size"
    _log INFO "  Files: $count"
    
    if [[ "$dry_run" == "true" ]]; then
        _log DEBUG "[DRY RUN] Would remove: '$dir'"
        return 0
    fi
    
    _log INFO "Removing directory: '$dir'"
    if rm -rf "$dir"; then
        _log INFO "Successfully removed: '$dir'"
        return 0
    else
        _log ERROR "Failed to remove: '$dir'"
        return 1
    fi
}

confirm_deletion() {
    local run_dir="$1"
    local has_fastq="$2"
    local has_processing="$3"
    local fastq_size="$4"
    local processing_size="$5"
    
    echo ""
    echo "======================================"
    echo "  DELETION CONFIRMATION"
    echo "======================================"
    echo "Run directory: $run_dir"
    echo ""
    echo "The following will be deleted:"
    if [[ "$has_fastq" == "true" ]]; then
        echo "  • fastq_pass/ ($fastq_size)"
    fi
    if [[ "$has_processing" == "true" ]]; then
        echo "  • processing/ ($processing_size)"
    fi
    echo ""
    echo -n "Are you sure you want to proceed? [y/N]: "
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            _log WARN "Deletion cancelled by user"
            return 1
            ;;
    esac
}

# --- Main function ---
main() {
    local dry_run=false
    local skip_confirm=false
    local run_dir=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --yes|-y)
                skip_confirm=true
                shift
                ;;
            -*)
                _log ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$run_dir" ]]; then
                    run_dir="$1"
                else
                    _log ERROR "Too many arguments"
                    echo "Use --help for usage information"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if run directory was provided
    if [[ -z "$run_dir" ]]; then
        _log ERROR "No run directory specified"
        echo "Use --help for usage information"
        exit 1
    fi
    
    # Convert to absolute path
    run_dir=$(cd "$run_dir" && pwd)
    
    # Display header
    _log INFO "======================================"
    _log INFO "Clean Run Directory Tool v.$VERSION"
    _log INFO "======================================"
    if [[ "$dry_run" == "true" ]]; then
        _log DEBUG "Mode: DRY RUN (no actual deletion)"
    fi
    _log INFO "Run directory: '$run_dir'"
    echo ""
    
    # Validate run directory
    validate_directory "$run_dir"
    
    # Define target directories
    local fastq_dir="${run_dir}/fastq_pass"
    local processing_dir="${run_dir}/processing"
    
    # Check what exists
    local has_fastq=false
    local has_processing=false
    local fastq_size="N/A"
    local processing_size="N/A"
    
    if [[ -d "$fastq_dir" ]]; then
        has_fastq=true
        fastq_size=$(get_dir_size "$fastq_dir")
    fi
    
    if [[ -d "$processing_dir" ]]; then
        has_processing=true
        processing_size=$(get_dir_size "$processing_dir")
    fi
    
    # Check if there's anything to delete
    if [[ "$has_fastq" == "false" && "$has_processing" == "false" ]]; then
        _log WARN "No directories to clean (fastq_pass and processing not found)"
        exit 0
    fi
    
    # Show what will be deleted
    _log INFO "Directories found:"
    if [[ "$has_fastq" == "true" ]]; then
        _log INFO "  • fastq_pass/ ($fastq_size)"
    else
        _log INFO "  • fastq_pass/ (not found)"
    fi
    
    if [[ "$has_processing" == "true" ]]; then
        _log INFO "  • processing/ ($processing_size)"
    else
        _log INFO "  • processing/ (not found)"
    fi
    echo ""
    
    # Confirmation (unless --yes or --dry-run)
    if [[ "$dry_run" == "false" && "$skip_confirm" == "false" ]]; then
        if ! confirm_deletion "$run_dir" "$has_fastq" "$has_processing" "$fastq_size" "$processing_size"; then
            exit 0
        fi
        echo ""
    fi
    
    # Perform deletion
    local exit_code=0
    
    if [[ "$has_fastq" == "true" ]]; then
        if ! remove_directory "$fastq_dir" "$dry_run"; then
            exit_code=1
        fi
    fi
    
    if [[ "$has_processing" == "true" ]]; then
        if ! remove_directory "$processing_dir" "$dry_run"; then
            exit_code=1
        fi
    fi
    
    # Summary
    echo ""
    if [[ "$dry_run" == "true" ]]; then
        _log INFO "======================================"
        _log INFO "DRY RUN COMPLETE"
        _log INFO "======================================"
        _log INFO "No files were actually deleted"
        _log INFO "Run without --dry-run to perform deletion"
    else
        _log INFO "======================================"
        _log INFO "CLEANUP COMPLETE"
        _log INFO "======================================"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"
