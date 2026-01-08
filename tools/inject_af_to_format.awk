#!/usr/bin/awk -f
# Script to inject AF (Allele Frequency) from HPL or existing AF into FORMAT field
# For Nanopore: extracts HPL from FORMAT/HPL
# For Illumina: preserves/relocates existing FORMAT/AF
# 
# Usage: awk -f inject_af_to_format.awk input.vcf > output.vcf
#
# This ensures haplocheck reads AF from sample columns (FORMAT), not INFO

BEGIN {
    OFS = "\t"
    has_af_header = 0
    af_header_line = "##FORMAT=<ID=AF,Number=A,Type=Float,Description=\"Allele Frequency from sample data\">"
    header_buffer = ""
}

# Accumulate header lines until #CHROM
/^##/ {
    if ($0 ~ /^##FORMAT=<ID=AF/) {
        has_af_header = 1
    }
    if (header_buffer == "") header_buffer = $0; else header_buffer = header_buffer "\n" $0
    next
}

# On #CHROM, flush header with AF if missing, then print #CHROM
/^#CHROM/ {
    if (has_af_header == 0) {
        header_buffer = header_buffer "\n" af_header_line
    }
    if (header_buffer != "") {
        print header_buffer
        header_buffer = ""
    }
    print
    next
}

# Process data lines
!/^#/ {
    # Parse FORMAT field (column 9)
    split($9, format_fields, ":")
    
    # Find indices of HPL and GT and DP in FORMAT
    hpl_idx = 0
    gt_idx = 0
    dp_idx = 0
    af_idx = 0
    
    for (i = 1; i <= length(format_fields); i++) {
        if (format_fields[i] == "HPL") hpl_idx = i
        if (format_fields[i] == "GT") gt_idx = i
        if (format_fields[i] == "AF") af_idx = i
        if (format_fields[i] == "DP") dp_idx = i
    }
    
    # If AF not in FORMAT, add it
    if (af_idx == 0) {
        $9 = $9 ":AF"
        af_idx = length(format_fields) + 1
    }
    
    # Process all sample columns (starting from column 10)
    for (sample_col = 10; sample_col <= NF; sample_col++) {
        split($sample_col, sample_vals, ":")
        
        # Initialize AF value
        af_value = "."
        
        # Try to extract AF value from HPL or existing AF
        if (hpl_idx > 0 && hpl_idx <= length(sample_vals)) {
            hpl_raw = sample_vals[hpl_idx]
            
            # Handle multi-allelic HPL: take max value
            if (hpl_raw != "." && hpl_raw != "") {
                n = split(hpl_raw, hpl_arr, ",")
                af_value = hpl_arr[1] + 0
                for (j = 2; j <= n; j++) {
                    v = hpl_arr[j] + 0
                    if (v > af_value) af_value = v
                }
            }
        } else if (af_idx > 0 && af_idx <= length(sample_vals)) {
            # Preserve existing AF value if it exists
            af_value = sample_vals[af_idx]
        }
        
        # Set or update the AF value in sample data
        if (af_idx <= length(sample_vals)) {
            sample_vals[af_idx] = af_value
        } else {
            # Pad with dots if necessary
            for (k = length(sample_vals) + 1; k < af_idx; k++) {
                sample_vals[k] = "."
            }
            sample_vals[af_idx] = af_value
        }
        
        # Reconstruct sample column
        $sample_col = sample_vals[1]
        for (i = 2; i <= length(sample_vals); i++) {
            $sample_col = $sample_col ":" sample_vals[i]
        }
    }
    
    print
}
