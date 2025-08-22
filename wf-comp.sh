#!/bin/bash
VERSION='2025-08-21.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Description:
# This script compares VCF files generated from Nanopore and Illumina sequencing.
# It performs the following tasks
# 1. Annotates VCF files with MITOMAP and gnomAD databases
# 2. Compares variants between Nanopore and Illumina
# 3. Performs haplogroup analysis
# 4. Exports results in TSV format
#
# Usage:
#   ./wf-comp.sh /path/to/directory
# If no argument is provided, the current directory will be used by default.

# Constants and reference paths
readonly HAPLOCHECK_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/haplocheck/haplocheck.jar'   
readonly SNPSIFT_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/snpEff/SnpSift.jar'
readonly ANN_GNOMAD='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/gnomAD/gnomad.genomes.v3.1.sites.chrM.vcf'
readonly ANN_MITOMAP_DISEASE='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/disease-nosp.vcf'
readonly ANN_MITOMAP_POLYMORPHISMS='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/polymorphisms.vcf'

# ANSI color codes (no change needed)
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'   # Info
readonly COLOR_YELLOW='\033[0;33m'  # Warning
readonly COLOR_RED='\033[0;31m'     # Error

# Enable strict error handling
set -euo pipefail

# --- Functions (in alphabetical order) ---
# Log function to handle colored output and logging
_log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="[$(date '+%F %T')]"
  local log_line="$timestamp [$level] $message"
  
  # Select color based on level
  local color=""
  case "$level" in
      INFO)    color="$COLOR_GREEN";;
      WARN)    color="$COLOR_YELLOW";;
      ERROR)   color="$COLOR_RED";;
  esac

  # Write to log file (plain text)
  if [[ -n "${LOGFILE:-}" ]]; then
      printf '%s\n' "$log_line" >> "$LOGFILE"
  fi

  # Write to terminal (with colors)
  if [[ -t 1 && -n "$color" ]]; then
      printf "${color}%s${COLOR_RESET}\n" "$log_line"
  else
      printf '%s\n' "$log_line"
  fi
}

annotate_vcf() {
    local input_vcf="$1"
    local output_vcf="$2"
    local tmp_vcf1="${output_vcf}.tmp1"
    local tmp_vcf2="${output_vcf}.tmp2"

    _log INFO "Annotating VCF file: '$input_vcf'"

    # Check input file
    check_file "$input_vcf" "Input VCF"

    # Annotate with MITOMAP Disease
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_DISEASE" "$input_vcf" > "$tmp_vcf1"; then
        handle_error "Failed to annotate with MITOMAP Disease"
    fi

    # Annotate with MITOMAP Polymorphisms
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_POLYMORPHISMS" "$tmp_vcf1" > "$tmp_vcf2"; then
        rm -f "$tmp_vcf1"
        handle_error "Failed to annotate with MITOMAP Polymorphisms"
    fi

    # Annotate with gnomAD
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_GNOMAD" "$tmp_vcf2" > "$output_vcf"; then
        rm -f "$tmp_vcf1" "$tmp_vcf2"
        handle_error "Failed to annotate with gnomAD"
    fi

    # Cleanup temporary files
    rm -f "$tmp_vcf1" "$tmp_vcf2"
    _log INFO "Annotation completed: '$output_vcf'"
}

check_dependencies() {
    _log INFO "Checking dependencies..."
    local dependencies=("bgzip" "tabix" "bcftools" "bedtools" "java")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            _log ERROR "Error: $cmd is not installed or not in PATH." >&2
            exit 1
        fi
    done
    _log INFO "All dependencies are installed."
}

check_file() {
    local file="$1"
    local type="$2"
    
    if [[ ! -f "$file" ]]; then
        handle_error "$type file not found: $file"
    fi
    if [[ ! -r "$file" ]]; then
        handle_error "$type file not readable: $file"
    fi
}

check_output_dir() {
    local dir="$1"
    local name="$2"
    if ! mkdir -p "$dir"; then
        handle_error "Failed to create $name directory: $dir"
    fi
}

cleanup_compressed_files() {
    local vcf_file="$1"
    _log INFO "Decompressing and cleaning up: '$vcf_file'"
    bgzip -d -f "${vcf_file}.gz"
    rm -f "${vcf_file}.gz.tbi"
}

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        _log ERROR "Script failed with errors. Check the log file for details: $LOGFILE"
    fi
    
    # Cleanup temporary files
    cleanup_compressed_files "$VCF_NANOPORE"
    cleanup_compressed_files "$VCF_ILLUMINA_ANNOTMT"
    
    local files_to_remove=("$VCF_ILLUMINA_ANNOTMT" "$VCF_NANOPORE_PASS")
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                _log INFO "Removed temporary file: '$file'"
            else
                _log WARN "Warning: Failed to remove temporary file: '$file'" >&2
            fi
        fi
    done
}

compress_and_index() {
    local vcf_file="$1"
    _log INFO "Compressing and indexing: '$vcf_file'"
    bgzip -f "$vcf_file"
    tabix -p vcf -f "${vcf_file}.gz"
}

create_directory() {
    local dir="$1"
    local dir_name="$2"
    
    if ! mkdir -p "$dir"; then
        handle_error "Failed to create $dir_name directory: $dir"
    fi
    _log INFO "Created '$dir_name' directory: '$dir'"
}

export_vcf_to_tsv_Illumina() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    _log INFO "Exporting VCF to TSV (Illumina): '$input_vcf' -> '$output_tsv'"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tQUAL\tDP" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %AF]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t%QUAL\t[ %DP]\n' "$input_vcf" >> "$output_tsv"

    _log INFO "TSV file generated: '$output_tsv'"
}

export_vcf_to_tsv_Nanopore() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    _log INFO "Exporting VCF to TSV (Nanopore): '$input_vcf' -> '$output_tsv'"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tADF\tADR\tQUAL\tDP" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %HPL]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t[ %ADF]\t[ %ADR]\t%QUAL\t%DP\n' "$input_vcf" >> "$output_tsv"

    _log INFO "TSV file generated: '$output_tsv'"
}

filter_pass_variants() {
    local vcf_file="$1"
    local output_file="$2"

    _log INFO "Filtering PASS variants from '$vcf_file'"

    if ! bcftools view -f PASS "$vcf_file" > "$output_file"; then
        handle_error "Failed to filter PASS variants"
    fi

    _log INFO "PASS variants filtered to '$output_file'"
}

find_vcf_files() {
    local dir="$1"

    # Use find command for reliable file discovery
    local nanopore_file
    local illumina_file
    nanopore_file=$(find "$dir" -maxdepth 1 -name "*.ann.vcf" -print -quit)
    illumina_file=$(find "$dir" -maxdepth 1 -name "i---*.vcf" -print -quit)

    # Validate Nanopore file existence
    if [[ -z "$nanopore_file" ]]; then
        _log ERROR "Error: No Nanopore VCF file (*.ann.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    # Validate Illumina file existence
    if [[ -z "$illumina_file" ]]; then
        _log ERROR "Error: No Illumina VCF file (i---*.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    # Display debug messages on stderr
    _log INFO "Found:" >&2
    _log INFO "- Nanopore: '$nanopore_file'" >&2
    _log INFO "- Illumina: '$illumina_file'" >&2

    # Return file paths on stdout
    printf "%s\n%s\n" "$nanopore_file" "$illumina_file"
}

handle_error() {
    local error_msg="$1"
    _log ERROR "$error_msg" >&2
    exit 1
}

is_file_readable() {
    local file="$1"
    [[ -f "$file" && -r "$file" ]]
}

print_summary() {
    local start_time="$1"
    local end_time="$2"
    local runtime=$((end_time - start_time))
    
    _log INFO "Summary:"
    _log INFO "- Input directory: '$WORKDIR'"
    _log INFO "- Log file: '$LOGFILE'"
    _log INFO "- Bcftools isec directory: '$ISEC_DIR'"
    _log INFO "- Haplocheck directory: '$HPLCHK_DIR'"
    _log INFO "- Execution time: $(printf '%02d:%02d:%02d' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60)))"
}

process_haplocheck() {
    local vcf_file="$1"
    local summary_file="$2"
    local hplchk_dir="$3"
    
    _log INFO "Processing haplocheck for '$vcf_file'..."

    # Run Haplocheck
    prefix="${hplchk_dir}/hplchk_tmp"
    if ! java -jar "$HAPLOCHECK_BIN" --raw --out "$prefix" "$vcf_file"; then
        handle_error "haplocheck failed"
    fi
    
    # Update summary file
    local raw_file="${prefix}.raw.txt"
    if [[ ! -e "$summary_file" ]]; then
        cp "$raw_file" "$summary_file"
        _log INFO "File '$summary_file' created (with header)"
    else
        tail -n +2 "$raw_file" >> "$summary_file"
        _log INFO "Line added to '$summary_file'"
    fi

    # Cleanup files
    rm -f "$prefix" "${prefix}.html" "$raw_file"
    _log INFO "Haplocheck completed"
}

validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        handle_error "The specified directory '$dir' does not exist."
    fi
    if [[ ! -r "$dir" || ! -w "$dir" ]]; then
        handle_error "The specified directory '$dir' is not readable or writable."
    fi
}

validate_reference_files() {
    _log INFO "Checking reference files..."
    local ref_files=(
        "$SNPSIFT_BIN"
        "$ANN_GNOMAD"
        "$ANN_MITOMAP_DISEASE"
        "$ANN_MITOMAP_POLYMORPHISMS"
    )
    for ref in "${ref_files[@]}"; do
        if [[ ! -f "$ref" ]]; then
            _log ERROR "Error: Reference file not found: '$ref'" >&2
            exit 1
        fi
        if [[ ! -r "$ref" ]]; then
            _log ERROR "Error: Reference file not readable: '$ref'" >&2
            exit 1
        fi
    done
    _log INFO "All reference files are valid."
}

# --- Main function ---
main() {
    # Setup error handling and cleanup
    trap cleanup_on_exit EXIT
    trap 'handle_error "Script interrupted"' INT TERM

    # Start timing
    START=$(date +%s)

    # Initialize working directory and validate
    WORKDIR=$(cd "${1:-$(pwd)}" && pwd)
    validate_directory "$WORKDIR"
    
    # Extract prefix from directory name
    PREFIX=${WORKDIR##*/}
    PREFIX=${PREFIX:-/}

    # Create directory structure
    LOGDIR="$WORKDIR/logs"
    mkdir -p "$LOGDIR"

    # Setup logging without append
    LOGFILE="$LOGDIR/${PREFIX}-wf-comp.log"
    exec > >(tee "$LOGFILE") 2>&1

    # Workflow information
    _log INFO "Workflow: wf-comp v.$VERSION by $AUTHOR"
    _log INFO "Date: $(LC_TIME=C date '+%b %d, %Y %H:%M:%S')"
    _log INFO "Sample: '$PREFIX'"
    _log INFO "Working directory: '$WORKDIR'"

    # Check dependencies and reference files
    check_dependencies
    validate_reference_files

    # Find VCF files with improved error handling
    local vcf_output
    vcf_output=$(find_vcf_files "$WORKDIR")
    
    # Create the table from the output (compatible with bash 3.2 macOS)
    VCF_FILES=()
    while IFS= read -r line; do
        VCF_FILES+=("$line")
    done <<< "$vcf_output"
    
    # Verifying the number of files found
    if [[ ${#VCF_FILES[@]} -ne 2 ]]; then
        _log ERROR "Error: Expected exactly 2 VCF files, found ${#VCF_FILES[@]}" >&2
        exit 1
    fi

    # Assigning found files (compatible with bash)
    VCF_NANOPORE="${VCF_FILES[0]}"
    VCF_ILLUMINA="${VCF_FILES[1]}"

    _log INFO '**********************'
    _log INFO '* Variant Annotation *'
    _log INFO '**********************'

    # Annotate Illumina VCF
    VCF_ILLUMINA_ANNOTMT="${VCF_ILLUMINA%.vcf}.ann.vcf"
    annotate_vcf "$VCF_ILLUMINA" "$VCF_ILLUMINA_ANNOTMT"

    _log INFO '******************'
    _log INFO '* PASS Filtering *'
    _log INFO '******************'
    VCF_NANOPORE_PASS="${VCF_NANOPORE%.vcf}.PASS.vcf"
    filter_pass_variants "$VCF_NANOPORE" "$VCF_NANOPORE_PASS"

    _log INFO '*************************'
    _log INFO '* Haplogroup Comparison *'
    _log INFO '*************************'

    # Create output directory for haplocheck
    HPLCHK_DIR="$WORKDIR/hplchk-${PREFIX}"
    mkdir -p "$HPLCHK_DIR"
    
    HPLCHK_SUMMARY_FILE="${HPLCHK_DIR}/haplocheck_summary.${PREFIX}.tsv"

    # Process haplocheck for Nanopore and Illumina
    _log INFO "Comparing haplogroups using haplocheck..."

    process_haplocheck "$VCF_NANOPORE_PASS" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"
    process_haplocheck "$VCF_ILLUMINA_ANNOTMT" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"

    _log INFO '***********************'
    _log INFO '* Variants Comparison *'
    _log INFO '***********************'

    # Compress and index files
    compress_and_index "$VCF_NANOPORE"
    compress_and_index "$VCF_ILLUMINA_ANNOTMT"

    # Create output directory for bcftools isec
    ISEC_DIR="$WORKDIR/isec-$PREFIX"
    mkdir -p "$ISEC_DIR"

    # Compare VCF files using bcftools isec
    _log INFO "Comparing VCF files using bcftools isec..."
    if ! bcftools isec "${VCF_NANOPORE}.gz" "${VCF_ILLUMINA_ANNOTMT}.gz" --prefix "$ISEC_DIR" --apply-filters PASS; then
        _log ERROR "Error: bcftools isec failed" >&2
        exit 1
    fi
    
    # Export VCF files to TSV
    _log INFO '******************'
    _log INFO '* TSV Conversion *'
    _log INFO '******************'
    
    # Export specific VCF files in ISEC_DIR
    if [[ -d "$ISEC_DIR" ]]; then
        _log INFO "Converting specific VCF files to TSV in: '$ISEC_DIR'"
        for vcf_num in "0000" "0002"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Nanopore "$vcf_file"
            else
                _log WARN "Warning: File '$vcf_file' not found"
            fi
        done
    else
        _log WARN "Warning: Directory '$ISEC_DIR' not found. Skipping TSV conversion."
    fi

    if [[ -d "$ISEC_DIR" ]]; then
        _log INFO "Converting specific VCF files to TSV in: '$ISEC_DIR'"
        for vcf_num in "0001" "0003"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Illumina "$vcf_file"
            else
                _log WARN "Warning: File '$vcf_file' not found"
            fi
        done
    else
        _log WARN "Warning: Directory $ISEC_DIR not found. Skipping TSV conversion."
    fi

    # Print final messages
    _log INFO '**********'
    _log INFO '* ENDING *'
    _log INFO '**********'

    # End timing
    END=$(date +%s)
    
    # Print summary
    print_summary "$START" "$END"
}

# Run the main function
main "$@"