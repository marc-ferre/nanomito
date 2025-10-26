#!/bin/bash
#
# Archiving a run
#
# archiving.sh /Path/to/run/dir/
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

WF_ARCHIVING='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-archiving.sh'

PROJECTS_DIR='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/projects'

# Validate workflow file exists
if [ ! -f "$WF_ARCHIVING" ]; then
	log_error "Workflow file not found: $WF_ARCHIVING"
	exit 128
fi

# Validate projects directory exists
if [ ! -d "$PROJECTS_DIR" ]; then
	log_error "Projects directory not found: $PROJECTS_DIR"
	exit 128
fi

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

echo ""
echo -e "${BOLD}${CYAN}==========================================${NC}"
echo -e "${BOLD}${CYAN}     RUN ARCHIVING v.$VERSION${NC}"
echo -e "${BOLD}${CYAN}==========================================${NC}"
log_info "Author: $AUTHOR"
echo ""

cd "$1"
RUN_DIR=$(pwd)
RUN_ID=$(basename "$RUN_DIR")
log_info "Run directory: $RUN_DIR"
log_info "Run ID: $RUN_ID"

ARCHIVING_DIR="$PROJECTS_DIR/$RUN_ID"
echo ""
if [ -d "$ARCHIVING_DIR" ]; then
    log_warning "Archiving directory already exists: $ARCHIVING_DIR"
    echo ""
    echo "Do you want to overwrite it? (y/n)"
    read -r YN
    if [ "$YN" = "y" ] || [ "$YN" = "Y" ]; then
        log_info "Overwriting existing archive..."
    else
    	log_info "Operation cancelled by user"
        exit 0
    fi
else
	mkdir -p "$ARCHIVING_DIR"
	log_success "Created archiving directory: $ARCHIVING_DIR"
fi    

echo ""
echo -e "${BOLD}${CYAN}==========================================${NC}"
echo -e "${BOLD}${CYAN}     SUBMITTING ARCHIVING JOB${NC}"
echo -e "${BOLD}${CYAN}==========================================${NC}"

SLURM_FILE="$PROJECTS_DIR/slurm-$RUN_ID.log"

JOBID=$(sbatch --parsable --job-name="a${RUN_ID: -7}" --output="$SLURM_FILE" $WF_ARCHIVING "$RUN_DIR" "$ARCHIVING_DIR")

if [ -n "$JOBID" ]; then
	log_success "Submitted batch job $JOBID"
	log_info "Output file: $SLURM_FILE"
	log_info "Archiving to: $ARCHIVING_DIR"
	echo ""
	echo -e "${BOLD}${GREEN}==========================================${NC}"
	log_info "Use '${YELLOW}scancel $JOBID${NC}' to cancel the job"
	echo -e "${BOLD}${GREEN}==========================================${NC}"
else
	log_error "Failed to submit batch job"
	exit 1
fi