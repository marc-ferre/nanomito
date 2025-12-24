#!/bin/bash
#SBATCH --job-name=modmito
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=6
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --mail-type=FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#
# wf-modmito.sh - Mitochondrial modifications analysis workflow
#
# Description:
#   Analyzes mitochondrial modifications from demultiplexed patient files
#
# Usage:
#   sbatch --chdir=/path/to/run wf-modmito.sh SAMPLE_ID
#
# Arguments:
#   $1: SAMPLE_ID - Name of the sample directory in fastq_pass/
#                   (e.g., barcode09, barcode10, etc.)
#
# Directory structure expected:
#   RUN_DIR/
#     ├── fastq_pass/
#     │   └── SAMPLE_ID/
#     │       └── demultiplexed patient files
#     └── processing/
#         └── SAMPLE_ID/
#
# Dependencies:
#   - Requires wf-demultmt.sh to have completed successfully
#
#
# Strict error handling
set -euo pipefail

# Trap for cleanup on error
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Check logs in processing/ directory"
    fi
}
trap cleanup EXIT

VERSION='2.0.0'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Logging helper functions
log_step() {
	echo ""
	echo "=========================================="
	echo "[STEP $1] $(date '+%Y-%m-%d %H:%M:%S')"
	echo "=========================================="
}

log_info() {
	echo "[INFO] $(date '+%H:%M:%S') - $1"
}

log_success() {
	echo "[OK]   $(date '+%H:%M:%S') - $1"
}

log_error() {
	echo "[ERROR] $(date '+%H:%M:%S') - $1" >&2
}

log_warning() {
	echo "[WARN] $(date '+%H:%M:%S') - $1"
}

# Run id = Working directory basename
RUN_ID=${PWD##*/} # Assign directory name to run id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Sample id = Argument
if [ $# -eq 0 ]
	then
		log_error "No arguments supplied"
		echo "Usage: sbatch --chdir=/path/to/run wf-modmito.sh SAMPLE_ID"
		exit 128 # die with error code
fi
SAMPLE_ID=$1

# Read selection strategy (start, both, either ,xor)
SELECT='both' 

# Basecalling model
MODEL_COMPLEX='sup,5mC_5hmC,6mA'

# Directories
RUN_DIR=$(pwd)
PROCESS_DIR="$RUN_DIR/processing"
OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
SELECT_DIR="$OUT_DIR/select-$SELECT"
# MODBASE_DIR="$OUT_DIR/modbase"

# Load global configuration
# Get absolute path to script directory (works even with relative paths and symlinks)
# Use NANOMITO_DIR if set (from submit_nanomito.sh), otherwise auto-detect
if [ -n "${NANOMITO_DIR:-}" ]; then
    SCRIPT_DIR="$NANOMITO_DIR"
else
    # Use BASH_SOURCE when available (sbatch), fallback to $0 for direct execution
    SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
    if [ -L "$SCRIPT_PATH" ]; then
        SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    fi
    case "$SCRIPT_PATH" in
        /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
        *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
    esac
fi
CONFIG_FILE="$SCRIPT_DIR/nanomito.config"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# shellcheck source=nanomito.config
source "$CONFIG_FILE"

# Basecalling model
MODEL_COMPLEX='sup,5mC_5hmC,6mA'

# Prefixes
BAM_PREFIX="$SAMPLE_ID.chrM.$MODEL_COMPLEX"

# Files - Robust handling of multiple sample_sheet files
DEMULT_POD5_FILE="$SELECT_DIR/$SAMPLE_ID.demultmt.pod5"
BAM_FILE="$OUT_DIR/$BAM_PREFIX.bam"
SORTED_BAM_FILE="$OUT_DIR/$BAM_PREFIX.sorted.bam"
BEDMETHYL_FILE="$OUT_DIR/$BAM_PREFIX.combine.bed"

# Handle multiple sample_sheet files (select oldest if multiple exist)
mapfile -t SAMPLESHEET_FILES < <(find "$RUN_DIR" -maxdepth 2 -type f -name 'sample_sheet_*.csv')
if [ ${#SAMPLESHEET_FILES[@]} -eq 0 ]; then
    log_error "No sample_sheet_*.csv file found in $RUN_DIR"
    exit 1
elif [ ${#SAMPLESHEET_FILES[@]} -eq 1 ]; then
    SAMPLESHEET_FILE=$(readlink -f "${SAMPLESHEET_FILES[0]}")
else
    # Multiple files found - select the oldest (first created)
    OLDEST_FILE="${SAMPLESHEET_FILES[0]}"
    for file in "${SAMPLESHEET_FILES[@]}"; do
        if [ "$file" -ot "$OLDEST_FILE" ]; then
            OLDEST_FILE="$file"
        fi
    done
    SAMPLESHEET_FILE=$(readlink -f "$OLDEST_FILE")
    log_warning "Found ${#SAMPLESHEET_FILES[@]} sample_sheet files, using oldest: $SAMPLESHEET_FILE"
fi

WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

check_dir () { 
	if [ -d "$1" ]
	then 
   		log_success "Directory $1 exists"
   	else
		log_error "Directory $1 doesn't exist"
		exit 128 # die with error code 
	fi
}
check_file () { 
	if [ -f "$1" ] && [ -s "$1" ]
	then 
   		log_success "File $1 exists and is not empty"
   	else
		log_error "File $1 is empty or doesn't exist"
		exit 128 # die with error code
	fi
}

START=$(date +%s)
STEP_START=$START

log_step "1/4: INITIALIZATION"
log_info "Workflow: wf-modmito v.$VERSION by $AUTHOR"
log_info "Run ID: $RUN_ID"
log_info "Sample ID: $SAMPLE_ID"
log_info "SLURM Job ID: ${SLURM_JOB_ID:-N/A}"
log_info "Run directory: $RUN_DIR"
log_info "Output directory: $OUT_DIR"
log_info "Read selection strategy: $SELECT"
log_info "Pod5 file: $DEMULT_POD5_FILE"
log_info "Sample sheet: $SAMPLESHEET_FILE"
log_info "Model complex: $MODEL_COMPLEX"
log_info "Reference file: $SELECTED_REF"

# Check if demultiplexing found no data
NO_DATA_MARKER="$OUT_DIR/NO_DATA.marker"
if [ -f "$NO_DATA_MARKER" ]; then
	echo ""
	echo "=========================================="
	echo "NO DATA DETECTED - SKIPPING ANALYSIS"
	echo "=========================================="
	log_warning "The demultiplexing step found no reads matching both references"
	log_warning "This sample will be skipped (not an error)"
	log_warning "NO_DATA.marker file detected: $NO_DATA_MARKER"
	echo "=========================================="
	echo ""
	
	# Exit successfully to allow dependency chain to continue
	log_success "Workflow completed successfully (NO DATA - SKIPPED)"
	exit 0
fi

echo ""
echo "========== SLURM Environment =========="
echo "Node    : ${SLURM_NODELIST:-N/A}"
echo "Job ID  : ${SLURM_JOB_ID:-N/A}"
echo "CPUs    : ${SLURM_CPUS_PER_TASK:-N/A}"
echo "Memory  : ${SLURM_MEM_PER_NODE:-N/A} MB"
if command -v nvidia-smi &> /dev/null; then
    echo "GPU     : $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'N/A')"
else
    echo "GPU     : N/A"
fi
echo "========================================"

log_step "2/4: VALIDATION"
check_file "$DEMULT_POD5_FILE"

log_step "3/4: MODIFIED BASES BASECALLING"
STEP_START=$(date +%s)

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

log_info "Dorado version:"
$DORADO_BIN --version

log_info "Starting duplex basecalling with modifications..."
$DORADO_BIN duplex $MODEL_COMPLEX "$DEMULT_POD5_FILE" \
	--verbose \
	--reference $SELECTED_REF \
	> "$BAM_FILE"
check_file "$BAM_FILE"

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "Basecalling completed"
log_info "Basecalling duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

log_step "4/4: BAM SORTING & BEDMETHYL GENERATION"
STEP_START=$(date +%s)

# Source Conda, to use it on a Genouest cluster compute node
log_info "Loading Conda environment"
set +u  # Temporarily disable unset variable check for conda
if [ -f /local/env/envconda.sh ]; then
    # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
    . /local/env/envconda.sh 2>/dev/null || log_warning "Failed to source envconda.sh, conda may already be available"
else
    log_warning "Conda init script not found at /local/env/envconda.sh"
fi
set -u  # Re-enable unset variable check

conda activate $MODMITO_ENV

log_info "Samtools version:"
samtools --version

log_info "Sorting BAM file..."
samtools sort "$BAM_FILE" -o "$SORTED_BAM_FILE"
check_file "$SORTED_BAM_FILE"

log_info "Indexing sorted BAM file..."
samtools index "$SORTED_BAM_FILE"
check_file "${SORTED_BAM_FILE}.bai"

log_info "Removing unsorted BAM file..."
rm "$BAM_FILE" && [[ ! -e $BAM_FILE ]] && log_success "BAM file removed: $BAM_FILE"

log_info "Modkit version: $(modkit --version)"

log_info "Generating bedMethyl file..."
modkit pileup "$SORTED_BAM_FILE" "$BEDMETHYL_FILE"
check_file "$BEDMETHYL_FILE"

conda deactivate

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "BAM sorting and bedMethyl generation completed"
log_info "Processing duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

echo ""
echo "=========================================="
echo "          WORKFLOW COMPLETED              "
echo "=========================================="

END=$(date +%s)
RUNTIME=$((END - START))
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))

log_success "Total runtime: $(printf '%02d:%02d:%02d' $HOURS $MINUTES $SECONDS)"
log_info "End time: $(date '+%Y-%m-%d %H:%M:%S')"

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > "$WORKFLOW_SUMMARY_FILE"
	log_success "Created workflow summary file"
fi
printf "%s\t%s\t%s\t%02d:%02d:%02d\n" "$RUN_ID" "$SAMPLE_ID" "modmito" "$HOURS" "$MINUTES" "$SECONDS" >> "$WORKFLOW_SUMMARY_FILE"
log_success "Updated workflow summary file: $WORKFLOW_SUMMARY_FILE"

echo ""
echo "=========================================="
log_info "Check detailed logs in processing/ directory"
echo "=========================================="