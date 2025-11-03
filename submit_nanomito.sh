#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh [OPTIONS] /Path/to/run/dir/
#
# Options:
#   --bchg-only       Only submit basecalling/demux workflow (wf-bchg.sh)
#   --skip-bchg       Skip basecalling/demux, only submit analysis workflows
#   --demultmt-only   Only submit demultmt workflow (requires --skip-bchg)
#   --skip-demultmt   Skip demultmt workflow, only submit modmito
#   --modmito-only    Only submit modmito workflow (requires --skip-bchg)
#   --skip-modmito    Skip modmito workflow, only submit demultmt
#   --help            Display this help message
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
DEMULTMT_ONLY=false
SKIP_DEMULTMT=false
MODMITO_ONLY=false
SKIP_MODMITO=false
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
	echo "  --bchg-only       Only submit basecalling/demux workflow (wf-bchg.sh)"
	echo "  --skip-bchg       Skip basecalling/demux, only submit analysis workflows"
	echo "  --demultmt-only   Only submit demultmt workflow (requires --skip-bchg)"
	echo "  --skip-demultmt   Skip demultmt workflow, only submit modmito"
	echo "  --modmito-only    Only submit modmito workflow (requires --skip-bchg)"
	echo "  --skip-modmito    Skip modmito workflow, only submit demultmt"
	echo "  --help, -h        Display this help message"
	echo ""
	echo "Examples:"
	echo "  $0 /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --bchg-only /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --skip-bchg /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --skip-bchg --demultmt-only /scratch/mferre/workbench/250916_MK1B_RUN15/"
	echo "  $0 --skip-bchg --modmito-only /scratch/mferre/workbench/250916_MK1B_RUN15/"
	exit 0
fi

# Check for conflicting options
if [ "$BCHG_ONLY" = true ] && [ "$SKIP_BCHG" = true ]; then
	log_error "Cannot use --bchg-only and --skip-bchg together"
	exit 128
fi

if [ "$DEMULTMT_ONLY" = true ] && [ "$SKIP_DEMULTMT" = true ]; then
	log_error "Cannot use --demultmt-only and --skip-demultmt together"
	exit 128
fi

if [ "$MODMITO_ONLY" = true ] && [ "$SKIP_MODMITO" = true ]; then
	log_error "Cannot use --modmito-only and --skip-modmito together"
	exit 128
fi

if [ "$DEMULTMT_ONLY" = true ] && [ "$MODMITO_ONLY" = true ]; then
	log_error "Cannot use --demultmt-only and --modmito-only together"
	exit 128
fi

if [ "$SKIP_DEMULTMT" = true ] && [ "$SKIP_MODMITO" = true ]; then
	log_error "Cannot skip both demultmt and modmito workflows"
	exit 128
fi

# Analysis-only options require --skip-bchg
if [ "$SKIP_BCHG" = false ]; then
	if [ "$DEMULTMT_ONLY" = true ] || [ "$MODMITO_ONLY" = true ]; then
		log_error "Options --demultmt-only and --modmito-only require --skip-bchg"
		exit 128
	fi
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

# Load global configuration
# Get absolute path to script directory (works even with relative paths and symlinks)
if [ -L "$0" ]; then
    # Script is a symlink, resolve it
    SCRIPT_PATH="$(readlink "$0")"
else
    SCRIPT_PATH="$0"
fi

# Get absolute directory path
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac

CONFIG_FILE="$SCRIPT_DIR/nanomito.config"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_error "Script path: $0"
    log_error "Script directory: $SCRIPT_DIR"
    exit 1
fi

# shellcheck source=nanomito.config
source "$CONFIG_FILE"

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
	check_workflow "$WF_SUBWF"
fi

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
	echo -e "${BOLD}${CYAN}   STEP 2: ANALYSIS WORKFLOWS (subwf)${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	
	# Build arguments for wf-subwf.sh based on options
	SUBWF_ARGS=""
	if [ "$DEMULTMT_ONLY" = true ]; then
		SUBWF_ARGS="$SUBWF_ARGS --demultmt-only"
	fi
	if [ "$SKIP_DEMULTMT" = true ]; then
		SUBWF_ARGS="$SUBWF_ARGS --skip-demultmt"
	fi
	if [ "$MODMITO_ONLY" = true ]; then
		SUBWF_ARGS="$SUBWF_ARGS --modmito-only"
	fi
	if [ "$SKIP_MODMITO" = true ]; then
		SUBWF_ARGS="$SUBWF_ARGS --skip-modmito"
	fi
	
	# Submit wf-subwf.sh which will discover samples and submit demultmt/modmito jobs
	WF_ID='subwf'
	SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"
	
	# Add dependency on bchg job if it was submitted
	if [ -n "$BCHG_JOBID" ]; then
		SUBWF_JOBID=$(sbatch --dependency=afterok:"$BCHG_JOBID" --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_SUBWF" $SUBWF_ARGS)
		log_success "Submitted batch job $SUBWF_JOBID (depends on $BCHG_JOBID)"
	else
		SUBWF_JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_SUBWF" $SUBWF_ARGS)
		log_success "Submitted batch job $SUBWF_JOBID"
	fi
	
	log_info "Output file: $SLURM_FILE"
	if [ -n "$SUBWF_ARGS" ]; then
		log_info "Options:$SUBWF_ARGS"
	fi
	log_info "wf-subwf.sh will discover samples and submit demultmt/modmito jobs"
	JOBID_LIST="$SUBWF_JOBID $JOBID_LIST"
	JOBS_COUNT=$((JOBS_COUNT + 1))
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
