#!/usr/bin/env bash
#
# wf-getmt.sh [-l|--log LOGFILE] /Path/to/run/dir
#
# Filter raw Pod5 data from nanopore sequencing reads aligned (BAM) to chrM
# For Windows Subsystem for Linux
#
set -euo pipefail

VERSION='25.05.26.2'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'
GETMT_ENV='nanomito'
CHRMPIDS_SCRIPT='/home/mferre/workflows/get_chrMpid.py'

usage() {
    echo "Usage: $0 [-l|--log LOGFILE] /Path/to/run/dir"
    exit 1
}

parse_args() {
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

    if [[ -z "$RUN_DIR" ]]; then
        echo "[ERROR] No run directory supplied."
        usage
    fi
}

redirect_log() {
    if [[ -n "$LOG_FILE" ]]; then
        exec > >(tee "$LOG_FILE") 2>&1
        echo "[INFO] Logging to $LOG_FILE"
    fi
}

error_exit() {
    echo "[ERROR] $1" >&2
    exit "${2:-1}"
}

init_conda() {
    local conda_sh='/home/mferre/anaconda3/etc/profile.d/conda.sh'
    if [[ -f "$conda_sh" ]]; then
        # shellcheck source=/home/mferre/anaconda3/etc/profile.d/conda.sh
        source "$conda_sh"
    else
        error_exit "Conda initialization script not found at $conda_sh"
    fi
    conda activate "$GETMT_ENV" || error_exit "Failed to activate conda env: $GETMT_ENV"
}

main() {
    parse_args "$@"
    redirect_log
    
    ULIMIT=4096
    echo "[INFO] Maximum number of user processes set to $ULIMIT"
    ulimit -n $ULIMIT

    cd "$RUN_DIR" || error_exit "Cannot cd to $RUN_DIR"
    RUN_ID="${PWD##*/}"
    RUN_ID="${RUN_ID:-/}"

    RUN_DIR_PATH=$(pwd)
    BAM_DIR="$RUN_DIR_PATH/bam"
    POD5_ALL_DIR="$RUN_DIR_PATH/pod5"
    POD5_MT_DIR="$RUN_DIR_PATH/pod5_chrM"
    MT_PIDS_FILE="$POD5_MT_DIR/$RUN_ID.chrM_pids.txt"
    POD5_MT_IDS_FILE="$POD5_MT_DIR/$RUN_ID.chrM.pod5"

    echo "Workflow  : wf-getmt v.$VERSION by $AUTHOR"
    echo "——————————— Get IDs of Pod5 reads matching chrM for Nanomito ——————————————"
    echo "Run       : $RUN_ID"
    echo "Run dir   : $RUN_DIR_PATH"
    echo "BAM dir   : $BAM_DIR"
    echo "POD5 dir  : $POD5_ALL_DIR"
    echo "Output dir: $POD5_MT_DIR"

    init_conda

    mkdir -p "$POD5_MT_DIR"
    echo "[OK] chrM POD5 directory created: $POD5_MT_DIR"

	echo "[INFO] $(pod5 --version)"

    # Get unique parent IDs (pid) of reads aligned to chrM
	conda run -n getmt python "$CHRMPIDS_SCRIPT" -b "$BAM_DIR" -p "$POD5_ALL_DIR" -o "$MT_PIDS_FILE"

    READ_IDS_COUNT=$(wc -l < "$MT_PIDS_FILE")

    if [[ "$READ_IDS_COUNT" -eq 0 ]]; then
        echo '[WARNING] No read matching chrM: ending without Pod5 file of reads matching chrM'
    else
        echo "[WARNING] Option '--missing-ok' to pod5 command: possibly missing reads"
        pod5 filter --missing-ok --recursive --force-overwrite "$POD5_ALL_DIR" --ids "$MT_PIDS_FILE" --output "$POD5_MT_IDS_FILE"
        echo
        echo "[OK] Pod5 reads matching chrM filtered in file: $POD5_MT_IDS_FILE"
        pod5 inspect summary "$POD5_MT_IDS_FILE"
    fi

    # Uncomment to remove intermediate file
    # rm "$MT_PIDS_FILE" && echo "[OK] IDs file of Pod5 reads matching chrM removed: $MT_PIDS_FILE"

    conda deactivate

    echo '|'
    echo '|'
    echo "| Workflow finished successfully. Pod5 data generated:"
    echo "| $(du -hs "$POD5_MT_DIR")"
    echo '|'
    echo '|'
}

main "$@"