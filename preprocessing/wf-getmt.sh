#!/usr/bin/env bash
###############################################################################
# Script: wf-getmt.sh
# Description: Filter raw Pod5 data from nanopore sequencing reads aligned (BAM) to chrM
# Usage: wf-getmt.sh [-l|--log LOGFILE] /Path/to/run/di
# 
# This script extracts reads from Nanopore sequencing data that align to the 
# mitochondrial chromosome (chrM), which can be used for further analysis in 
# Nanomito. Compatible with Windows Subsystem for Linux.
###############################################################################

# Set shell options:
# -e: Exit immediately if a command exits with a non-zero status
# -u: Treat unset variables as an error when substituting
# -o pipefail: Return value of a pipeline is the value of the last command to exit with non-zero status
set -euo pipefail

VERSION='25.09.19.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Source centralized configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/preprocessing.config"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=preprocessing.config
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Configuration variables are now loaded from preprocessing.config:
# - CONDA_SCRIPT: Path to conda initialization
# - GETMT_ENV: Conda environment name
# - CHRMPIDS_SCRIPT: Path to get_chrMpid.py
# - CREATE_PID_DICT_SCRIPT: Path to create_pid_dict.py
# - DATA_ROOT: Root directory for data

usage() {
    # Display usage information and exit
    echo "Usage: $0 [-l|--log LOGFILE] [/Path/to/run/dir]"
    echo "       If run directory is not specified, automatically uses the latest directory in /mnt/c/data/"
    echo "       If LOGFILE is not specified, defaults to /Path/to/run/dir/dirname.wf-getmt.log"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use latest run, auto-generate log file"
    echo "  $0 /mnt/c/data/250303_run01_solene    # Use specific run, auto-generate log"
    echo "  $0 -l /tmp/custom.log                 # Use latest run with custom log file"
    exit 1
}

get_latest_run_directory() {
    # Find the latest created directory in /mnt/c/data/
    local data_root="/mnt/c/data"
    
    if [[ ! -d "$data_root" ]]; then
        error_exit "Data root directory does not exist: '$data_root'"
    fi
    
    # Find directories with date format (YYMMDD_) and sort by creation time
    local latest_di
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
    # Parse command line arguments
    # Initialize empty variables for log file and run directory
    LOG_FILE=""
    RUN_DIR=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
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
    
    # Set default log file name if not specified
    # Format: /path/to/run/dir/dirname.wf-getmt.log
    if [[ -z "$LOG_FILE" ]]; then
        # Extract directory name for log file naming
        DIR_NAME=$(basename "$RUN_DIR")
        LOG_FILE="$RUN_DIR/$DIR_NAME.wf-getmt.log"
        echo "[INFO] Log file automatically set to: '$LOG_FILE'"
    fi
}

redirect_log() {
    # Redirect stdout and stderr to both console and log file
    if [[ -n "$LOG_FILE" ]]; then
        exec > >(tee "$LOG_FILE") 2>&1
        echo "[INFO] Logging to '$LOG_FILE'"
    fi
}

error_exit() {
    # Print error message and exit with provided or default exit code
    echo "[ERROR] $1" >&2
    exit "${2:-1}"  # Use provided exit code or default to 1
}

init_conda() {
    # Initialize conda environment for running pod5 commands
    local conda_sh=$CONDA_SCRIPT
    if [[ -f "$conda_sh" ]]; then
        # shellcheck source=/home/mferre/anaconda3/etc/profile.d/conda.sh
        source "$conda_sh"
    else
        error_exit "Conda initialization script not found at '$conda_sh'"
    fi
    conda activate "$GETMT_ENV" || error_exit "Failed to activate conda env: '$GETMT_ENV'"
}

main() {
    # Main function that orchestrates the workflow
    parse_args "$@"
    redirect_log
    
    # Display script information
    echo "=========================================================================="
    echo "Workflow  : wf-getmt v.$VERSION by $AUTHOR"
    echo "Description: Extract chrM reads from nanopore sequencing data"
    echo "=========================================================================="
    
    # Increase the maximum number of open files to handle large datasets
    ULIMIT=8182
    echo "[INFO] Maximum number of user processes set to $ULIMIT"
    ulimit -n $ULIMIT

    # Change to the run directory and extract the run ID from the directory name
    cd "$RUN_DIR" || error_exit "Cannot cd to '$RUN_DIR'"
    RUN_ID="${PWD##*/}"
    RUN_ID="${RUN_ID:-/}"

    # Define paths for input and output directories/files
    RUN_DIR_PATH=$(pwd)
    BAM_DIR="$RUN_DIR_PATH/bam"                        # BAM alignment files directory
    POD5_ALL_DIR="$RUN_DIR_PATH/pod5"                       # All Pod5 files directory
    POD5_MT_DIR="$RUN_DIR_PATH/pod5_chrM"                   # Output directory for chrM-specific Pod5 files
    MT_PIDS_FILE="$POD5_MT_DIR/$RUN_ID.chrM_pids.txt"       # File to store read IDs matching chrM
    POD5_MT_IDS_FILE="$POD5_MT_DIR/$RUN_ID.chrM.pod5"       # Output Pod5 file with chrM-specific reads
    PID_DICT_FILE="$POD5_MT_DIR/$RUN_ID.pid_dict.tsv"       # TSV mapping read_id -> parent_id

    echo "Run       : '$RUN_ID'"
    echo "Run dir   : '$RUN_DIR_PATH'"
    echo "BAM dir   : '$BAM_DIR'"
    echo "POD5 dir  : '$POD5_ALL_DIR'"
    echo "Output dir: '$POD5_MT_DIR'"
    echo "Log file  : '$LOG_FILE'"
    echo "=========================================================================="
    
    # Validate required directories exist
    if [[ ! -d "$BAM_DIR" ]]; then
        error_exit "BAM directory not found: '$BAM_DIR'"
    fi
    
    if [[ ! -d "$POD5_ALL_DIR" ]]; then
        error_exit "POD5 directory not found: '$POD5_ALL_DIR'"
    fi
    
    echo "[INFO] Validated required directories exist"

    # Initialize conda environment
    init_conda

    # Create output directory for chrM Pod5 files if it doesn't exist
    mkdir -p "$POD5_MT_DIR"
    echo "[OK] chrM POD5 directory created: '$POD5_MT_DIR'"

    # Display Pod5 version information
    echo "[INFO] $(pod5 --version)"

    # Create read_id -> parent_id dictionary from Dorado BAMs (if possible)
    echo "[INFO] Creating read->parent dictionary: $PID_DICT_FILE"
    conda run -n getmt python "$CREATE_PID_DICT_SCRIPT" -b "$BAM_DIR" -o "$PID_DICT_FILE" || echo "[WARN] create_pid_dict.py failed or not available; continuing without dict"

    # Run the Python script to extract read IDs from BAM files that align to chrM
    # Use the dictionary if it was successfully created
    if [[ -f "$PID_DICT_FILE" ]]; then
        echo "[INFO] Using PID dictionary: $PID_DICT_FILE"
        conda run -n getmt python "$CHRMPIDS_SCRIPT" -b "$BAM_DIR" -p "$POD5_ALL_DIR" -o "$MT_PIDS_FILE" -v -d "$PID_DICT_FILE"
    else
        conda run -n getmt python "$CHRMPIDS_SCRIPT" -b "$BAM_DIR" -p "$POD5_ALL_DIR" -o "$MT_PIDS_FILE" -v
    fi

    # Count the number of identified reads
    READ_IDS_COUNT=$(wc -l < "$MT_PIDS_FILE")
    echo "[INFO] Found $READ_IDS_COUNT reads matching chrM"

    if [[ "$READ_IDS_COUNT" -eq 0 ]]; then
        # No reads found that match chrM - nothing to do
        echo '[WARNING] No read matching chrM: ending without Pod5 file of reads matching chrM'
    else
        echo "[INFO] Filtering Pod5 files to extract chrM reads..."
        # Use the pod5 tool to filter and extract only the reads that match chrM
        # --recursive: Search recursively through the input directory
        # --force-overwrite: Overwrite output file if it exists
        # --ids: File containing read IDs to filte
        # --output: Output file path
        pod5 filter --recursive --force-overwrite "$POD5_ALL_DIR" --ids "$MT_PIDS_FILE" --output "$POD5_MT_IDS_FILE"
        echo
        echo "[OK] Pod5 reads matching chrM filtered in file: '$POD5_MT_IDS_FILE'"
        
        # Display summary information about the filtered Pod5 file
        echo "[INFO] Pod5 file summary:"
        pod5 inspect summary "$POD5_MT_IDS_FILE"
    fi

    # Uncomment the line below to remove the intermediate file with read IDs
    # rm "$MT_PIDS_FILE" && echo "[OK] IDs file of Pod5 reads matching chrM removed: $MT_PIDS_FILE"

    # Deactivate conda environment when done
    conda deactivate

    # Move log file to output directory if it's not already there
    if [[ -n "$LOG_FILE" && "$LOG_FILE" != "$POD5_MT_DIR"/* ]]; then
        # Extract just the filename from the full path
        LOG_FILENAME=$(basename "$LOG_FILE")
        NEW_LOG_PATH="$POD5_MT_DIR/$LOG_FILENAME"
        
        # Close current log file before moving it to avoid file-in-use errors
        exec &>/dev/tty
        
        # Copy log file to output directory and remove original if successful
        if cp "$LOG_FILE" "$NEW_LOG_PATH"; then
            echo "[OK] Log file copied to output directory: '$NEW_LOG_PATH'"
            rm "$LOG_FILE" && echo "[OK] Original log file removed: $LOG_FILE"
        else
            echo "[WARNING] Failed to copy log file to output directory"
        fi
    fi

    # Display final success message with directory size information
    echo '|'
    echo '|'
    echo "| Workflow finished successfully. Pod5 data generated:"
    echo "| $(du -hs "$POD5_MT_DIR")"
    echo '|'
    echo '|'
}

main "$@"