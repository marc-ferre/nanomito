#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
#SBATCH --job-name=subwf
#SBATCH --time=00:30:00
#SBATCH --output=processing/slurm-%x.%j.out
#SBATCH --error=processing/slurm-%x.%j.err
#SBATCH --mail-type=FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_80
#
#
# wf-subwf.sh - Workflow submission orchestrator
#
# Description:
#   This script orchestrates the submission of multiple SLURM jobs for each sample
#   in a sequencing run. It submits two types of workflows per sample:
#   1. demultmt: Demultiplexing of mitochondrial reads
#   2. modmito: Analysis of mitochondrial modifications (depends on demultmt)
#
# Usage:
#   sbatch wf-subwf.sh
#   (Must be run from the run directory containing fastq_pass/)
#
# Directory structure expected:
#   RUN_DIR/
#     ├── fastq_pass/
#     │   ├── sample1/
#     │   ├── sample2/
#     │   └── ...
#     └── processing/
#
# Arguments:
#   None - The script automatically detects samples in fastq_pass/ directory
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

# Parse options
DEMULTMT_ONLY=false
SKIP_DEMULTMT=false
MODMITO_ONLY=false
SKIP_MODMITO=false
SKIP_ARCHIVING=false
INCLUDE_UNCLASSIFIED=false
ONLY_SAMPLES=""
PROCESS_ALL=false

while [[ $# -gt 0 ]]; do
	case $1 in
		--demultmt-only)
			DEMULTMT_ONLY=true
			shift
			;;
		--skip-demultmt)
			SKIP_DEMULTMT=true
			shift
			;;
		--modmito-only)
			MODMITO_ONLY=true
			shift
			;;
		--skip-modmito)
			SKIP_MODMITO=true
			shift
			;;
		--skip-archiving)
			SKIP_ARCHIVING=true
			shift
			;;
		--include-unclassified)
			INCLUDE_UNCLASSIFIED=true
			shift
			;;
		--only-samples)
			ONLY_SAMPLES="$2"
			shift 2
			;;
		--all)
			PROCESS_ALL=true
			shift
			;;
		*)
			log_error "Unknown option: $1"
			exit 128
			;;
	esac
done

# Directories
RUN_DIR=$(pwd)
FASTQ_DIR="$RUN_DIR/fastq_pass"
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=$(basename "$RUN_DIR")

# Files
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

# Load global configuration
# Get absolute path to script directory (works even with relative paths and symlinks)
# Use NANOMITO_DIR if set (from submit_nanomito.sh or parent workflow), otherwise auto-detect
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
# shellcheck disable=SC1091
source "$CONFIG_FILE"

# Validate workflow scripts exist
# Note: Only checks file existence, not executability
# sbatch will perform its own validation when submitting jobs
check_workflow() {
	if [ -f "$1" ]; then
		log_success "Workflow script found: $1"
	else
		log_warning "Workflow script not found: $1"
		log_warning "Continuing anyway - sbatch will validate the script path"
	fi
}

START=$(date +%s)

log_step "1/3: INITIALIZATION"
log_info "Workflow: wf-subwf v.$VERSION by $AUTHOR"
log_info "Run ID: $RUN_ID"
log_info "SLURM Job ID: ${SLURM_JOB_ID:-N/A}"
log_info "Run directory: $RUN_DIR"
log_info "FASTQ directory: $FASTQ_DIR"
log_info "Output directory: $PROCESS_DIR"

# Log active options
if [ "$DEMULTMT_ONLY" = true ]; then
	log_info "Mode: demultmt-only (skipping modmito)"
elif [ "$MODMITO_ONLY" = true ]; then
	log_info "Mode: modmito-only (skipping demultmt)"
elif [ "$SKIP_DEMULTMT" = true ]; then
	log_info "Mode: modmito workflows only"
elif [ "$SKIP_MODMITO" = true ]; then
	log_info "Mode: demultmt workflows only"
else
	log_info "Mode: full analysis (demultmt + modmito)"
fi

echo ""
echo "========== SLURM Environment =========="
echo "Node    : ${SLURM_NODELIST:-N/A}"
echo "Job ID  : ${SLURM_JOB_ID:-N/A}"
echo "========================================"

log_step "2/3: VALIDATION"
if [ "$SKIP_DEMULTMT" = false ] && [ "$MODMITO_ONLY" = false ]; then
	check_workflow "$WF_DEMULTMT"
fi
if [ "$SKIP_MODMITO" = false ] && [ "$DEMULTMT_ONLY" = false ]; then
	check_workflow "$WF_MODMITO"
fi

if [ ! -d "$FASTQ_DIR" ]; then
	log_error "FASTQ directory does not exist: $FASTQ_DIR"
	exit 128
fi

SAMPLE_COUNT=$(find "$FASTQ_DIR"/* -prune -type d 2>/dev/null | wc -l)
log_info "Found $SAMPLE_COUNT sample directories"

if [ "$SAMPLE_COUNT" -eq 0 ]; then
	log_error "No sample directories found in $FASTQ_DIR"
	exit 128
fi

# Extract expected samples from sample sheet if available
EXPECTED_SAMPLES=""
if [ "$PROCESS_ALL" = false ]; then
	SAMPLESHEET_FILE=$(find "$RUN_DIR" -maxdepth 2 -type f -name 'sample_sheet_*.csv' | head -1)
	if [ -f "$SAMPLESHEET_FILE" ]; then
		log_info "Reading sample sheet: $SAMPLESHEET_FILE"
		
		# Extract barcodes and aliases from sample sheet (skip header)
		# Expected columns: experiment_id,kit,flow_cell_id,alias,barcode
		BARCODES=$(tail -n +2 "$SAMPLESHEET_FILE" | cut -d, -f5 | sort -u)
		ALIASES=$(tail -n +2 "$SAMPLESHEET_FILE" | cut -d, -f4 | sort -u)
		
		# Combine barcodes and aliases into expected samples list
		EXPECTED_SAMPLES=$(echo -e "${BARCODES}\n${ALIASES}" | sort -u | tr '\n' ',')
		EXPECTED_SAMPLES="${EXPECTED_SAMPLES%,}"  # Remove trailing comma
		
		if [ -n "$EXPECTED_SAMPLES" ]; then
			log_success "Expected samples from sample sheet: $EXPECTED_SAMPLES"
			
			# If user didn't specify --only-samples, use the sample sheet list
			if [ -z "$ONLY_SAMPLES" ]; then
				ONLY_SAMPLES="$EXPECTED_SAMPLES"
				log_info "Filtering samples based on sample sheet (use --all to process all directories)"
			fi
		fi
	else
		log_warning "No sample sheet found, processing all sample directories"
	fi
else
	log_info "--all option specified, processing all sample directories"
fi

log_step "3/3: SUBMITTING WORKFLOWS"

# Counters for tracking submitted jobs
SAMPLES_COUNT=0
JOBS_COUNT=0
JOBID_LIST=''
DEMULTMT_JOBS=0
MODMITO_JOBS=0
SKIPPED_SAMPLES=""
SKIPPED_COUNT=0

# Process each sample directory in fastq_pass/
cd "$FASTQ_DIR"
shopt -u dotglob  # Don't include hidden directories
while IFS= read -r DIR
do
	# Extract sample identifier from directory name
	SAMPLE_ID=$(basename "$DIR")
	
	# Filter samples if --only-samples was specified
	if [ -n "$ONLY_SAMPLES" ]; then
		# Check if SAMPLE_ID is in the comma-separated list
		# Add commas around the list and the sample to avoid partial matches
		if [[ ",$ONLY_SAMPLES," != *",$SAMPLE_ID,"* ]]; then
			if [ -n "$EXPECTED_SAMPLES" ] && [ "$PROCESS_ALL" = false ]; then
				log_warning "Skipping $SAMPLE_ID (not declared in sample sheet)"
			else
				log_info "Skipping $SAMPLE_ID (not in --only-samples list)"
			fi
			SKIPPED_SAMPLES="$SKIPPED_SAMPLES $SAMPLE_ID"
			SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
			continue
		fi
	fi
	
	# Skip 'unclassified' folder unless --include-unclassified is set
	if [ "$SAMPLE_ID" = "unclassified" ] && [ "$INCLUDE_UNCLASSIFIED" = false ]; then
		log_info "Skipping unclassified folder (use --include-unclassified to process it)"
		continue
	fi
	
	log_info "Processing sample: $SAMPLE_ID"
	
	SAMPLES_COUNT=$((SAMPLES_COUNT+1))
	
	# Create output directory for this sample's logs
	OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
	mkdir -p "$OUT_DIR"
	SLURM_PRE="slurm-$SAMPLE_ID"
	
	# ============================================================
	# Submit demultmt workflow
	# ============================================================
	# Arguments passed to wf-demultmt.sh:
	#   $1: SAMPLE_ID - name of the sample directory in fastq_pass/
	# ============================================================
	if [ "$SKIP_DEMULTMT" = false ] && [ "$MODMITO_ONLY" = false ]; then
		WF_ID='demultmt'
		SLURM_OUT="$OUT_DIR/$SLURM_PRE.$WF_ID.out"
		SLURM_ERR="$OUT_DIR/$SLURM_PRE.$WF_ID.err"
		JOBID=$(sbatch --parsable \
			--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
			--chdir="$RUN_DIR" \
			--job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" \
			--output="$SLURM_OUT" \
			--error="$SLURM_ERR" \
			--mail-type="$MAIL_TYPE_ISSUE" \
			--mail-user="$MAIL_USER" \
			"$WF_DEMULTMT" "$SAMPLE_ID")
		
		if [ -z "$JOBID" ]; then
			log_error "Failed to submit $WF_ID job for $SAMPLE_ID"
			exit 1
		fi
		
	log_success "Submitted job $JOBID ($WF_ID)"
	log_info "  Output: $SLURM_OUT"
	log_info "  Error : $SLURM_ERR"
		JOBS_COUNT=$((JOBS_COUNT+1))
		DEMULTMT_JOBS=$((DEMULTMT_JOBS+1))
		JOBID_LIST="$JOBID $JOBID_LIST"
	fi
	
	# ============================================================
	# Submit modmito workflow (depends on demultmt completion)
	# ============================================================
	# Arguments passed to wf-modmito.sh:
	#   $1: SAMPLE_ID - name of the sample directory in fastq_pass/
	# 
	# Dependency: This job will only start after demultmt job completes successfully
	# ============================================================
	if [ "$SKIP_MODMITO" = false ] && [ "$DEMULTMT_ONLY" = false ]; then
	WF_ID='modmito'
	SLURM_OUT="$OUT_DIR/$SLURM_PRE.$WF_ID.out"
	SLURM_ERR="$OUT_DIR/$SLURM_PRE.$WF_ID.err"
		
		# If demultmt was submitted, add dependency
		if [ "$SKIP_DEMULTMT" = false ] && [ "$MODMITO_ONLY" = false ]; then
			JOBID_MODMITO=$(sbatch --dependency=afterok:"${JOBID}" \
				--parsable \
				--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
				--chdir="$RUN_DIR" \
				--job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" \
				--output="$SLURM_OUT" \
				--error="$SLURM_ERR" \
				--mail-type="$MAIL_TYPE_END" \
				--mail-user="$MAIL_USER" \
				"$WF_MODMITO" "$SAMPLE_ID")
		else
			# No dependency if demultmt was skipped
			JOBID_MODMITO=$(sbatch --parsable \
				--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
				--chdir="$RUN_DIR" \
				--job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" \
				--output="$SLURM_OUT" \
				--error="$SLURM_ERR" \
				--mail-type="$MAIL_TYPE_END" \
				--mail-user="$MAIL_USER" \
				"$WF_MODMITO" "$SAMPLE_ID")
		fi
		
		if [ -z "$JOBID_MODMITO" ]; then
			log_error "Failed to submit $WF_ID job for $SAMPLE_ID"
			exit 1
		fi
		
		# Log message depends on whether there was a dependency
		if [ "$SKIP_DEMULTMT" = false ] && [ "$MODMITO_ONLY" = false ]; then
			log_success "Submitted job $JOBID_MODMITO ($WF_ID, depends on $JOBID)"
		else
			log_success "Submitted job $JOBID_MODMITO ($WF_ID)"
		fi
	log_info "  Output: $SLURM_OUT"
	log_info "  Error : $SLURM_ERR"
		JOBS_COUNT=$((JOBS_COUNT+1))
		MODMITO_JOBS=$((MODMITO_JOBS+1))
		JOBID_LIST="$JOBID_MODMITO $JOBID_LIST"
	fi
	
# Read all directories (non-recursively) in fastq_pass/
done < <(find ./* -prune -type d)

echo ""
echo "=========================================="
echo "          SUBMISSION COMPLETED            "
echo "=========================================="

log_success "$SAMPLES_COUNT sample(s) processed"
log_success "$JOBS_COUNT job(s) submitted:"
log_info "  - demultmt: $DEMULTMT_JOBS jobs"
log_info "  - modmito: $MODMITO_JOBS jobs"

if [ $SKIPPED_COUNT -gt 0 ]; then
	echo ""
	log_warning "$SKIPPED_COUNT sample(s) skipped (not in sample sheet):$SKIPPED_SAMPLES"
fi

echo ""
echo "========== Job Management =========="
log_info "To cancel all submitted jobs:"
echo ""
echo "  scancel $JOBID_LIST"
echo ""
log_info "To monitor job status:"
echo ""
echo "  squeue -u \$USER"
echo ""
log_info "To check specific jobs:"
echo ""
echo "  squeue -j $JOBID_LIST"
echo "===================================="

END=$(date +%s)
RUNTIME=$((END - START))
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))

echo ""
log_success "Total runtime: $(printf '%02d:%02d:%02d' $HOURS $MINUTES $SECONDS)"
log_info "End time: $(date '+%Y-%m-%d %H:%M:%S')"

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > "$WORKFLOW_SUMMARY_FILE"
	log_success "Created workflow summary file"
fi
printf "%s\t%s\t%s\t%02d:%02d:%02d\n" "$RUN_ID" "NA" "subwf" "$HOURS" "$MINUTES" "$SECONDS" >> "$WORKFLOW_SUMMARY_FILE"
log_success "Updated workflow summary file: $WORKFLOW_SUMMARY_FILE"

echo ""
echo "=========================================="
log_info "Check detailed logs in processing/ directory"
echo "=========================================="

# Submit archiving and final notification jobs that depend on all submitted jobs
if [ -n "$JOBID_LIST" ]; then
	# Normalize spaces and build dependency list
	DEP_IDS=$(echo "$JOBID_LIST" | xargs)
	DEP_STR="afterok:$(echo "$DEP_IDS" | tr ' ' ':')"

	# Submit archiving job (unless --skip-archiving is set)
	if [ "$SKIP_ARCHIVING" = false ]; then
		ARCHIVING_DIR="${ARCHIVING_DIR:-/project/storage/path/$RUN_ID}"  # Define in nanomito.config
		ARCHIVE_OUT="$PROCESS_DIR/slurm-$RUN_ID.archive.out"
		
		ARCHIVE_JOBID=$(sbatch --parsable \
			--dependency="$DEP_STR" \
			--export=ALL \
			--chdir="$RUN_DIR" \
			--job-name="a${RUN_ID: -7}" \
			--output="$ARCHIVE_OUT" \
			"$SCRIPT_DIR/wf-archiving.sh" "$RUN_DIR" "$ARCHIVING_DIR")
		
		if [ -n "$ARCHIVE_JOBID" ]; then
			log_success "Submitted archiving job $ARCHIVE_JOBID (depends on all analysis jobs)"
			log_info "  Output: $ARCHIVE_OUT"
			log_info "  Destination: $ARCHIVING_DIR"
			
			# Finalize depends on archiving
			FINAL_DEP_STR="afterok:$ARCHIVE_JOBID"
		else
			log_error "Failed to submit archiving job"
			# Finalize depends on analysis jobs directly
			FINAL_DEP_STR="$DEP_STR"
		fi
	else
		log_info "Skipping archiving (--skip-archiving mode)"
		# Finalize depends on analysis jobs directly
		FINAL_DEP_STR="$DEP_STR"
	fi

	# Submit final notification job
	FINAL_OUT="$PROCESS_DIR/slurm-$RUN_ID.final.out"
	FINAL_JOBID=$(sbatch --parsable \
		--dependency="$FINAL_DEP_STR" \
		--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
		--chdir="$RUN_DIR" \
		--job-name="f${RUN_ID: -7}" \
		--output="$FINAL_OUT" \
		"$SCRIPT_DIR/wf-finalize.sh")

	if [ -n "$FINAL_JOBID" ]; then
		if [ "$SKIP_ARCHIVING" = false ] && [ -n "$ARCHIVE_JOBID" ]; then
			log_success "Submitted final notification job $FINAL_JOBID (depends on archiving)"
		else
			log_success "Submitted final notification job $FINAL_JOBID (depends on all jobs)"
		fi
		log_info "  Output: $FINAL_OUT"
	else
		log_error "Failed to submit final notification job"
	fi
fi