#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
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

Converts HPL (FORMAT field) or FORMAT AF to INFO/AF for haplocheck compatibility.

Arguments:
    input.vcf   Input VCF file (Nanopore with HPL field or Illumina with FORMAT AF)
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

echo "Converting heteroplasmy to INFO/AF for haplocheck..."
echo "Input:  $INPUT_VCF"
echo "Output: $OUTPUT_VCF"
echo ""

# Process file: rename any existing INFO/AF to INFO/AF_gnomAD, add new AF header, and add AF from FORMAT
awk 'BEGIN{OFS="\t"}
    # Header lines: rename INFO/AF to INFO/AF_gnomAD
    /^##/ {
        line=$0
        if (line ~ /^##INFO=<ID=AF,/) {
            gsub(/ID=AF,/, "ID=AF_gnomAD,", line)
            # Optionally tag description to indicate origin
            gsub(/Description=\"/, "Description=\"[gnomAD] ", line)
        }
        print line
        next
    }
    # Insert new AF header just before the column header
    /^#CHROM/ {
        print "##INFO=<ID=AF,Number=A,Type=Float,Description=\"Allele Frequency from sample heteroplasmy (HPL) or FORMAT AF for haplocheck\">"
        print
        next
    }
    # Data lines: compute AF from FORMAT (prefer HPL, else FORMAT AF), handle multi-allelic, prepend AF
    !/^#/ {
        info=$8
        # Rename any INFO/AF to INFO/AF_gnomAD at start or after semicolons
        if (info ~ /^AF=/) { info = "AF_gnomAD" substr(info,3) }
        gsub(/;AF=/, ";AF_gnomAD=", info)

        # Parse FORMAT keys and sample values (assumes single-sample VCF)
        split($9, fmt, ":")
        split($10, samp, ":")
        hpl_idx=0; af_idx=0
        for(i=1;i<=length(fmt);i++){
            if(fmt[i]=="HPL") hpl_idx=i
            if(fmt[i]=="AF") af_idx=i
        }
        af_value=""
        if(hpl_idx>0){ af_value=samp[hpl_idx] }
        else if(af_idx>0){ af_value=samp[af_idx] }

        if(af_value!=""){
            # For multi-allelic, take max value (numeric comparison)
            if(index(af_value,",")>0){
                n=split(af_value, arr, ",")
                maxv=arr[1]+0
                for(i=2;i<=n;i++){ v=arr[i]+0; if(v>maxv) maxv=v }
                af_value=maxv
            }
            if(info=="." || info=="") info="AF=" af_value
            else info="AF=" af_value ";" info
        }
        $8=info
        print
        next
    }
    { print }
' "$INPUT_VCF" > "$OUTPUT_VCF"

echo -e "${GREEN}✓ Conversion complete!${NC}"
echo "Output file: $OUTPUT_VCF"
echo ""
echo -e "${YELLOW}Note:${NC} INFO/AF_gnomAD is preserved (if present); new INFO/AF is derived from sample FORMAT (HPL or AF)."
