#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh /Path/to/run/dir/
#
# Strict error handling
set -euo pipefail

# Trap for cleanup on error
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "[ERROR] Script failed with exit code $exit_code at $(date)"
    fi
}
trap cleanup EXIT

VERSION='25.10.26.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Logging helper functions
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

if [ $# -eq 0 ]
	then
		log_error "No arguments supplied"
		echo "Usage: $0 /Path/to/run/dir/"
		exit 128 # die with error
fi

# Validate run directory
if [ ! -d "$1" ]; then
	log_error "Directory $1 does not exist"
	exit 128
fi

cd "$1"

# Directories
RUN_DIR=$(pwd)
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=$(basename "$RUN_DIR")
SLURM_PRE="slurm-$RUN_ID"
SLURM_EXT='log'

# Workflow files
WF_BCHG='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-bchg.sh'
WF_SUBWF='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-subwf.sh'

# Validate workflow files exist
if [ ! -f "$WF_BCHG" ]; then
	log_error "Workflow file not found: $WF_BCHG"
	exit 128
fi
if [ ! -f "$WF_SUBWF" ]; then
	log_error "Workflow file not found: $WF_SUBWF"
	exit 128
fi

# Mail parameters
MAIL_USER='marc.ferre@univ-angers.fr'
MAIL_TYPE_END='END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_ISSUE='FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
# MAIL_TYPE_NONE='NONE'
# MAIL_TYPE_ALL='ALL'

echo ""
echo "=========================================="
echo "   NANOMITO WORKFLOW SUBMISSION v.$VERSION"
echo "=========================================="
log_info "Author: $AUTHOR"
log_info "Run directory: $RUN_DIR"
log_info "Run ID: $RUN_ID"
echo ""

# Create processing directory if it doesn't exist
if [ ! -d "$PROCESS_DIR" ]; then
	mkdir -p "$PROCESS_DIR"
	log_success "Created processing directory: $PROCESS_DIR"
else
	log_info "Processing directory exists: $PROCESS_DIR"
fi

JOBID_LIST=''
JOBS_COUNT=0

echo "=========================================="
echo "   STEP 1/2: BASECALLING & DEMUX (bchg)"
echo "=========================================="

WF_ID='bchg'
SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" $WF_BCHG "$RUN_DIR")

log_success "Submitted batch job $JOBID"
log_info "Output file: $SLURM_FILE"
JOBID_LIST="$JOBID $JOBID_LIST"
JOBS_COUNT=$((JOBS_COUNT + 1))

echo ""
echo "=========================================="
echo "   STEP 2/2: SUB-WORKFLOWS (subwf)"
echo "=========================================="

WF_ID='subwf'
SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

JOBID=$(sbatch --dependency=afterok:"${JOBID}" --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" $WF_SUBWF)

log_success "Submitted batch job $JOBID (depends on previous job)"
log_info "Output file: $SLURM_FILE"
JOBID_LIST="$JOBID $JOBID_LIST"
JOBS_COUNT=$((JOBS_COUNT + 1))

echo ""
echo "=========================================="
echo "          SUBMISSION COMPLETED"
echo "=========================================="
log_success "$JOBS_COUNT batch job(s) submitted"
echo ""
log_info "Use following command to cancel all jobs:"
echo "  scancel $JOBID_LIST"
echo ""
