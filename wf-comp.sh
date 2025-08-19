#!/bin/zsh
VERSION='2025-08-18.3'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Description:
# This script compares VCF files generated from Nanopore and Illumina.
# Usage:
#   ./wf-comp.sh /path/to/directory
# If no argument is provided, the current directory will be used by default.

# Exit on error
set -euo pipefail

# Functions
check_dependencies() {
    echo "Checking dependencies..."
    local dependencies=("bgzip" "tabix" "bcftools" "bedtools" "java")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: $cmd is not installed or not in PATH." >&2
            exit 1
        fi
    done
    echo "All dependencies are installed."
}

validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Error: The specified directory '$dir' does not exist." >&2
        exit 1
    fi
}

find_vcf_files() {
    local dir="$1"
    local nanopore_files=("$dir"/*.ann.vcf)
    local illumina_files=("$dir"/i---*.vcf)

    if [[ ! -e "${nanopore_files[1]}" ]]; then
        echo "Error: No Nanopore VCF file found in $dir." >&2
        exit 1
    fi
    if [[ ! -e "${illumina_files[1]}" ]]; then
        echo "Error: No Illumina VCF file found in $dir." >&2
        exit 1
    fi

    echo "${nanopore_files[1]}" "${illumina_files[1]}"
}

annotate_vcf() {
    local input_vcf="$1"
    local output_vcf="$2"
    local tmp_vcf1="${output_vcf}.tmp1"
    local tmp_vcf2="${output_vcf}.tmp2"

    echo "Annotating VCF file: $input_vcf"

    # Annotate with MITOMAP Disease
    java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_DISEASE" "$input_vcf" > "$tmp_vcf1"

    # Annotate with MITOMAP Polymorphisms
    java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_POLYMORPHISMS" "$tmp_vcf1" > "$tmp_vcf2"

    # Annotate with gnomAD
    java -jar "$SNPSIFT_BIN" annotate -v "$ANN_GNOMAD" "$tmp_vcf2" > "$output_vcf"

    # Cleanup temporary files
    rm -f "$tmp_vcf1" "$tmp_vcf2"
}

compress_and_index() {
    local vcf_file="$1"
    echo "Compressing and indexing: $vcf_file"
    bgzip -f "$vcf_file"
    tabix -p vcf -f "${vcf_file}.gz"
}

cleanup_compressed_files() {
    local vcf_file="$1"
    echo "Decompressing and cleaning up: $vcf_file"
    bgzip -d -f "${vcf_file}.gz"
    rm -f "${vcf_file}.gz.tbi"
}

# Main script
main() {
    # Define the working directory
    WORKDIR=${1:-$(pwd)}
    validate_directory "$WORKDIR"

    # Define the prefix
    PREFIX=${WORKDIR##*/}
    PREFIX=${PREFIX:-/}

    # Redirect output to a log file
    LOGFILE="${WORKDIR}/${PREFIX}-wf-comp.log"
    exec > >(tee -a "$LOGFILE") 2>&1

    # Check dependencies
    check_dependencies

   

    # Find VCF files
    read -r VCF_NANOPORE VCF_ILLUMINA <<< "$(find_vcf_files "$WORKDIR")"

    # Workflow information
    echo "Workflow: wf-comp v.$VERSION by $AUTHOR"
    echo "Working directory: $WORKDIR"
    echo "Nanopore VCF: $VCF_NANOPORE"
    echo "Illumina VCF: $VCF_ILLUMINA"
    echo "Date: $(date)"

    # Start timing
    START=$(date +%s)

    echo
    echo '**********************'
    echo '* Variant Annotation *'
    echo '**********************'

    # Annotate Illumina VCF
    VCF_ILLUMINA_ANNOTMT="${VCF_ILLUMINA%.vcf}.ann.vcf"
    annotate_vcf "$VCF_ILLUMINA" "$VCF_ILLUMINA_ANNOTMT"

    echo
    echo '************'
    echo '* Analysis *'
    echo '************'

    # Compress and index files
    compress_and_index "$VCF_NANOPORE"
    compress_and_index "$VCF_ILLUMINA_ANNOTMT"

    # File analysis
    bcftools isec "${VCF_NANOPORE}.gz" "${VCF_ILLUMINA_ANNOTMT}.gz" \
        --prefix "$WORKDIR/isec-$PREFIX" --apply-filters PASS

    # Decompress and cleanup
    cleanup_compressed_files "$VCF_NANOPORE"
    cleanup_compressed_files "$VCF_ILLUMINA_ANNOTMT"

    # End timing
    END=$(date +%s)
    RUNTIME=$((END - START))
    echo ">>> Execution time: $(printf '%02d:%02d:%02d' $((RUNTIME/3600)) $((RUNTIME%3600/60)) $((RUNTIME%60))) (hh:mm:ss)"
}

# References
SNPSIFT_BIN="/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/snpEff/SnpSift.jar"
ANN_GNOMAD='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/gnomAD/gnomad.genomes.v3.1.sites.chrM.vcf'
ANN_MITOMAP_DISEASE='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/disease-nosp.vcf'
ANN_MITOMAP_POLYMORPHISMS='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/polymorphisms.vcf'

# Run the main function
main "$@"