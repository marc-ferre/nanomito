#!/bin/bash
# Fix Nanopore VCF for haplocheck by converting HPL (FORMAT) to AF (INFO)
# This is required because haplocheck expects AF in INFO field

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $(basename "$0") <input.vcf> <output.vcf>

Converts HPL (FORMAT field) to AF (INFO field) for haplocheck compatibility.

Arguments:
  input.vcf   Input VCF file (Nanopore with HPL field)
  output.vcf  Output VCF file (with AF in INFO field)

Example:
  $(basename "$0") sample.vcf sample.fixed.vcf
EOF
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

INPUT_VCF="$1"
OUTPUT_VCF="$2"

# Validate input
if [ ! -f "$INPUT_VCF" ]; then
    echo -e "${RED}Error: Input file not found: $INPUT_VCF${NC}" >&2
    exit 1
fi

echo "Converting HPL to AF for haplocheck..."
echo "Input:  $INPUT_VCF"
echo "Output: $OUTPUT_VCF"
echo ""

# Create temporary file for processing
TMP_VCF=$(mktemp "${OUTPUT_VCF}.tmp.XXXXXX")
trap "rm -f '$TMP_VCF'" EXIT

# Step 1: Rename existing AF to AF_gnomAD and add new AF header
echo "Step 1: Renaming AF (gnomAD) to AF_gnomAD and adding new AF header..."
{
    # Copy all headers, renaming AF to AF_gnomAD
    grep "^##" "$INPUT_VCF" | while read -r line; do
        if [[ "$line" =~ ^##INFO=\<ID=AF, ]]; then
            # Rename AF to AF_gnomAD
            echo "$line" | sed 's/ID=AF,/ID=AF_gnomAD,/' | sed 's/Description="/Description="[gnomAD] /'
        else
            echo "$line"
        fi
    done
    
    # Add Rename AF to AF_gnomAD in INFO and add new AF from HPL
echo "Step 2: Renaming AF to AF_gnomAD in data lines and adding new AF from HPL..."
grep -v "^#" "$INPUT_VCF" | while IFS=$'\t' read -r chrom pos id ref alt qual filter info format sample rest; do
    # Extract HPL value from sample field (assuming single sample)
    # Format is GT:ADF:ADR:HPL:... and sample is 0/1:xxx:xxx:0.01042:...
    hpl_value=$(echo "$sample" | cut -d: -f4)
    
    # Handle multi-allelic sites (HPL can have comma-separated values)
    # For haplocheck, we take the first/max value
    if [[ "$hpl_value" == *","* ]]; then
        # Take the maximum HPL value for multi-allelic sites
        hpl_value=$(echo "$hpl_value" | tr ',' '\n' | sort -rn | head -1)
    fi
    
    # Rename existing AF to AF_gnomAD in INFO field
    new_info=$(echo "$info" | sed -E 's/(^|;)AF=/\1AF_gnomAD=/g')
    
    # Add new AF value from HPL at the beginningvalue" | tr ',' '\n' | sort -rn | head -1)
    fi
    
    # Replace existing AF value with HPL value in INFO field
    # Remove any existing AF= value
    new_info=$(echo "$info" | sed -E 's/;?AF=[^;]+(;|$)/\1/g' | sed 's/^;//' | sed 's/;$//')
    
    # Add new AF value from HPL
    if [ "$new_info" = "." ] || [ -z "$new_info" ]; then
        new_info="AF=$hpl_value"
    else
        new_info="AF=$hpl_value;${new_info}"
    fi
    
    # Output modified line
    echo -e "${chrom}\t${pos}\t${id}\t${ref}\t${alt}\t${qual}\t${filter}\t${new_info}\t${format}\t${sample}${rest:+\t}${rest}"
done >> "$TMP_VCF"

# Move temporary file to output
mv "$TMP_VCF" "$OUTPUT_VCF"

echo ""
echo -e "${GREEN}✓ Conversion complete!${NC}"
echo "Output file: $OUTPUT_VCF"
echo ""
echo "Verification (AF should now equal HPL):"
bcftools query -f '%CHROM:%POS\t%REF>%ALT\t, AF_gnomAD preserved):"
bcftools query -f '%CHROM:%POS\t%REF>%ALT\tAF(sample)=%AF\tAF_gnomAD=%AF_gnomAD\t[HPL=%HPL]\n' "$OUTPUT_VCF" 2>/dev/null | head -5
echo ""
echo -e "${YELLOW}Changes made:${NC}"
echo "  • AF (gnomAD) renamed to AF_gnomAD (preserved)"
echo "  • New AF created from sample HPL values (for haplocheck)"
echo "
