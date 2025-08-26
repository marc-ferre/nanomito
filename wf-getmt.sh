#!/usr/bin/env bash
###############################################################################
# Script: wf-getmt.sh
# Description: Filter raw Pod5 data from nanopore sequencing reads aligned (BAM) to chrM
# Usage: wf-getmt.sh [-l|--log LOGFILE] /Path/to/run/dir
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

VERSION='25.08.25.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'
# Conda environment name for running the script
GETMT_ENV='nanomito'
# Path to the Python script that extracts chrM read IDs
CHRMPIDS_SCRIPT='/home/mferre/workflows/get_chrMpid.py'
# Path to the conda initialization script
CONDA_SCRIPT='/home/mferre/anaconda3/etc/profile.d/conda.sh'

usage() {
    # Display usage information and exit
    echo "Usage: $0 [-l|--log LOGFILE] /Path/to/run/dir"
    echo "       If LOGFILE is not specified, defaults to /Path/to/run/dir/dir.wf-getmt.log"
    exit 1
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

    # Check if run directory is provided
    if [[ -z "$RUN_DIR" ]]; then
        echo "[ERROR] No run directory supplied."
        usage
    fi
    
    # Set default log file name if not specified
    # Format: /path/to/run/dir/dirname.wf-getmt.log
    if [[ -z "$LOG_FILE" ]]; then
        # Extract directory name for log file naming
        DIR_NAME=$(basename "$RUN_DIR")
        LOG_FILE="$RUN_DIR$DIR_NAME.wf-getmt.log"
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

    echo "Workflow  : wf-getmt v.$VERSION by $AUTHOR"
    echo "——————————— Get IDs of Pod5 reads matching chrM for Nanomito ——————————————"
    echo "Run       : '$RUN_ID'"
    echo "Run dir   : '$RUN_DIR_PATH'"
    echo "BAM dir   : '$BAM_DIR'"
    echo "POD5 dir  : '$POD5_ALL_DIR'"
    echo "Output dir: '$POD5_MT_DIR'"
    echo "Log file  : '$LOG_FILE'"

    # Initialize conda environment
    init_conda

    # Create output directory for chrM Pod5 files if it doesn't exist
    mkdir -p "$POD5_MT_DIR"
    echo "[OK] chrM POD5 directory created: '$POD5_MT_DIR'"

    # Display Pod5 version information
    echo "[INFO] $(pod5 --version)"

    # Run the Python script to extract read IDs from BAM files that align to chrM
    # The script will analyze BAM files and create a list of Pod5 read IDs
    conda run -n getmt python "$CHRMPIDS_SCRIPT" -b "$BAM_DIR" -p "$POD5_ALL_DIR" -o "$MT_PIDS_FILE" -v

    # Count the number of identified reads
    READ_IDS_COUNT=$(wc -l < "$MT_PIDS_FILE")

    if [[ "$READ_IDS_COUNT" -eq 0 ]]; then
        # No reads found that match chrM - nothing to do
        echo '[WARNING] No read matching chrM: ending without Pod5 file of reads matching chrM'
    else
        # Use the pod5 tool to filter and extract only the reads that match chrM
        # --recursive: Search recursively through the input directory
        # --force-overwrite: Overwrite output file if it exists
        # --ids: File containing read IDs to filter
        # --output: Output file path
        pod5 filter --recursive --force-overwrite "$POD5_ALL_DIR" --ids "$MT_PIDS_FILE" --output "$POD5_MT_IDS_FILE"
        echo
        echo "[OK] Pod5 reads matching chrM filtered in file: '$POD5_MT_IDS_FILE'"
        
        # Display summary information about the filtered Pod5 file
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
    echo "| $(du -hs $POD5_MT_DIR)"
    echo '|'
    echo '|'
}

main "$@"