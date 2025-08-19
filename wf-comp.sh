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
        handle_error "The specified directory '$dir' does not exist."
    fi
    if [[ ! -r "$dir" || ! -w "$dir" ]]; then
        handle_error "The specified directory '$dir' is not readable or writable."
    fi
}

validate_reference_files() {
    echo "Checking reference files..."
    local ref_files=(
        "$SNPSIFT_BIN"
        "$ANN_GNOMAD"
        "$ANN_MITOMAP_DISEASE"
        "$ANN_MITOMAP_POLYMORPHISMS"
    )
    for ref in "${ref_files[@]}"; do
        if [[ ! -f "$ref" ]]; then
            echo "Error: Reference file not found: $ref" >&2
            exit 1
        fi
        if [[ ! -r "$ref" ]]; then
            echo "Error: Reference file not readable: $ref" >&2
            exit 1
        fi
    done
    echo "All reference files are valid."
}

find_vcf_files() {
    local dir="$1"
    local debug_msg="Searching for VCF files in: $dir" >&2

    # Utilisation de find pour plus de fiabilité
    local nanopore_file=$(find "$dir" -maxdepth 1 -name "*.ann.vcf" -print -quit)
    local illumina_file=$(find "$dir" -maxdepth 1 -name "i---*.vcf" -print -quit)

    if [[ -z "$nanopore_file" ]]; then
        echo "Error: No Nanopore VCF file (*.ann.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    if [[ -z "$illumina_file" ]]; then
        echo "Error: No Illumina VCF file (i---*.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    # Afficher les messages de débogage sur stderr
    echo "Found:" >&2
    echo "- Nanopore: $nanopore_file" >&2
    echo "- Illumina: $illumina_file" >&2

    # Retourner uniquement les chemins des fichiers sur stdout
    printf "%s\n%s\n" "$nanopore_file" "$illumina_file"
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

export_vcf_to_tsv_Nanopore() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    echo "Exporting VCF to TSV (Nanopore): $input_vcf -> $output_tsv"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tADF\tADR\tQUAL\tDP" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %HPL]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t[ %ADF]\t[ %ADR]\t%QUAL\t%DP\n' "$input_vcf" >> "$output_tsv"

    echo "TSV file generated: $output_tsv"
}

export_vcf_to_tsv_Illumina() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    echo "Exporting VCF to TSV (Illumina): $input_vcf -> $output_tsv"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tQUAL\tDP" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %AF]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t%QUAL\t[ %DP]\n' "$input_vcf" >> "$output_tsv"

    echo "TSV file generated: $output_tsv"
}

# Add new error handling function
handle_error() {
    local error_msg="$1"
    echo "Error: $error_msg" >&2
    exit 1
}

# Add new function to check file existence and permissions
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

# Add new function to create directory
create_directory() {
    local dir="$1"
    local dir_name="$2"
    
    if ! mkdir -p "$dir"; then
        handle_error "Failed to create $dir_name directory: $dir"
    fi
    echo "Created $dir_name directory: $dir"
}

# Modify validate_directory function
validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        handle_error "The specified directory '$dir' does not exist."
    fi
    if [[ ! -r "$dir" || ! -w "$dir" ]]; then
        handle_error "The specified directory '$dir' is not readable or writable."
    fi
}

# Haplogroup processing
process_haplocheck() {
    local vcf_file="$1"
    local summary_file="$2"
    local hplchk_dir="$3"
    
    prefix="${hplchk_dir}/hplchk_tmp"

    echo "Processing haplocheck for $vcf_file..."
    
    if ! java -jar "$HAPLOCHECK_BIN" --raw --out "$prefix" "$vcf_file"; then
        handle_error "haplocheck failed"
    fi
    
    # Update summary file
    local raw_file="${prefix}.raw.txt"
    if [[ ! -e "$summary_file" ]]; then
        cp "$raw_file" "$summary_file"
        echo "[OK] File $summary_file created (with header)"
    else
        tail -n +2 "$raw_file" >> "$summary_file"
        echo "[OK] Line added to $summary_file"
    fi

    # Cleanup files
    rm -f "$prefix" "${prefix}.html" "$raw_file" 
}

# Main function
main() {
    # Define the working directory
    WORKDIR=$(cd "${1:-$(pwd)}" && pwd)
    echo "Working directory: $WORKDIR"
    validate_directory "$WORKDIR"

    # Create logs directory
    LOGDIR="$WORKDIR/logs"
    mkdir -p "$LOGDIR"

    # Define the prefix
    PREFIX=${WORKDIR##*/}
    PREFIX=${PREFIX:-/}

    # Redirect output to a log file (without append)
    LOGFILE="$LOGDIR/${PREFIX}-wf-comp.log"
    exec > >(tee "$LOGFILE") 2>&1

    # Check dependencies and reference files
    check_dependencies
    validate_reference_files

    # Find VCF files with improved error handling
    local vcf_output
    vcf_output=$(find_vcf_files "$WORKDIR")
    
    # Créer le tableau à partir de la sortie
    VCF_FILES=("${(f)vcf_output}")
    
    # Vérification du nombre de fichiers trouvés
    if [[ ${#VCF_FILES[@]} -ne 2 ]]; then
        echo "Error: Expected exactly 2 VCF files, found ${#VCF_FILES[@]}" >&2
        exit 1
    fi

    # Attribution des fichiers trouvés
    VCF_NANOPORE="${VCF_FILES[1]}"  # En Zsh, les tableaux commencent à 1
    VCF_ILLUMINA="${VCF_FILES[2]}"   # En Zsh, les tableaux commencent à 1

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
    echo '*************************'
    echo '* Haplogroup Comparison *'
    echo '*************************'

    # Create output directory for haplocheck
    HPLCHK_DIR="$WORKDIR/hplchk-${PREFIX}"
    mkdir -p "$HPLCHK_DIR"
    
    HPLCHK_SUMMARY_FILE="${HPLCHK_DIR}/haplocheck_summary.${PREFIX}.tsv"

    # Process haplocheck for Nanopore and Illumina
    echo "Comparing haplogroups using haplocheck..."

    process_haplocheck "$VCF_NANOPORE" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"
    process_haplocheck "$VCF_ILLUMINA_ANNOTMT" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"

    echo
    echo '***********************'
    echo '* Variants Comparison *'
    echo '***********************'

    # Compress and index files
    compress_and_index "$VCF_NANOPORE"
    compress_and_index "$VCF_ILLUMINA_ANNOTMT"

    # Create output directory for bcftools isec
    ISEC_DIR="$WORKDIR/isec-$PREFIX"
    mkdir -p "$ISEC_DIR"

    # Compare VCF files using bcftools isec
    echo "Comparing VCF files using bcftools isec..."
    if ! bcftools isec "${VCF_NANOPORE}.gz" "${VCF_ILLUMINA_ANNOTMT}.gz" --prefix "$ISEC_DIR" --apply-filters PASS; then
        echo "Error: bcftools isec failed" >&2
        exit 1
    fi


    # Decompress and cleanup
    cleanup_compressed_files "$VCF_NANOPORE"
    cleanup_compressed_files "$VCF_ILLUMINA_ANNOTMT"
    
    # Remove annotated Illumina VCF
    echo "Removing annotated Illumina VCF file: $VCF_ILLUMINA_ANNOTMT"
    rm -f "$VCF_ILLUMINA_ANNOTMT"

    # Export VCF files to TSV
    echo
    echo '*******************'
    echo '* TSV Conversion *'
    echo '*******************'
    
    # Export specific VCF files in ISEC_DIR
    if [[ -d "$ISEC_DIR" ]]; then
        echo "Converting specific VCF files to TSV in: $ISEC_DIR"
        for vcf_num in "0000" "0002"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Nanopore "$vcf_file"
            else
                echo "Warning: File $vcf_file not found"
            fi
        done
    else
        echo "Warning: Directory $ISEC_DIR not found. Skipping TSV conversion."
    fi

    if [[ -d "$ISEC_DIR" ]]; then
        echo "Converting specific VCF files to TSV in: $ISEC_DIR"
        for vcf_num in "0001" "0003"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Illumina "$vcf_file"
            else
                echo "Warning: File $vcf_file not found"
            fi
        done
    else
        echo "Warning: Directory $ISEC_DIR not found. Skipping TSV conversion."
    fi

    # End timing
    END=$(date +%s)
    RUNTIME=$((END - START))
    echo ">>> Execution time: $(printf '%02d:%02d:%02d' $((RUNTIME/3600)) $((RUNTIME%3600/60)) $((RUNTIME%60))) (hh:mm:ss)"

    # Add summary information
    echo
    echo "Summary:"
    echo "- Input directory: $WORKDIR"
    echo "- Log file: $LOGFILE"
    echo "- Output directory: $ISEC_DIR"
    echo "- Execution time: $(printf '%02d:%02d:%02d' $((RUNTIME/3600)) $((RUNTIME%3600/60)) $((RUNTIME%60)))"
}

# References
HAPLOCHECK_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/haplocheck/haplocheck.jar'   
SNPSIFT_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/snpEff/SnpSift.jar'
ANN_GNOMAD='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/gnomAD/gnomad.genomes.v3.1.sites.chrM.vcf'
ANN_MITOMAP_DISEASE='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/disease-nosp.vcf'
ANN_MITOMAP_POLYMORPHISMS='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/polymorphisms.vcf'

# Add cleanup function at the end of the script, before main()
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        echo "Script failed with errors. Check the log file for details: $LOGFILE"
    fi
    
    # Cleanup temporary files
    rm -f "$VCF_ILLUMINA_ANNOTMT"
    cleanup_compressed_files "$VCF_NANOPORE"
    cleanup_compressed_files "$VCF_ILLUMINA_ANNOTMT"
}

# Run the main function
main "$@"