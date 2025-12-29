#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
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
#   --archiving-only  Only submit archiving job (archives existing data)
#   --skip-archiving  Skip archiving step in the workflow
#   --finalize-only   Only submit finalization job (email report from existing data)
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

VERSION='2.0.0'
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
ARCHIVING_ONLY=false
SKIP_ARCHIVING=false
FINALIZE_ONLY=false
INCLUDE_UNCLASSIFIED=false
ONLY_SAMPLES=""
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
		--archiving-only)
			ARCHIVING_ONLY=true
			shift
			;;
		--skip-archiving)
			SKIP_ARCHIVING=true
			shift
			;;
		--finalize-only)
			FINALIZE_ONLY=true
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
	echo "  --bchg-only             Only submit basecalling/demux workflow (wf-bchg.sh)"
	echo "  --skip-bchg             Skip basecalling/demux, only submit analysis workflows"
	echo "  --demultmt-only         Only submit demultmt workflow (requires --skip-bchg)"
	echo "  --skip-demultmt         Skip demultmt workflow, only submit modmito"
	echo "  --modmito-only          Only submit modmito workflow (requires --skip-bchg)"
	echo "  --skip-modmito          Skip modmito workflow, only submit demultmt"
	echo "  --archiving-only        Only submit archiving job (archives existing data)"
	echo "  --skip-archiving        Skip archiving step in the workflow"
	echo "  --finalize-only         Only submit finalization job (email report from existing data)"
	echo "  --include-unclassified  Include 'unclassified' folder in sample processing"
	echo "  --only-samples SAMPLES  Process only specified samples (comma-separated list)"
	echo "  --help, -h              Display this help message"
	echo ""
	echo "Examples:"
	echo "  $0 /path/to/run_directory/"
	echo "  $0 --bchg-only /path/to/run_directory/"
	echo "  $0 --skip-bchg /path/to/run_directory/"
	echo "  $0 --skip-bchg --demultmt-only /path/to/run_directory/"
	echo "  $0 --skip-bchg --modmito-only /path/to/run_directory/"
	echo "  $0 --skip-bchg --include-unclassified /path/to/run_directory/"
	echo "  $0 --only-samples SAMPLE1,SAMPLE2 /path/to/run_directory/"
	echo "  $0 --skip-bchg --only-samples SAMPLE1,SAMPLE2 /path/to/run_directory/"
	echo "  $0 --archiving-only /path/to/run_directory/"
	echo "  $0 --finalize-only /path/to/run_directory/"
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

if [ "$ARCHIVING_ONLY" = true ] && [ "$SKIP_ARCHIVING" = true ]; then
	log_error "Cannot use --archiving-only and --skip-archiving together"
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

# Load global configuration BEFORE changing directory
# Get absolute path to script directory (works even with relative paths and symlinks)
# Use BASH_SOURCE when available (sbatch), fallback to $0 for direct execution
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [ -L "$SCRIPT_PATH" ]; then
    # Script is a symlink, resolve it
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
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
# shellcheck disable=SC1091
source "$CONFIG_FILE"

# Export SCRIPT_DIR for use by sbatch-ed workflows
export NANOMITO_DIR="$SCRIPT_DIR"

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

# Get archiving configuration
ARCHIVING_DIR="${ARCHIVING_DIR:-/project/storage/path/$RUN_ID}"  # Define in nanomito.config

# SPECIAL CASE: --archiving-only to archive existing data
if [ "$ARCHIVING_ONLY" = true ]; then
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   ARCHIVING ONLY MODE${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	log_info "Submitting archiving job only (no dependencies)"
	log_info "This will archive data from $RUN_DIR to $ARCHIVING_DIR"
	echo ""
	
	ARCHIVE_OUT="$PROCESS_DIR/slurm-$RUN_ID.archive.out"
	ARCHIVE_JOBID=$(sbatch --parsable \
		--export=ALL \
		--chdir="$RUN_DIR" \
		--job-name="a${RUN_ID: -7}" \
		--output="$ARCHIVE_OUT" \
		"$SCRIPT_DIR/wf-archiving.sh" "$RUN_DIR" "$ARCHIVING_DIR")
	
	if [ -n "$ARCHIVE_JOBID" ]; then
		log_success "Submitted archiving job $ARCHIVE_JOBID"
		log_info "  Output: $ARCHIVE_OUT"
		log_info "  Destination: $ARCHIVING_DIR"
		echo ""
		log_success "Archiving will complete when job finishes"
	else
		log_error "Failed to submit archiving job"
		exit 1
	fi
	
	exit 0
fi

# SPECIAL CASE: --finalize-only to test email report
if [ "$FINALIZE_ONLY" = true ]; then
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   FINALIZE ONLY MODE${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	log_info "Submitting finalization job only (no dependencies)"
	log_info "This will generate an email report from existing data"
	echo ""
	
	FINAL_OUT="$PROCESS_DIR/slurm-$RUN_ID.final.out"
	FINAL_JOBID=$(sbatch --parsable \
		--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
		--chdir="$RUN_DIR" \
		--job-name="f${RUN_ID: -7}" \
		--output="$FINAL_OUT" \
		"$SCRIPT_DIR/wf-finalize.sh" --reports-only "$RUN_DIR")
	
	if [ -n "$FINAL_JOBID" ]; then
		log_success "Submitted finalization job $FINAL_JOBID"
		log_info "  Output: $FINAL_OUT"
		echo ""
		log_success "Email report will be sent when job completes"
	else
		log_error "Failed to submit finalization job"
		exit 1
	fi
	
	exit 0
fi

# STEP 1: Submit basecalling & demux if not skipped
if [ "$SKIP_BCHG" = false ]; then
	echo -e "${BOLD}${CYAN}==========================================${NC}"
	echo -e "${BOLD}${CYAN}   STEP 1: BASECALLING & DEMUX (bchg)${NC}"
	echo -e "${BOLD}${CYAN}==========================================${NC}"

	WF_ID='bchg'
	SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

	BCHG_JOBID=$(sbatch --parsable --export=ALL,NANOMITO_DIR="$SCRIPT_DIR" --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_BCHG" "$RUN_DIR")

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
	if [ "$INCLUDE_UNCLASSIFIED" = true ]; then
		SUBWF_ARGS="$SUBWF_ARGS --include-unclassified"
	fi
	if [ -n "$ONLY_SAMPLES" ]; then
		SUBWF_ARGS="$SUBWF_ARGS --only-samples $ONLY_SAMPLES"
	fi
	
	# Submit wf-subwf.sh which will discover samples and submit demultmt/modmito jobs
	WF_ID='subwf'
	SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"
	
	# Add dependency on bchg job if it was submitted
	if [ -n "$BCHG_JOBID" ]; then
		# shellcheck disable=SC2086  # SUBWF_ARGS intentionally unquoted for word splitting
		SUBWF_JOBID=$(sbatch --dependency=afterok:"$BCHG_JOBID" --parsable --export=ALL,NANOMITO_DIR="$SCRIPT_DIR" --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_SUBWF" $SUBWF_ARGS)
		log_success "Submitted batch job $SUBWF_JOBID (depends on $BCHG_JOBID)"
	else
		# shellcheck disable=SC2086  # SUBWF_ARGS intentionally unquoted for word splitting
		SUBWF_JOBID=$(sbatch --parsable --export=ALL,NANOMITO_DIR="$SCRIPT_DIR" --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" "$WF_SUBWF" $SUBWF_ARGS)
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

# Submit archiving and finalization jobs
# Note: When SUBWF is used, wf-subwf.sh handles archiving/finalize submission with proper dependencies
# Here we only submit archiving/finalize for special modes (--skip-bchg, --bchg-only, etc.)
if [ -z "$SUBWF_JOBID" ]; then
	# No SUBWF job - submit archiving/finalize directly
	if [ "$SKIP_ARCHIVING" = false ] && [ "$BCHG_ONLY" = false ]; then
		echo ""
		echo -e "${BOLD}${CYAN}==========================================${NC}"
		echo -e "${BOLD}${CYAN}   SUBMITTING ARCHIVING JOB${NC}"
		echo -e "${BOLD}${CYAN}==========================================${NC}"
		
		ARCHIVE_OUT="$PROCESS_DIR/slurm-$RUN_ID.archive.out"
		
		# Archive depends on bchg job if it exists
		if [ -n "$BCHG_JOBID" ]; then
			ARCHIVE_JOBID=$(sbatch --dependency=afterok:"$BCHG_JOBID" --parsable \
				--export=ALL \
				--chdir="$RUN_DIR" \
				--job-name="a${RUN_ID: -7}" \
				--output="$ARCHIVE_OUT" \
				"$SCRIPT_DIR/wf-archiving.sh" "$RUN_DIR" "$ARCHIVING_DIR")
			log_success "Submitted archiving job $ARCHIVE_JOBID (depends on $BCHG_JOBID)"
		else
			ARCHIVE_JOBID=$(sbatch --parsable \
				--export=ALL \
				--chdir="$RUN_DIR" \
				--job-name="a${RUN_ID: -7}" \
				--output="$ARCHIVE_OUT" \
				"$SCRIPT_DIR/wf-archiving.sh" "$RUN_DIR" "$ARCHIVING_DIR")
			log_success "Submitted archiving job $ARCHIVE_JOBID"
		fi
		
		log_info "  Output: $ARCHIVE_OUT"
		log_info "  Destination: $ARCHIVING_DIR"
		JOBID_LIST="$ARCHIVE_JOBID $JOBID_LIST"
		JOBS_COUNT=$((JOBS_COUNT + 1))
		echo ""
		
		# Submit finalization job that depends on archiving
		echo -e "${BOLD}${CYAN}==========================================${NC}"
		echo -e "${BOLD}${CYAN}   SUBMITTING FINALIZATION JOB${NC}"
		echo -e "${BOLD}${CYAN}==========================================${NC}"
		
		FINAL_OUT="$PROCESS_DIR/slurm-$RUN_ID.final.out"
		FINAL_JOBID=$(sbatch --dependency=afterok:"$ARCHIVE_JOBID" --parsable \
			--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
			--chdir="$RUN_DIR" \
			--job-name="f${RUN_ID: -7}" \
			--output="$FINAL_OUT" \
			"$SCRIPT_DIR/wf-finalize.sh")
		
		log_success "Submitted finalization job $FINAL_JOBID (depends on $ARCHIVE_JOBID)"
		log_info "  Output: $FINAL_OUT"
		log_info "  Email report will be sent when job completes"
		JOBID_LIST="$FINAL_JOBID $JOBID_LIST"
		JOBS_COUNT=$((JOBS_COUNT + 1))
		echo ""
	else
		if [ "$SKIP_ARCHIVING" = true ]; then
			log_info "Skipping archiving (--skip-archiving mode)"
		fi
		
		# Submit finalization job without archiving dependency
		if [ "$BCHG_ONLY" = false ]; then
			echo ""
			echo -e "${BOLD}${CYAN}==========================================${NC}"
			echo -e "${BOLD}${CYAN}   SUBMITTING FINALIZATION JOB${NC}"
			echo -e "${BOLD}${CYAN}==========================================${NC}"
			
			FINAL_OUT="$PROCESS_DIR/slurm-$RUN_ID.final.out"
			
			if [ -n "$BCHG_JOBID" ]; then
				FINAL_JOBID=$(sbatch --dependency=afterok:"$BCHG_JOBID" --parsable \
					--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
					--chdir="$RUN_DIR" \
					--job-name="f${RUN_ID: -7}" \
					--output="$FINAL_OUT" \
					"$SCRIPT_DIR/wf-finalize.sh")
				log_success "Submitted finalization job $FINAL_JOBID (depends on $BCHG_JOBID)"
			else
				FINAL_JOBID=$(sbatch --parsable \
					--export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
					--chdir="$RUN_DIR" \
					--job-name="f${RUN_ID: -7}" \
					--output="$FINAL_OUT" \
					"$SCRIPT_DIR/wf-finalize.sh")
				log_success "Submitted finalization job $FINAL_JOBID"
			fi
			
			log_info "  Output: $FINAL_OUT"
			log_info "  Email report will be sent when job completes"
			JOBID_LIST="$FINAL_JOBID $JOBID_LIST"
			JOBS_COUNT=$((JOBS_COUNT + 1))
			echo ""
		fi
	fi
else
	# SUBWF job exists - archiving/finalize handled by wf-subwf.sh
	log_info "Archiving and finalization will be submitted by wf-subwf.sh"
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
