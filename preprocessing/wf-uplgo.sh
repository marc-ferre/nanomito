#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# shellcheck disable=SC2034
#
# wf-uplgo.sh - Upload run data to remote SSH host using rsync
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
#
# Upload run data to a remote SSH host using rsync
# Excludes large data files (pod5, bam, fastq) and only syncs metadata/configuration files

set -euo pipefail

# Load optional preprocessing configuration
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
fi
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
CONFIG_FILE="$SCRIPT_DIR/preprocessing.config"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=preprocessing.config
    # shellcheck disable=SC1091
    source "$CONFIG_FILE"
fi

# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || echo 'unknown')"

# Track if we started the ssh-agent ourselves
SSH_AGENT_STARTED=0

cleanup_ssh_agent() {
    # Only kill the agent if we started it
    if [[ $SSH_AGENT_STARTED -eq 1 && -n "${SSH_AGENT_PID:-}" ]]; then
        echo "[INFO] Cleaning up SSH agent (PID: $SSH_AGENT_PID)..."
        kill "$SSH_AGENT_PID" 2>/dev/null || true
        unset SSH_AUTH_SOCK SSH_AGENT_PID
    fi
}

# Cleanup on exit
trap cleanup_ssh_agent EXIT

setup_ssh() {
    echo "[INFO] Setting up SSH authentication..."
    
    # Start SSH agent if not already running
    if ! pgrep -u "$USER" ssh-agent > /dev/null 2>/dev/null; then
        echo "[INFO] Starting SSH agent..."
        eval "$(ssh-agent -s)"
        SSH_AGENT_STARTED=1
    else
        # Agent is running - try to connect to it
        if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
            # Find the agent socket
            export SSH_AUTH_SOCK=$(find /tmp/ssh-* -name "agent.*" 2>/dev/null | head -n 1)
            if [[ -n "$SSH_AUTH_SOCK" ]]; then
                echo "[INFO] Connected to existing SSH agent"
            fi
        fi
    fi
    
    # Check if key is already loaded in agent
    if ssh-add -l > /dev/null 2>&1; then
        echo "[OK] SSH key already loaded in agent"
        return 0
    fi
    
    # Add the SSH key to agent (will prompt for passphrase)
    echo "[INFO] Adding SSH key to agent..."
    if ssh-add /home/mferre/.ssh/id_rsa > /dev/null 2>&1; then
        echo "[OK] SSH key added successfully"
    else
        echo "[WARNING] Could not add SSH key - SSH may prompt for passphrase"
    fi
}

usage() {
    cat << EOF
Usage: $0 [RUN_DIRECTORY] [OPTIONS]

Upload nanopore run data to a remote SSH host, excluding large data files.

Arguments:
  RUN_DIRECTORY     Path to the run directory to upload
                    If not specified, uses the latest directory in /mnt/c/data/

Options:
    -u, --user USER   SSH username (default: from config or local user)
    -h, --host HOST   SSH hostname (default: from config)
    -d, --dest PATH   Destination path on remote host (default: from config)
  -n, --dry-run     Show what would be transferred without actually doing it
  --help            Show this help message

Examples:
  $0                                                    # Upload latest run with defaults
  $0 /mnt/c/data/run_dir                               # Upload specific run
    $0 -u myuser -h myserver.org                         # Upload with custom credentials
  $0 --dry-run                                         # Preview what would be uploaded

Excluded directories: pod5, bam, bam_fail, bam_pass, fastq_fail, fastq_pass
EOF
    exit 0
}

error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

get_latest_run_directory() {
    # Find the latest created directory in /mnt/c/data/
    local data_root="/mnt/c/data"
    
    if [[ ! -d "$data_root" ]]; then
        error_exit "Data root directory does not exist: '$data_root'"
    fi
    
    # Find directories with date format (YYMMDD_) and sort by creation time
    local latest_dir
    latest_dir=$(find "$data_root" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9][0-9][0-9]_*" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_dir" ]]; then
        error_exit "No run directories found in '$data_root' (looking for format YYMMDD_*)"
    fi
    
    # Output info message to stderr (so it doesn't interfere with function return)
    echo "[INFO] Latest run directory automatically detected: '$latest_dir'" >&2
    # Return only the directory path to stdout
    echo "$latest_dir"
}

parse_args() {
    # Default values
    # Defaults pulled from preprocessing.config if available
    GO_USER="${GO_USER:-$USER}"
    GO_HOST="${GO_HOST:-your.ssh.host}"
    GO_DEST="${GO_REMOTE_BASE:-/path/on/remote/workbench}" 
    RUN_DIR=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--user)
                GO_USER="$2"
                shift 2
                ;;
            -h|--host)
                GO_HOST="$2"
                shift 2
                ;;
            -d|--dest)
                GO_DEST="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                usage
                ;;
            -*)
                echo "[ERROR] Unknown option: $1"
                usage
                ;;
            *)
                if [[ -z "$RUN_DIR" ]]; then
                    RUN_DIR="$1"
                    shift
                else
                    echo "[ERROR] Unexpected argument: $1"
                    usage
                fi
                ;;
        esac
    done
    
    # If no run directory is provided, automatically detect the latest one
    if [[ -z "$RUN_DIR" ]]; then
        echo "[INFO] No run directory specified, detecting latest directory..."
        RUN_DIR=$(get_latest_run_directory)
    fi
    
    # Validate that the run directory exists
    if [[ ! -d "$RUN_DIR" ]]; then
        error_exit "Run directory does not exist: '$RUN_DIR'"
    fi
    
    # Ensure destination path ends with /
    if [[ "$GO_DEST" != */ ]]; then
        GO_DEST="${GO_DEST}/"
    fi
}

show_summary() {
    echo "========================================="
    echo "HPC Upload Summary"
    echo "========================================="
    echo "Source directory: $RUN_DIR"
    echo "Destination: ${GO_USER}@${GO_HOST}:${GO_DEST}"
    echo "Dry run mode: $DRY_RUN"
    echo ""
    echo "Excluded directories:"
    echo "  - pod5 (raw signal data)"
    echo "  - bam, bam_fail, bam_pass (alignment files)"
    echo "  - fastq_fail, fastq_pass (basecalled sequences)"
    echo ""
    echo "This will sync configuration files, logs, and metadata only."
    echo "========================================="
    echo ""
}

run_rsync() {
    # Build rsync command
    local rsync_cmd=(
        rsync
        -avzc
        --stats
        --progress
        --delete
        --delete-excluded
        "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fog=r"
        --exclude 'pod5'
        --exclude 'bam'
        --exclude 'bam_fail'
        --exclude 'bam_pass'
        --exclude 'fastq_fail'
        --exclude 'fastq_pass'
    )
    
    # Add dry-run flag if specified
    if [[ "$DRY_RUN" = true ]]; then
        rsync_cmd+=(--dry-run)
        echo "[INFO] DRY RUN MODE - No files will actually be transferred"
        echo ""
    fi
    
    # Add source and destination
    rsync_cmd+=("$RUN_DIR" "${GO_USER}@${GO_HOST}:${GO_DEST}")
    
    echo "[INFO] Executing rsync command:"
    echo "${rsync_cmd[*]}"
    echo ""
    
    # Execute rsync
    "${rsync_cmd[@]}"
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$DRY_RUN" = true ]]; then
            echo ""
            echo "[SUCCESS] Dry run completed successfully"
            echo "[INFO] Run without --dry-run to perform actual upload"
        else
            echo ""
            echo "[SUCCESS] Upload completed successfully"
        fi
    else
        error_exit "rsync failed with exit code $exit_code"
    fi
}

main() {
    parse_args "$@"
    show_summary
    
    # Setup SSH authentication
    setup_ssh
    
    # Skip confirmation when:
    # 1. Called from pipeline (PIPELINE_MODE=true)
    # 2. Called from Windows/PowerShell (non-interactive stdin)
    # 3. Dry run mode
    if [[ "$DRY_RUN" = false && "${PIPELINE_MODE:-false}" != "true" ]]; then
        # Only ask if stdin is a terminal (interactive)
        if [[ -t 0 ]]; then
            read -p "Do you want to proceed with the upload? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "[INFO] Upload cancelled by user"
                exit 0
            fi
            echo ""
        fi
    fi
    
    run_rsync
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi