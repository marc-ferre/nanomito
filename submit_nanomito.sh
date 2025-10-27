#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh [OPTIONS] /Path/to/run/dir/
#
# Options:
#   --bchg-only    Only submit basecalling/demux workflow (wf-bchg.sh)
#   --skip-bchg    Skip basecalling/demux, only submit analysis workflows
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
SKIP_BCHG=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
	case $1 in
		--bchg-only)
			BCHG_ONLY=true
			shift
			;;
		--skip-bchg)
			SKIP_BCHG=true
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
	echo "  --skip-bchg    Skip basecalling/demux, only submit analysis workflows"
	echo "  --help, -h     Display this help message"
	echo ""
	echo "Examples:"
	echo "  $0 /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --bchg-only /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --skip-bchg /scratch/mferre/workbench/250916_MK1B_RUN15/"
	exit 0
fi

# Check for conflicting options
if [ "$BCHG_ONLY" = true ] && [ "$SKIP_BCHG" = true ]; then
	log_error "Cannot use --bchg-only and --skip-bchg together"
	exit 128
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
SLURM_EXT='out'

# Workflow files
WF_BCHG='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/nanomito/wf-bchg.sh'
WF_DEMULTMT='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/nanomito/wf-demultmt.sh'
WF_MODMITO='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/nanomito/wf-modmito.sh'

# Validate workflow files exist
check_workflow() {
	local wf_path=$1
	if [ ! -f "$wf_path" ]; then
		log_error "Workflow file not found: $wf_path"
		exit 128
	fi
}

if [ "$SKIP_BCHG" = false ]; then
	check_workflow "$WF_BCHG"
fi
if [ "$BCHG_ONLY" = false ]; then
	check_workflow "$WF_DEMULTMT"
	check_workflow "$WF_MODMITO"
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
BCHG_JOBID=''

# STEP 1: Submit basecalling & demux if not skipped
if [ "$SKIP_BCHG" = false ]; then
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   STEP 1: BASECALLING & DEMUX (bchg)${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"

	WF_ID='bchg'
	SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

	BCHG_JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_BCHG" "$RUN_DIR")

	log_success "Submitted batch job $BCHG_JOBID"
	log_info "Output file: $SLURM_FILE"
	JOBID_LIST="$BCHG_JOBID $JOBID_LIST"
	JOBS_COUNT=$((JOBS_COUNT + 1))
	echo ""
else
	log_info "Skipping basecalling/demux (--skip-bchg mode)"
	echo ""
fi

# STEP 2: Submit analysis workflows for each sample if not in bchg-only mode
if [ "$BCHG_ONLY" = false ]; then
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   STEP 2: ANALYSIS WORKFLOWS${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"

	# Navigate to fastq_pass directory
	FASTQ_DIR="$RUN_DIR/fastq_pass"
	if [ ! -d "$FASTQ_DIR" ]; then
		log_error "FASTQ directory not found: $FASTQ_DIR"
		exit 128
	fi

	cd "$FASTQ_DIR" || exit 128

	# Find all sample directories
	SAMPLES=()
	while IFS= read -r -d '' sample; do
		SAMPLES+=("$sample")
	done < <(find ./* -prune -type d -print0)

	SAMPLES_COUNT=${#SAMPLES[@]}
	log_info "Found $SAMPLES_COUNT sample(s) to process"

	if [ "$SAMPLES_COUNT" -eq 0 ]; then
		log_error "No samples found in $FASTQ_DIR"
		exit 128
	fi

	echo ""

	DEMULTMT_JOBS=0
	MODMITO_JOBS=0

	# Submit workflows for each sample
	for sample in "${SAMPLES[@]}"; do
		SAMPLE_ID=$(basename "$sample")
		log_info "Processing sample: $SAMPLE_ID"

		SAMPLE_DIR="$FASTQ_DIR/$SAMPLE_ID"
		SAMPLE_PROCESS_DIR="$PROCESS_DIR/$SAMPLE_ID"

		# Create sample processing directory
		if [ ! -d "$SAMPLE_PROCESS_DIR" ]; then
			mkdir -p "$SAMPLE_PROCESS_DIR"
		fi

		# Submit demultmt workflow
		WF_ID='demultmt'
		SLURM_FILE="$SAMPLE_PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"
		
		# Add dependency on bchg job if it was submitted
		if [ -n "$BCHG_JOBID" ]; then
			DEMULTMT_JOBID=$(sbatch --dependency=afterok:"$BCHG_JOBID" --parsable --chdir="$SAMPLE_DIR" --job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_DEMULTMT")
		else
			DEMULTMT_JOBID=$(sbatch --parsable --chdir="$SAMPLE_DIR" --job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_DEMULTMT")
		fi

		log_success "  └─ demultmt: job $DEMULTMT_JOBID"
		JOBID_LIST="$DEMULTMT_JOBID $JOBID_LIST"
		JOBS_COUNT=$((JOBS_COUNT + 1))
		DEMULTMT_JOBS=$((DEMULTMT_JOBS + 1))

		# Submit modmito workflow (depends on demultmt)
		WF_ID='modmito'
		SLURM_FILE="$SAMPLE_PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

		MODMITO_JOBID=$(sbatch --dependency=afterok:"$DEMULTMT_JOBID" --parsable --chdir="$SAMPLE_DIR" --job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" "$WF_MODMITO")

		log_success "  └─ modmito:  job $MODMITO_JOBID (depends on $DEMULTMT_JOBID)"
		JOBID_LIST="$MODMITO_JOBID $JOBID_LIST"
		JOBS_COUNT=$((JOBS_COUNT + 1))
		MODMITO_JOBS=$((MODMITO_JOBS + 1))

		echo ""
	done

	cd "$RUN_DIR" || exit 128

	log_success "Submitted $DEMULTMT_JOBS demultmt job(s)"
	log_success "Submitted $MODMITO_JOBS modmito job(s)"
	echo ""
else
	log_info "Skipping analysis workflows (--bchg-only mode)"
	echo ""
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
