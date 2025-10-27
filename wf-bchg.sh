#!/bin/bash
#SBATCH --job-name=bchg
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 2-00:00:00
#SBATCH --output=processing/slurm-%x.%j.out
#SBATCH --error=processing/slurm-%x.%j.err
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_80
#SBATCH --mail-user=marc.ferre@univ-angers.fr
#
#
# wf-bchg.sh /Path/to/run/dir/
#
#
# Strict error handling
set -euo pipefail

# Trap for cleanup on error
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "[ERROR] Script failed with exit code $exit_code at $(date)"
        echo "[INFO] Check logs in processing/ directory"
    fi
}
trap cleanup EXIT

VERSION='25.10.26.2'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Directories
RUN_DIR=$(pwd)
POD5_DIR="$RUN_DIR/pod5_chrM"
FASTQ_DIR="$RUN_DIR/fastq_pass"
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=$(basename "$RUN_DIR")

# Files - Robust handling of multiple sample_sheet files
mapfile -t SAMPLESHEET_FILES < <(find "$RUN_DIR" -maxdepth 2 -type f -name 'sample_sheet_*.csv')

if [ ${#SAMPLESHEET_FILES[@]} -eq 0 ]; then
    echo "[ERROR] No sample_sheet_*.csv file found in $RUN_DIR or subdirectories"
    echo "Looking for files matching: sample_sheet_*.csv"
    echo "Available CSV files:"
    find "$RUN_DIR" -maxdepth 2 -type f -name '*.csv'
    exit 128
elif [ ${#SAMPLESHEET_FILES[@]} -eq 1 ]; then
    SAMPLESHEET_FILE=$(readlink -f "${SAMPLESHEET_FILES[0]}")
    echo "[OK] Found 1 sample_sheet file: $SAMPLESHEET_FILE"
else
    echo "[WARNING] Found ${#SAMPLESHEET_FILES[@]} sample_sheet files:"
    for file in "${SAMPLESHEET_FILES[@]}"; do
        echo "  - $file"
    done
    
    # Check if all files have identical content (ignoring first column: protocol_run_id)
    FIRST_FILE="${SAMPLESHEET_FILES[0]}"
    ALL_IDENTICAL=true
    
    for ((i=1; i<${#SAMPLESHEET_FILES[@]}; i++)); do
        # Compare files ignoring the first column
        DIFF_OUTPUT=$(diff <(cut -d, -f2- "$FIRST_FILE") <(cut -d, -f2- "${SAMPLESHEET_FILES[$i]}"))
        if [ -n "$DIFF_OUTPUT" ]; then
            ALL_IDENTICAL=false
            echo "[ERROR] Sample sheet files have different content (excluding protocol_run_id):"
            echo "  - $FIRST_FILE"
            echo "  - ${SAMPLESHEET_FILES[$i]}"
            echo "Differences found:"
            echo "$DIFF_OUTPUT"
            echo ""
            echo "Please keep only one sample_sheet file or ensure they are identical (except protocol_run_id)."
            exit 128
        fi
    done
    
    if [ "$ALL_IDENTICAL" = true ]; then
        echo "[OK] All sample_sheet files have identical content (protocol_run_id may differ)"
        # Select the oldest file (first created)
        OLDEST_FILE="${SAMPLESHEET_FILES[0]}"
        for file in "${SAMPLESHEET_FILES[@]}"; do
            if [ "$file" -ot "$OLDEST_FILE" ]; then
                OLDEST_FILE="$file"
            fi
        done
        SAMPLESHEET_FILE=$(readlink -f "$OLDEST_FILE")
        echo "[OK] Using oldest file: $SAMPLESHEET_FILE"
    fi
fi

WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

# Basecalling options
MODEL='sup'
KIT='SQK-NBD114-24'

# Binary and Conda env
# shellcheck disable=SC2034  # DORADO_BIN used in basecalling pipeline below
DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado'
BCHG_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_bchg'

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

log_step "1/5: INITIALIZATION"
log_info "Workflow: wf-bchg v.$VERSION by $AUTHOR"
log_info "Run ID: $RUN_ID"
log_info "SLURM Job ID: $SLURM_JOB_ID"
log_info "Run directory: $RUN_DIR"
log_info "POD5 directory: $POD5_DIR"
log_info "FASTQ directory: $FASTQ_DIR"
log_info "Sample sheet: $SAMPLESHEET_FILE"
log_info "Model: $MODEL"
log_info "Kit: $KIT"

echo ""
echo "========== SLURM Environment =========="
echo "Node    : $SLURM_NODELIST"
echo "Job ID  : $SLURM_JOB_ID"
echo "CPUs    : $SLURM_CPUS_PER_TASK"
echo "Memory  : ${SLURM_MEM_PER_NODE:-N/A} MB"
if command -v nvidia-smi &> /dev/null; then
    echo "GPU     : $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'N/A')"
else
    echo "GPU     : N/A"
fi
echo "========================================"

log_step "2/5: VALIDATION"

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

check_dir "$POD5_DIR"
check_file "$SAMPLESHEET_FILE"

# Count POD5 files
POD5_COUNT=$(find "$POD5_DIR" -name "*.pod5" -type f | wc -l)
POD5_SIZE=$(du -sh "$POD5_DIR" | cut -f1)
log_info "Found $POD5_COUNT POD5 files (total size: $POD5_SIZE)"

echo ""
echo "============= Sample Sheet ============="
column -s, -t < "$SAMPLESHEET_FILE"
echo "========================================"

mkdir -p  "$PROCESS_DIR"
mkdir -p "$FASTQ_DIR"
check_dir "$FASTQ_DIR"

echo ""
log_info "Dorado version:"
$DORADO_BIN --version

log_step "3/6: BASECALLING"
STEP_START=$(date +%s)
log_info "Starting basecalling..."
BAM_DIR="$FASTQ_DIR/bam_output"
mkdir -p "$BAM_DIR"
BASECALL_BAM="$BAM_DIR/basecalls.bam"

# Basecalling without sample-sheet to write single BAM file to stdout
# The sample-sheet will be used in the demux step instead
if $DORADO_BIN basecaller $MODEL "$POD5_DIR" --recursive \
	> "$BASECALL_BAM"; then
	STEP_END=$(date +%s)
	STEP_RUNTIME=$((STEP_END - STEP_START))
	
	# Force flush and verify file exists
	sync
	if [ ! -f "$BASECALL_BAM" ]; then
		log_error "Basecalling completed but output file not found: $BASECALL_BAM"
		exit 1
	fi
	BAM_SIZE=$(stat -f%z "$BASECALL_BAM" 2>/dev/null || stat -c%s "$BASECALL_BAM" 2>/dev/null)
	if [ "$BAM_SIZE" -eq 0 ]; then
		log_error "Basecalling output file is empty: $BASECALL_BAM"
		exit 1
	fi
	
	log_success "Basecalling completed successfully"
	log_info "Basecalling duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"
	log_info "Basecalling output: $BASECALL_BAM ($(numfmt --to=iec-i --suffix=B $BAM_SIZE 2>/dev/null || echo $BAM_SIZE bytes))"
else
	log_error "Basecalling failed with exit code $?"
	exit 1
fi

log_step "4/6: DEMULTIPLEXING"
STEP_START=$(date +%s)
log_info "Starting demultiplexing..."
DEMUX_DIR="$BAM_DIR/demux"
mkdir -p "$DEMUX_DIR"

if $DORADO_BIN demux \
	--kit-name $KIT \
	--output-dir "$DEMUX_DIR" \
	"$BASECALL_BAM"; then
	STEP_END=$(date +%s)
	STEP_RUNTIME=$((STEP_END - STEP_START))
	log_success "Demultiplexing completed successfully"
	log_info "Demultiplexing duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"
	
	# Count demuxed BAM files
	DEMUX_BAM_COUNT=$(find "$DEMUX_DIR" -name "*.bam" -type f | wc -l)
	log_info "Demuxed BAM files: $DEMUX_BAM_COUNT"
	
	# Only clean up basecalls.bam if demux created files
	if [ "$DEMUX_BAM_COUNT" -gt 0 ]; then
		log_info "Cleaning up basecalls.bam..."
		rm -f "$BASECALL_BAM"
		log_success "Removed basecalls.bam"
	else
		log_warning "No demuxed files created, keeping basecalls.bam for inspection"
	fi
else
	log_error "Demultiplexing failed with exit code $?"
	log_warning "Keeping basecalls.bam for inspection"
	exit 1
fi

log_step "5/6: CONVERTING BAM TO FASTQ"
CONVERT_START=$(date +%s)

# Source Conda for Genouest cluster compute node
if [ -f /local/env/envconda.sh ]; then
    log_info "Sourcing conda environment"
    # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
    . /local/env/envconda.sh 2>/dev/null || log_warning "Failed to source envconda.sh, conda may already be available"
fi

# Activate conda environment for samtools
log_info "Activating conda environment: $BCHG_ENV"
conda activate "$BCHG_ENV" || {
    log_error "Failed to activate conda environment: $BCHG_ENV"
    log_error "Please create it with: conda create -n env_bchg -c bioconda samtools -y"
    exit 1
}

# Verify samtools is available
if ! command -v samtools &> /dev/null; then
    log_error "samtools not found in conda environment"
    exit 1
fi
log_success "samtools is available: $(samtools --version 2>&1 | head -1)"

# Convert each BAM file to FASTQ
log_info "Looking for BAM files in: $DEMUX_DIR"
log_info "BAM files found:"
find "$DEMUX_DIR" -name "*.bam" -type f || log_warning "No BAM files found"

BAM_COUNT=0
while IFS= read -r -d '' BAM_FILE; do
	BASENAME=$(basename "$BAM_FILE" .bam)
	log_info "Converting: $(basename "$BAM_FILE") -> ${BASENAME}.fastq"
	samtools fastq "$BAM_FILE" > "$FASTQ_DIR/${BASENAME}.fastq"
	((BAM_COUNT++)) || true
done < <(find "$DEMUX_DIR" -name "*.bam" -type f -print0)

CONVERT_END=$(date +%s)
CONVERT_RUNTIME=$((CONVERT_END - CONVERT_START))
log_success "Converted $BAM_COUNT BAM files to FASTQ"
log_info "Conversion duration: $(printf '%02d:%02d:%02d' $((CONVERT_RUNTIME/3600)) $((CONVERT_RUNTIME%3600/60)) $((CONVERT_RUNTIME%60)))"

# Clean up BAM files
log_info "Cleaning up BAM files..."
rm -rf "$BAM_DIR"
log_success "BAM files removed"

log_step "6/6: COMPRESSION"
STEP_START=$(date +%s)
log_info "Compressing FASTQ files in $FASTQ_DIR"

# Load GNU parallel if available
PARALLEL_AVAILABLE=false
if [ -f /local/env/envparallel-20190122.sh ]; then
    log_info "Loading GNU parallel"
    # Use a subshell to safely source the file without affecting main script
    # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
    if (set +e; . /local/env/envparallel-20190122.sh >/dev/null 2>&1; exit $?); then
        # Source again in main shell if successful
        # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
        . /local/env/envparallel-20190122.sh >/dev/null 2>&1 || true
        PARALLEL_AVAILABLE=true
        log_success "GNU parallel loaded successfully"
    else
        log_warning "Failed to load GNU parallel, will use standard gzip"
    fi
fi

# Count files before compression
FASTQ_UNCOMPRESSED=$(find "$FASTQ_DIR" -name "*.fastq" -type f 2>/dev/null | wc -l)
log_info "Files to compress: $FASTQ_UNCOMPRESSED"

# Parallel compression if possible
if [ "$PARALLEL_AVAILABLE" = true ] && command -v parallel &> /dev/null && [ -n "${SLURM_CPUS_PER_TASK:-}" ] && [ "$FASTQ_UNCOMPRESSED" -gt 0 ]; then
    log_info "Using GNU parallel with $SLURM_CPUS_PER_TASK CPUs"
    find "$FASTQ_DIR" -name "*.fastq" -type f | parallel -j "$SLURM_CPUS_PER_TASK" gzip
elif [ "$FASTQ_UNCOMPRESSED" -gt 0 ]; then
    log_info "Using standard gzip (serial)"
    gzip "$FASTQ_DIR"/*.fastq
else
    log_warning "No .fastq files to compress"
fi

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "Compression completed"
log_info "Compression duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

log_step "7/7: ORGANIZATION"
STEP_START=$(date +%s)
log_info "Organizing files into sample directories"
cd "$FASTQ_DIR" || exit
SAMPLE_DIRS=0
for FILE in *.fastq.gz; do
	[[ -e "$FILE" ]] || break  # handle the case of no *.fastq.gz files
	DIR=${FILE#*_}
	DIR=${DIR%%.*}
	mkdir -p "$DIR"
	mv "$FILE" "$FASTQ_DIR"/"$DIR"/"$FILE"
	((SAMPLE_DIRS++)) || true
done

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "File organization completed"
log_info "Organization duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# Post-execution validation
echo ""
echo "=========================================="
echo "           VALIDATION & SUMMARY           "
echo "=========================================="

FASTQ_COUNT=$(find "$FASTQ_DIR" -name "*.fastq.gz" -type f | wc -l)
if [ "$FASTQ_COUNT" -eq 0 ]; then
    log_error "No FASTQ.gz files generated!"
    exit 1
else
    log_success "$FASTQ_COUNT FASTQ.gz files generated"
fi

# Count barcodes
BARCODE_DIRS=$(find "$FASTQ_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
log_info "Barcodes detected: $BARCODE_DIRS"

TOTAL_SIZE=$(du -sh "$FASTQ_DIR" | cut -f1)
log_success "Total output size: $TOTAL_SIZE"

# Calculate average file size
if [ "$FASTQ_COUNT" -gt 0 ]; then
    TOTAL_KB=$(du -sk "$FASTQ_DIR" | cut -f1)
    AVG_SIZE=$((TOTAL_KB / FASTQ_COUNT))
    log_info "Average file size: ${AVG_SIZE} KB"
fi

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
echo "$RUN_ID	NA	bchg	$HOURS:$MINUTES:$SECONDS" >> "$WORKFLOW_SUMMARY_FILE"
log_success "Updated workflow summary file: $WORKFLOW_SUMMARY_FILE"

echo ""
echo "=========================================="
log_info "Check detailed logs in processing/ directory"
echo "=========================================="
