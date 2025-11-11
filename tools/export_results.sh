#!/bin/bash
#
# export_results.sh - Export key result files from nanomito runs
#
# Description:
#   Copies analysis results (TSV, VCF, BAM, BAI files) from run directories
#   in /scratch/mferre/workbench to /scratch/mferre/export/<run_id>
#
################################################################################
# USAGE
################################################################################
show_usage() {
    cat << EOF
Usage: $0 RUN_PATH [RUN_NAME]

Export analysis results from a run directory to export directory, organized by run and sample.

Arguments:
    RUN_PATH    Required. Path to the run directory to export
                (e.g., /scratch/mferre/workbench/250416_run001_recherche_Val)
    
    RUN_NAME    Optional. Name to use for the export directory and ZIP file.
                If not provided, uses the basename of RUN_PATH.

Examples:
    # Export with automatic name (uses basename)
    $0 /scratch/mferre/workbench/250416_run001_recherche_Val
    
    # Export with custom name
    $0 /scratch/mferre/workbench/250416_run001_recherche_Val my_custom_name

Output:
    Files are exported to: $EXPORT_BASE/<run_name>/<sample_id>/
    ZIP archive created:   $EXPORT_BASE/<run_name>.zip

Exported files:
    - *.ann.tsv
    - *.ann.vcf
    - *.chrM.sup,5mC_5hmC,6mA.sorted.bam
    - *.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai
EOF
}
#
# Directory structure:
#   Source: /scratch/mferre/workbench/<run>/processing/<sample>/
#   Target: /scratch/mferre/export/<run>/<sample>/
#

set -euo pipefail

# Enable nullglob to handle patterns that don't match any files
shopt -s nullglob

# Configuration
EXPORT_DIR="/scratch/mferre/export"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Usage information
usage() {
    echo "Usage: $0 RUN_PATH [RUN_NAME]"
    echo ""
    echo "Export analysis results from a run directory to export directory."
    echo ""
    echo "Arguments:"
    echo "  RUN_PATH    Required. Path to the run directory to export"
    echo "              (e.g., /scratch/mferre/workbench/250416_run001_recherche_Val)"
    echo ""
    echo "  RUN_NAME    Optional. Custom name to use for the export directory and ZIP file."
    echo "              If not provided, uses the basename of RUN_PATH."
    echo ""
    echo "Examples:"
    echo "  # Export with automatic name (uses basename of path)"
    echo "  $0 /scratch/mferre/workbench/250416_run001_recherche_Val"
    echo ""
    echo "  # Export with custom name"
    echo "  $0 /scratch/mferre/workbench/250416_run001_recherche_Val my_custom_export"
    echo ""
    echo "Output:"
    echo "  Files are exported to: $EXPORT_DIR/<run_name>/<sample_id>/"
    echo "  ZIP archive created:   $EXPORT_DIR/<run_name>.zip"
    echo ""
    echo "Exported files per sample:"
    echo "  - *.ann.tsv"
    echo "  - *.ann.vcf"
    echo "  - *.chrM.sup,5mC_5hmC,6mA.sorted.bam"
    echo "  - *.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai"
    exit 0
}

# File patterns to export
FILE_PATTERNS=(
    "*.ann.tsv"
    "*.ann.vcf"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai"
)

# Export files for a single sample
export_sample() {
    local sample_dir=$1
    local export_sample_dir=$2
    local sample_id
    sample_id=$(basename "$sample_dir")
    local file_count=0
    
    # Create export directory
    mkdir -p "$export_sample_dir"
    
    # Copy each file pattern
    for pattern in "${FILE_PATTERNS[@]}"; do
        for file in "$sample_dir"/$pattern; do
            if [ -f "$file" ]; then
                cp "$file" "$export_sample_dir/"
                file_count=$((file_count + 1))
            fi
        done
    done
    
    if [ $file_count -gt 0 ]; then
        log_success "  Sample $sample_id: $file_count file(s) exported"
        return 0
    else
        log_warning "  Sample $sample_id: no files found matching patterns"
        return 1
    fi
}

# Export all samples from a run
export_run() {
    local run_dir=$1
    local run_name=$2  # Optional custom name
    local run_id
    
    # Use custom name if provided, otherwise use basename
    if [ -n "$run_name" ]; then
        run_id="$run_name"
    else
        run_id=$(basename "$run_dir")
    fi
    
    local processing_dir="$run_dir/processing"
    local export_run_dir="$EXPORT_DIR/$run_id"
    
    echo ""
    log_info "Processing run: $run_id"
    log_info "Source: $processing_dir"
    log_info "Target: $export_run_dir"
    
    # Check if processing directory exists
    if [ ! -d "$processing_dir" ]; then
        log_error "Processing directory not found: $processing_dir"
        return 1
    fi
    
    # Create export run directory
    mkdir -p "$export_run_dir"
    
    # Count samples and exported files
    local sample_count=0
    local exported_count=0
    
    # Process each sample directory
    for sample_dir in "$processing_dir"/*; do
        # Skip if not a directory or if it's a summary file
        if [ ! -d "$sample_dir" ]; then
            continue
        fi
        
        local sample_id
        sample_id=$(basename "$sample_dir")
        
        # Skip barcode directories (from bchg step)
        if [[ "$sample_id" =~ ^(pass_)?barcode[0-9]+ ]]; then
            continue
        fi
        
        sample_count=$((sample_count + 1))
        
        local export_sample_dir="$export_run_dir/$sample_id"
        
        # Don't fail the script if export_sample returns 1
        if export_sample "$sample_dir" "$export_sample_dir" || true; then
            if [ -d "$export_sample_dir" ] && [ "$(ls -A "$export_sample_dir" 2>/dev/null)" ]; then
                exported_count=$((exported_count + 1))
            fi
        fi
    done
    
    echo ""
    if [ $sample_count -eq 0 ]; then
        log_warning "No samples found in $run_id"
        return 1
    else
        log_success "Run $run_id: $exported_count/$sample_count sample(s) exported successfully"
        
        # Create ZIP archive
        log_info "Creating ZIP archive..."
        local zip_file="$EXPORT_DIR/${run_id}.zip"
        
        # Create ZIP from the export directory
        cd "$EXPORT_DIR" || return 1
        if zip -r -q "${run_id}.zip" "$run_id"; then
            local zip_size
            zip_size=$(du -h "$zip_file" | cut -f1)
            log_success "Archive created: ${run_id}.zip (${zip_size})"
        else
            log_error "Failed to create ZIP archive"
            return 1
        fi
    fi
    
    return 0
}

# Main execution
main() {
    echo "=========================================="
    echo "   Nanomito Results Export"
    echo "=========================================="
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        log_error "Missing required argument: RUN_PATH"
        echo ""
        usage
        
    elif [ $# -eq 1 ]; then
        # One argument: run path (auto-detect name from basename)
        RUN_PATH="$1"
        RUN_NAME=""
        
    elif [ $# -eq 2 ]; then
        # Two arguments: run path + custom name
        RUN_PATH="$1"
        RUN_NAME="$2"
        
    else
        log_error "Too many arguments"
        echo ""
        usage
    fi
    
    # Validate run path
    if [ ! -d "$RUN_PATH" ]; then
        log_error "Run directory not found: $RUN_PATH"
        exit 1
    fi
    
    # Export the run
    export_run "$RUN_PATH" "$RUN_NAME"
    
    echo ""
    echo "=========================================="
    log_success "Export completed"
    echo "=========================================="
    log_info "Results exported to: $EXPORT_DIR"
}

# Show usage if --help or -h
if [ $# -gt 0 ] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

main "$@"
