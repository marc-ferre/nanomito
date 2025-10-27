#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh [OPTIONS] /Path/to/run/dir/
#
# Options:
#   --bchg-only    Only submit basecalling/demux workflow (wf-bchg.sh)
#   --help         Display this help message
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

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging helper functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_success() {
	echo -e "${GREEN}[OK]${NC}   $(date '+%H:%M:%S') - $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1" >&2
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $1"
}

# Parse options
BCHG_ONLY=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
	case $1 in
		--bchg-only)
			BCHG_ONLY=true
			shift
			;;
		--help|-h)
			SHOW_HELP=true
			shift
			;;
		*)
			# Assume it's the run directory
			RUN_DIR_ARG="$1"
			shift
			;;
	esac
done

if [ "$SHOW_HELP" = true ]; then
	echo "Usage: $0 [OPTIONS] /Path/to/run/dir/"
	echo ""
	echo "Options:"
	echo "  --bchg-only    Only submit basecalling/demux workflow (wf-bchg.sh)"
	echo "  --help, -h     Display this help message"
	echo ""
	echo "Examples:"
	echo "  $0 /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --bchg-only /scratch/mferre/workbench/250916_MK1B_RUN15/"
	exit 0
fi

if [ -z "${RUN_DIR_ARG:-}" ]; then
	log_error "No run directory supplied"
	echo "Usage: $0 [OPTIONS] /Path/to/run/dir/"
	echo "Use --help for more information"
	exit 128
fi

# Validate run directory
if [ ! -d "$RUN_DIR_ARG" ]; then
	log_error "Directory $RUN_DIR_ARG does not exist"
	exit 128
fi

cd "$RUN_DIR_ARG"

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
echo -e "${BOLD}${CYAN}==========================================${NC}"
echo -e "${BOLD}${CYAN}   NANOMITO WORKFLOW SUBMISSION v.$VERSION${NC}"
echo -e "${BOLD}${CYAN}==========================================${NC}"
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

echo -e "${BOLD}${CYAN}==========================================${NC}"
echo -e "${BOLD}${CYAN}   STEP 1/2: BASECALLING & DEMUX (bchg)${NC}"
echo -e "${BOLD}${CYAN}==========================================${NC}"

WF_ID='bchg'
SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" $WF_BCHG "$RUN_DIR")

log_success "Submitted batch job $JOBID"
log_info "Output file: $SLURM_FILE"
JOBID_LIST="$JOBID $JOBID_LIST"
JOBS_COUNT=$((JOBS_COUNT + 1))

# Only submit sub-workflows if not in bchg-only mode
if [ "$BCHG_ONLY" = false ]; then
	echo ""
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   STEP 2/2: SUB-WORKFLOWS (subwf)${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"

	WF_ID='subwf'
	SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

	JOBID=$(sbatch --dependency=afterok:"${JOBID}" --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" $WF_SUBWF)

	log_success "Submitted batch job $JOBID (depends on previous job)"
	log_info "Output file: $SLURM_FILE"
	JOBID_LIST="$JOBID $JOBID_LIST"
	JOBS_COUNT=$((JOBS_COUNT + 1))
else
	log_info "Skipping sub-workflows (--bchg-only mode)"
fi

echo ""
echo -e "${BOLD}${GREEN}==========================================${NC}"
echo -e "${BOLD}${GREEN}          SUBMISSION COMPLETED${NC}"
echo -e "${BOLD}${GREEN}==========================================${NC}"
log_success "$JOBS_COUNT batch job(s) submitted"
echo ""
log_info "Use following command to cancel all jobs:"
echo -e "  ${YELLOW}scancel $JOBID_LIST${NC}"
echo ""
