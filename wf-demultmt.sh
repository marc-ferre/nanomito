#!/bin/bash
#SBATCH --job-name=demultmt
#SBATCH --cpus-per-task=4
#SBATCH --constraint=avx2
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=processing/slurm-%x.%j.out
#SBATCH --error=processing/slurm-%x.%j.err
#SBATCH --mail-type=FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#
# wf-demultmt.sh - Mitochondrial reads demultiplexing workflow
#
# Description:
#   Demultiplexes mitochondrial reads from a sample into individual patient files
#
# Usage:
#   sbatch --chdir=/path/to/run wf-demultmt.sh SAMPLE_ID
#
# Arguments:
#   $1: SAMPLE_ID - Name of the sample directory in fastq_pass/
#                   (e.g., barcode09, barcode10, etc.)
#
# Directory structure expected:
#   RUN_DIR/
#     ├── fastq_pass/
#     │   └── SAMPLE_ID/
#     │       └── *.fastq.gz files
#     └── processing/
#
#
# ============================================================================
# ERROR HANDLING & INITIALIZATION
# ============================================================================

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

# ============================================================================
# ARGUMENTS & PARAMETERS
# ============================================================================

# Run id = Working directory
RUN_ID=${PWD##*/} # Assign directory name to run id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Sample id = Argument
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 128
fi
SAMPLE_ID=$1

# Read selection strategy (start, both, either ,xor)
SELECT='both' 

# ----------------------------------------------------------------------------
# GENOUEST: Source Conda environment as early as possible
# ----------------------------------------------------------------------------
set +u  # Temporarily disable unset variable check for conda
if [ -f /local/env/envconda.sh ]; then
    # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
    . /local/env/envconda.sh 2>/dev/null || echo "[WARN] Could not source /local/env/envconda.sh"
else
    echo "[WARN] Conda init script not found at /local/env/envconda.sh"
fi
set -u  # Re-enable unset variable check

# ============================================================================
# DIRECTORY STRUCTURE
# ============================================================================

# Directories
RUN_DIR=$(pwd)
BAM_DIR="$RUN_DIR/fastq_pass/$SAMPLE_ID"
POD5_DIR="$RUN_DIR/pod5_chrM"
PROCESS_DIR="$RUN_DIR/processing"
OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
REF_MT_DIR='/scratch/mferre/reference'
SELECT_DIR="$OUT_DIR/select-$SELECT"
VARCALL_DIR="$OUT_DIR/varcall"

# ============================================================================
# EXTERNAL TOOLS & DEPENDENCIES
# ============================================================================

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
# shellcheck disable=SC1091
source "$CONFIG_FILE"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

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

# ============================================================================
# FILE NAMING CONVENTIONS
# ============================================================================

# Pre/Sufixes
BALDUR_PREFIX="$SAMPLE_ID.baldur"
DEMULT_PREFIX="$SAMPLE_ID.ont_demult"
HPLCHK_PREFIX="$OUT_DIR/$SAMPLE_ID-haplocheck"

# Files
ANNOTMT_TSV_FILE="$OUT_DIR/$SAMPLE_ID.ann.tsv"
ANNOTMT_VCF_FILE="$OUT_DIR/$SAMPLE_ID.ann.vcf"
BALDUR_VCF_FILE="$VARCALL_DIR/$BALDUR_PREFIX.vcf.gz"
BAM_FILE="$SELECT_DIR/$SAMPLE_ID.bam"
CHRM_ONLY_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.match_chrM_only.txt"
CUT_FILE='/scratch/mferre/reference/cut.txt'
DEMULT_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.txt.gz"
DEMULT_POD5_FILE="$SELECT_DIR/$SAMPLE_ID.demultmt.pod5"
DEMULT_SUMMARY_FILE="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
HPLCHK_RAW_FILE="$HPLCHK_PREFIX.raw.txt"
HPLCHK_SUMMARY_FILE="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"
IDS_FILE="$SELECT_DIR/$SAMPLE_ID.read_ids.txt"
MATCH_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.matched.txt"
PID_DICT_FILE="$POD5_DIR/$RUN_ID.pid_dict.tsv"
SORTED_BAM_FILE="$SELECT_DIR/$SAMPLE_ID.sorted.bam"
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Check if directory exists (silent unless error)
check_dir() {
	if [ ! -d "$1" ]; then
		log_error "Directory not found: $1"
		exit 1
	fi
}

# Check if file exists and is not empty (silent unless error)
check_file() {
	if [ ! -f "$1" ]; then
		log_error "File not found: $1"
		exit 1
	elif [ ! -s "$1" ]; then
		log_error "File is empty: $1"
		exit 1
	fi
}

# Create directory if it doesn't exist
ensure_dir() {
	if [ ! -d "$1" ]; then
		mkdir -p "$1" || {
			log_error "Failed to create directory: $1"
			exit 1
		}
		log_success "Created directory: $1"
	fi
}

# ============================================================================
# WORKFLOW EXECUTION
# ============================================================================

START=$(date +%s)
STEP_START=$START

# ----------------------------------------------------------------------------
# STEP 1: INITIALIZATION
# ----------------------------------------------------------------------------

log_step "1/7: INITIALIZATION"
log_info "Workflow: wf-demultmt v.$VERSION by $AUTHOR"
log_info "Run ID: $RUN_ID"
log_info "Sample ID: $SAMPLE_ID"
log_info "SLURM Job ID: $SLURM_JOB_ID"
log_info "Run directory: $RUN_DIR"
log_info "Pod5 directory: $POD5_DIR"
log_info "BAM directory: $BAM_DIR"
log_info "Output directory: $OUT_DIR"
log_info "Read selection strategy: $SELECT"

echo ""
echo "========== SLURM Environment =========="
echo "Node    : $SLURM_NODELIST"
echo "Job ID  : $SLURM_JOB_ID"
echo "CPUs    : $SLURM_CPUS_PER_TASK"
echo "Memory  : ${SLURM_MEM_PER_NODE:-N/A} MB"
echo "========================================"

# ----------------------------------------------------------------------------
# STEP 2: PREPROCESSING
# ----------------------------------------------------------------------------

log_step "2/7: PREPROCESSING"
STEP_START=$(date +%s)
check_dir "$BAM_DIR"
ensure_dir "$OUT_DIR"
FASTQ_FILE="$OUT_DIR/$SAMPLE_ID.fastq.gz"
log_info "FASTQ file: $FASTQ_FILE"
MAPPING_PAF_FILE="$OUT_DIR/$SAMPLE_ID.paf"
log_info "Mapping PAF file: $MAPPING_PAF_FILE"

log_info "Concatenating FASTQ files..."
cat "$BAM_DIR"/*.fastq.gz > "$FASTQ_FILE"
check_file "$FASTQ_FILE"

log_info "Counting total reads..."
COUNT_TOTAL=$(( $(zcat "$FASTQ_FILE" | wc -l) / 4 ))
log_success "Total reads: $COUNT_TOTAL"

# Create read_id→parent_id dictionary from Dorado BAM files (contains pi:Z tags)
if [ ! -f "$PID_DICT_FILE" ]; then
	log_info "Creating read_id→parent_id dictionary from BAM files..."
	conda run -p "$GETMT_ENV" python "$CREATE_PID_DICT_SCRIPT" -b "$BAM_DIR" -o "$PID_DICT_FILE" || {
		log_error "Failed to create parent ID dictionary"
		exit 1
	}
	check_file "$PID_DICT_FILE"
	log_success "Parent ID dictionary created"
else
	log_info "Using existing parent ID dictionary: $PID_DICT_FILE"
fi

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_info "Preprocessing duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# Source Conda for Genouest cluster compute node
log_info "Loading Conda environment"
set +u  # Temporarily disable unset variable check for conda
if [ -f /local/env/envconda.sh ]; then
    # shellcheck disable=SC1091  # File only exists on Genouest HPC cluster
    . /local/env/envconda.sh 2>/dev/null || log_warning "Failed to source envconda.sh, conda may already be available"
else
    log_warning "Conda init script not found at /local/env/envconda.sh"
fi
set -u  # Re-enable unset variable check

# ----------------------------------------------------------------------------
# STEP 3: MAPPING TO REFERENCE
# ----------------------------------------------------------------------------
log_step "3/7: MAPPING TO REFERENCE"
STEP_START=$(date +%s)

conda activate "$ONT_DEMULT_ENV"

log_info "Minimap2 version: $(minimap2 --version)"
log_info "Starting mapping..."

minimap2 -x map-ont -t "$SLURM_CPUS_PER_TASK" "$REF_WHOLE" "$FASTQ_FILE" > "$MAPPING_PAF_FILE"
check_file "$MAPPING_PAF_FILE"

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "Mapping completed"
log_info "Mapping duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# ----------------------------------------------------------------------------
# STEP 4: DEMULTIPLEXING
# ----------------------------------------------------------------------------
log_step "4/7: DEMULTIPLEXING"
STEP_START=$(date +%s)

log_info "ont_demult version: $($ONT_DEMULT_BIN --version)"

ensure_dir "$SELECT_DIR"
cd "$SELECT_DIR" || exit

log_info "Running demultiplexing (selection strategy: $SELECT)..."
$ONT_DEMULT_BIN --select $SELECT \
	--loglevel info \
	--mapq-threshold 10 \
	--max-distance 100 \
	--max-unmatched 200 \
	--margin 10 \
	--cut-file "$CUT_FILE" \
	--fastq "$FASTQ_FILE" \
	--prefix "${DEMULT_PREFIX}" \
	--matched-only \
	--compress \
	"$MAPPING_PAF_FILE"
check_file "$DEMULT_FILE"

log_info "Analyzing demultiplexing results..."
COUNT_ALIGN=$(( $(gunzip -c "$DEMULT_FILE" | wc -l) - 1 ))

(gunzip -c "$DEMULT_FILE" | head -1 > "$CHRM_ONLY_FILE") || true
(gunzip -c "$DEMULT_FILE" | grep -P 'chrM\t' >> "$CHRM_ONLY_FILE") || true
check_file "$CHRM_ONLY_FILE"
COUNT_CHRM_ONLY=$(($(wc -l < "$CHRM_ONLY_FILE") - 1))

(gunzip -c "$DEMULT_FILE" | head -1 > "$MATCH_FILE") || true
(gunzip -c "$DEMULT_FILE" | grep -P 'Matched\tmt_' >> "$MATCH_FILE") || true
check_file "$MATCH_FILE"
COUNT_MATCHED=$(($(wc -l < "$MATCH_FILE") - 1))

COUNT_CHRM=$(( COUNT_CHRM_ONLY +  COUNT_MATCHED ))

echo ""
echo "========== Demultiplexing Statistics =========="
log_info "Reads generated: $COUNT_TOTAL"
log_info "Reads aligned to reference: $COUNT_ALIGN ($(awk "BEGIN {printf \"%.2f\", ($COUNT_ALIGN/$COUNT_TOTAL)*100}")%)"
log_info "Reads aligned to chrM: $COUNT_CHRM ($(awk "BEGIN {printf \"%.2f\", ($COUNT_CHRM/$COUNT_TOTAL)*100}")%)"

# Check if no reads matched
if [ "$COUNT_MATCHED" -eq 0 ]; then
	log_warning "Reads matching $SELECT: $COUNT_MATCHED (0.00%) - NO DATA TO PROCESS"
	echo "==============================================="
	
	# Update summary file
	if ! [ -e "$DEMULT_SUMMARY_FILE" ] ; then
		echo "Run id	Sample id	Reads generated	Reads aligned to reference	Reads aligned to chrM	Reads matching $SELECT" \
			> "$DEMULT_SUMMARY_FILE"
		log_success "Created demultiplexing summary file"
	fi
	echo "$RUN_ID	$SAMPLE_ID	$COUNT_TOTAL	$COUNT_ALIGN	$COUNT_CHRM	$COUNT_MATCHED" >> "$DEMULT_SUMMARY_FILE"
	log_success "Updated demultiplexing summary file"
	
	# Create empty marker file to indicate no data
	touch "$OUT_DIR/NO_DATA.marker"
	
	echo ""
	echo "=========================================="
	echo "WARNING: NO MATCHING READS DETECTED"
	echo "=========================================="
	log_warning "This sample has no reads matching both patient and reference mitochondria"
	log_warning "This is not an error - the workflow will complete successfully"
	log_warning "Downstream analysis (modmito) will be skipped automatically"
	log_warning "A NO_DATA.marker file has been created to signal this condition"
	echo "=========================================="
	echo ""
	
	# Exit successfully to allow dependency chain to continue
	log_success "Workflow completed successfully (NO DATA)"
	exit 0
fi

log_success "Reads matching $SELECT: $COUNT_MATCHED ($(awk "BEGIN {printf \"%.2f\", ($COUNT_MATCHED/$COUNT_TOTAL)*100}")%)"
echo "==============================================="

if ! [ -e "$DEMULT_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Reads generated	Reads aligned to reference	Reads aligned to chrM	Reads matching $SELECT" \
		> "$DEMULT_SUMMARY_FILE"
	log_success "Created demultiplexing summary file"
fi
echo "$RUN_ID	$SAMPLE_ID	$COUNT_TOTAL	$COUNT_ALIGN	$COUNT_CHRM	$COUNT_MATCHED" >> "$DEMULT_SUMMARY_FILE"
log_success "Updated demultiplexing summary file"

log_info "Samtools version: $(samtools --version | head -n1)"
log_info "Aligning reads to mitochondrial references..."
ALN_PREFIX='alignment_'
REFERENCE_COUNT=$(wc -l < "$CUT_FILE")
log_info "Processing $REFERENCE_COUNT mitochondrial references..."

while IFS=$'\t' read -r _ _ ID _ _ || [ -n "$ID" ]; do
	REF="${REF_MT_DIR}/${REF_MT_PREFIX}${ID}${REF_MT_SUFIX}"
	FASTQ="${DEMULT_PREFIX}_${ID}.fastq.gz"
	BAM="${ALN_PREFIX}${ID}.bam"
	
	minimap2 -ax map-ont "$REF" "$FASTQ" | samtools view -b - > "$BAM" 2>/dev/null || true
done < "$CUT_FILE"

log_info "Merging BAM files..."
samtools merge "$BAM_FILE" ${ALN_PREFIX}*.bam
check_file "$BAM_FILE"

log_info "Sorting BAM file..."
samtools sort "$BAM_FILE" -o "$SORTED_BAM_FILE"
check_file "$SORTED_BAM_FILE"

log_info "Indexing BAM file..."
samtools index "$SORTED_BAM_FILE"

log_info "Cleaning up intermediate BAM files..."
while IFS=$'\t' read -r _ _ ID _ _ || [ -n "$ID" ]; do
	BAM="${ALN_PREFIX}${ID}.bam"
	rm -f "$BAM"
done < "$CUT_FILE"

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_success "Demultiplexing and alignment completed"
log_info "Demultiplexing duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

conda deactivate

# ----------------------------------------------------------------------------
# STEP 5: VARIANT CALLING
# ----------------------------------------------------------------------------
log_step "5/7: VARIANT CALLING"
STEP_START=$(date +%s)

ensure_dir "$VARCALL_DIR"
cd "$VARCALL_DIR" || exit

conda activate "$BALDUR_ENV"

# shellcheck disable=SC2153  # BALDUR_BIN is defined in sourced config
log_info "Baldur version: $("$BALDUR_BIN" --version)"
log_info "Starting variant calling..."

# Run Baldur in background and wait for completion
"$BALDUR_BIN" --mapq-threshold 20 \
	--qual-threshold 10 \
	--max-qual 30 \
	--max-indel-qual 20 \
	--homopolymer-limit 4 \
	--reference "$REF_MT" \
	--adjust 5 \
	--view \
	--output-deletions \
	--output-prefix "$BALDUR_PREFIX" \
	--sample "$SAMPLE_ID" \
	"$BAM_FILE" &

BALDUR_PID=$!
log_info "Baldur running in background (PID: $BALDUR_PID)"
wait $BALDUR_PID
BALDUR_EXIT=$?

if [ $BALDUR_EXIT -eq 0 ]; then
	log_success "Variant calling completed"
else
	log_error "Baldur failed with exit code $BALDUR_EXIT"
	exit 1
fi

conda deactivate

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_info "Variant calling duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# ----------------------------------------------------------------------------
# STEP 6: RETRIEVING RAW DATA
# ----------------------------------------------------------------------------
log_step "6/7: RETRIEVING RAW DATA"
STEP_START=$(date +%s)

log_info "Cleaning up unsorted BAM file..."
rm -f "$BAM_FILE"
log_success "Sorted BAM file retained: $SORTED_BAM_FILE"

cd "$VARCALL_DIR" || exit
log_info "Retrieving matching reads (selection strategy: $SELECT)..."

# Get unique parent IDs (pid) of reads aligned to chrM
# Using the read_id→parent_id dictionary created during preprocessing
# Capture output to check for missing reads
CHRMPIDS_OUTPUT=$(conda run -p "$GETMT_ENV" python "$CHRMPIDS_SCRIPT" -b "$SELECT_DIR" -p "$POD5_DIR" -d "$PID_DICT_FILE" -o "$IDS_FILE" 2>&1)
CHRMPIDS_EXIT=$?

# Display the output
echo "$CHRMPIDS_OUTPUT"

# Check if script failed
if [ $CHRMPIDS_EXIT -ne 0 ]; then
	log_error "Failed to retrieve read IDs from BAM files"
	exit 1
fi

check_file "$IDS_FILE"

READ_IDS_COUNT=$(wc -l < "$IDS_FILE")
log_success "Retrieved $READ_IDS_COUNT read IDs"

# Check for missing reads and display warning if any
MISSING_COUNT=$(echo "$CHRMPIDS_OUTPUT" | grep "Missing reads pIDs:" | awk '{print $NF}')
if [ -n "$MISSING_COUNT" ] && [ "$MISSING_COUNT" -gt 0 ]; then
	echo ""
	echo "=========================================="
	echo "WARNING: MISSING POD5 READS DETECTED"
	echo "=========================================="
	log_warning "$MISSING_COUNT read(s) aligned to chrM have no corresponding Pod5 file in pod5_chrM/"
	log_warning "These reads were basecalled but their raw Pod5 data is not available"
	log_warning "Missing read IDs are listed above in the PROCESSING SUMMARY"
	log_warning "Continuing with pod5 filter --missing-ok flag"
	echo "=========================================="
	echo ""
fi

conda activate "$POD5_ENV"

check_dir "$POD5_DIR"
log_info "POD5 version: $(pod5 --version 2>&1 | head -n1)"

log_info "Filtering POD5 files..."
POD5_FILTER_OUTPUT=$(pod5 filter --missing-ok --recursive --force-overwrite --threads "$SLURM_CPUS_PER_TASK" "$POD5_DIR" -i "$IDS_FILE" -o "$DEMULT_POD5_FILE" 2>&1)
POD5_FILTER_EXIT=$?

# Display pod5 filter output
echo "$POD5_FILTER_OUTPUT"

# Check if pod5 filter failed
if [ $POD5_FILTER_EXIT -ne 0 ]; then
	log_error "Failed to filter Pod5 files"
	exit 1
fi

check_file "$DEMULT_POD5_FILE"

POD5_SIZE=$(du -sh "$DEMULT_POD5_FILE" | cut -f1)
log_success "POD5 file created (size: $POD5_SIZE)"

# Extract and display pod5 filter statistics
READS_REQUESTED=$(echo "$POD5_FILTER_OUTPUT" | grep "Parsed.*reads_ids from" | awk '{print $2}')
READS_TRANSFERRED=$(echo "$POD5_FILTER_OUTPUT" | grep "Calculated.*transfers" | awk '{print $2}')

if [ -n "$READS_REQUESTED" ] && [ -n "$READS_TRANSFERRED" ]; then
	if [ "$READS_REQUESTED" -eq "$READS_TRANSFERRED" ]; then
		log_success "All $READS_TRANSFERRED reads successfully retrieved from Pod5 files"
	else
		READS_MISSING=$((READS_REQUESTED - READS_TRANSFERRED))
		echo ""
		echo "=========================================="
		echo "WARNING: POD5 FILTERING INCOMPLETE"
		echo "=========================================="
		log_warning "Requested reads: $READS_REQUESTED"
		log_warning "Retrieved reads: $READS_TRANSFERRED"
		log_warning "Missing reads:   $READS_MISSING"
		log_warning "Check the Missing IDs in the output above"
		echo "=========================================="
		echo ""
	fi
fi

conda deactivate

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_info "Raw data retrieval duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# ----------------------------------------------------------------------------
# STEP 7: VARIANT ANNOTATION & HAPLOGROUP
# ----------------------------------------------------------------------------
log_step "7/7: VARIANT ANNOTATION & HAPLOGROUP"
STEP_START=$(date +%s)

cd "$VARCALL_DIR" || exit
check_file "$BALDUR_VCF_FILE"

log_info "Decompressing VCF file..."
gunzip -f "$BALDUR_VCF_FILE"
BALDUR_VCF_FILE=$(basename "$BALDUR_VCF_FILE" .gz)
check_file "$BALDUR_VCF_FILE"

VARIANT_COUNT=$(grep -cv '^#' "$BALDUR_VCF_FILE")
log_success "Variants called: $VARIANT_COUNT"

conda activate "$ANNOTMT_ENV"

log_info "SnpSift version: $(SnpSift 2>&1 | grep -i version | head -n1 || echo 'N/A')"
log_info "Starting variant annotation..."

VCF_TMP1="$ANNOTMT_VCF_FILE.tmp"
VCF_TMP2="$ANNOTMT_VCF_FILE.1.tmp"

# MITOMAP Disease
log_info "Annotating with MITOMAP disease database..."
SnpSift annotate -v \
	"$ANN_MITOMAP_DISEASE" \
	"$BALDUR_VCF_FILE" \
	> "$VCF_TMP2"
mv "$VCF_TMP2" "$VCF_TMP1"

# MITOMAP Polymorphisms	
log_info "Annotating with MITOMAP polymorphisms database..."
SnpSift annotate -v \
	"$ANN_MITOMAP_POLYMORPHISMS" \
	"$VCF_TMP1" \
	> "$VCF_TMP2"
mv "$VCF_TMP2" "$VCF_TMP1"

# GnomAD including MitoTIP
log_info "Annotating with gnomAD database (includes MitoTIP)..."
SnpSift annotate -v \
	"$ANN_GNOMAD" \
	"$VCF_TMP1" \
	> "$ANNOTMT_VCF_FILE"
check_file "$ANNOTMT_VCF_FILE"

rm -f "$VCF_TMP1"
log_success "Variant annotation completed"

#
# Export to TSV
#
# Columns (TSV:VCF)
#
# CHROM:CHROM
# POS:POS
# ID:ID
# REF:REF
# ALT:ALT
# Heteroplasmy:HPL
# MitoMap_GenBank_allele_count:AC
# MitoMap_GenBank_allele_freq:AF
# MitoMap_Disease:Disease
# MitoMap_DiseaseStatus:DiseaseStatus
# MitoMap_Haplogroups_with_high_variant_frequency:HGFL
# MitoMap_PubmedIDs:PubmedIDs
# MitoMap_aachange:aachange
# MitoMap_heteroplasmy:heteroplasmy
# MitoMap_homoplasmy:homoplasmy
# MitoTIP_Interporetation:mitotip_trna_prediction
# MitoTIP_Score:mitotip_score
# gnomAD_WG_AlleleCount_heteroplasmic:AC_het
# gnomAD_WG_AlleleCount_homoplasmic:AC_hom
# gnomAD_WG_AlleleFreq_heteroplasmic:AF_het
# gnomAD_WG_AlleleFreq_homoplasmic:AF_hom
# gnomAD_WG_total_AlleleNumber:AN
# gnomAD_WG_filters:filters
# gnomAD_WG_hap_defining_variant:hap_defining_variant
# gnomAD_WG_max_hl:max_hl
# gnomAD_WG_pon_ml_probability_of_pathogenicity:pon_ml_probability_of_pathogenicity
# gnomAD_WG_pon_mt_trna_prediction:pon_mt_trna_prediction
# FILTER:FILTER
# SAMPLE_ADF:ADF
# SAMPLE_ADR:ADR
# QUAL:QUAL
# DP:DP
log_info "bcftools version: $(bcftools --version | head -n1)"
log_info "Exporting annotations to TSV..."
echo 'CHROM	POS	ID	REF	ALT	HPL	AC	AF	Disease	DiseaseStatus	HGFL	PubmedIDs	aachange	heteroplasmy	homoplasmy	mitotip_trna_prediction	mitotip_score	AC_het	AC_hom	AF_het	AF_hom	AN	filters	hap_defining_variant	max_hl	pon_ml_probability_of_pathogenicity	pon_mt_trna_prediction	FILTER	ADF	ADR	QUAL	DP' > "$ANNOTMT_TSV_FILE"
bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %HPL]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t[ %ADF]\t[ %ADR]\t%QUAL\t%DP\n' "$ANNOTMT_VCF_FILE" >> "$ANNOTMT_TSV_FILE"
check_file "$ANNOTMT_TSV_FILE"
log_success "TSV file created"

echo ""
log_info "Determining haplogroups with haplocheck..."
haplocheck --raw --out "$HPLCHK_PREFIX" "$ANNOTMT_VCF_FILE"
check_file "$HPLCHK_RAW_FILE"

# Extract haplogroup from results (column 10 = Major Haplogroup)
HAPLOGROUP=$(tail -n1 "$HPLCHK_RAW_FILE" | cut -f10)
log_success "Haplogroup detected: $HAPLOGROUP"

log_info "Cleaning up intermediate haplocheck files..."
rm -f "$HPLCHK_PREFIX" "$HPLCHK_PREFIX".html

if ! [ -e "$HPLCHK_SUMMARY_FILE" ] ; then
	cp "$HPLCHK_RAW_FILE" "$HPLCHK_SUMMARY_FILE"
	log_success "Created haplocheck summary file"
else
	tail -n +2 "$HPLCHK_RAW_FILE" >> "$HPLCHK_SUMMARY_FILE"
	log_success "Updated haplocheck summary file"
fi

conda deactivate

STEP_END=$(date +%s)
STEP_RUNTIME=$((STEP_END - STEP_START))
log_info "Annotation duration: $(printf '%02d:%02d:%02d' $((STEP_RUNTIME/3600)) $((STEP_RUNTIME%3600/60)) $((STEP_RUNTIME%60)))"

# ============================================================================
# WORKFLOW SUMMARY & COMPLETION
# ============================================================================
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

echo ""
echo "========== Final Statistics =========="
log_info "Total reads processed: $COUNT_TOTAL"
log_info "Mitochondrial reads: $COUNT_MATCHED"
log_info "Variants called: $VARIANT_COUNT"
log_info "Haplogroup: $HAPLOGROUP"
log_info "Output directory: $OUT_DIR"
echo "======================================"

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > "$WORKFLOW_SUMMARY_FILE"
	log_success "Created workflow summary file"
fi
printf "%s\t%s\t%s\t%02d:%02d:%02d\n" "$RUN_ID" "$SAMPLE_ID" "demultmt" "$HOURS" "$MINUTES" "$SECONDS" >> "$WORKFLOW_SUMMARY_FILE"
log_success "Updated workflow summary file: $WORKFLOW_SUMMARY_FILE"

echo ""
echo "=========================================="
log_info "Check detailed logs in processing/ directory"
echo "=========================================="
