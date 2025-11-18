#!/usr/bin/env bash
set -euo pipefail

# anonymize_vcf.sh
# Usage: anonymize_vcf.sh <id_list> <replacement_id> <vcf_file>
#
# <id_list>: comma- or space-separated list of identifiers to replace
# <replacement_id>: identifier to use as replacement
# <vcf_file>: path to VCF file (can be .vcf or .vcf.gz)

print_usage() {
    cat <<EOF
Usage: $0 <id_list> <replacement_id> <vcf_file>

  id_list         Comma- or space-separated list of identifiers to anonymize
  replacement_id  Replacement identifier
  vcf_file        Input VCF file (.vcf or .vcf.gz)

Example:
  $0 "SAMPLE1,SAMPLE2" anonymized sample.vcf.gz
EOF
}

if [ "$#" -ne 3 ]; then
    print_usage
    exit 2
fi

ID_LIST_RAW="$1"
REPL_ID="$2"
INFILE="$3"

if [ ! -f "$INFILE" ]; then
    echo "[ERROR] Input file not found: $INFILE" >&2
    exit 1
fi

# Normalize id list: replace commas with spaces
ID_LIST=$(printf '%s' "$ID_LIST_RAW" | tr ',' ' ')

# Detect gzip
IS_GZ=0
if [[ "$INFILE" == *.gz ]]; then
    IS_GZ=1
fi

# Prepare output filename by replacing occurrences in filename
DIRNAME=$(dirname -- "$INFILE")
BASENAME=$(basename -- "$INFILE")
NEW_BASENAME="$BASENAME"
for id in $ID_LIST; do
    # shellcheck disable=SC1001
    esc_id=$(printf '%s' "$id" | sed -e 's/[\/&]/\\&/g')
    NEW_BASENAME=$(printf '%s' "$NEW_BASENAME" | sed -e "s/$esc_id/$REPL_ID/g")
done
OUTFILE="$DIRNAME/$NEW_BASENAME"

# Log file (use anonymized basename to avoid leaking original identifiers)
LOGFILE="$DIRNAME/${NEW_BASENAME}.anonymize.log"

echo "[INFO] Anonymize VCF" > "$LOGFILE"
date >> "$LOGFILE"
echo "Input file: $INFILE" >> "$LOGFILE"
echo "Output file: $OUTFILE" >> "$LOGFILE"
echo "Identifiers to replace: $ID_LIST_RAW" >> "$LOGFILE"
echo "Replacement id: $REPL_ID" >> "$LOGFILE"
echo "" >> "$LOGFILE"

# Create sed script from IDs
SED_SCRIPT=$(mktemp)
trap 'rm -f "$SED_SCRIPT"' EXIT

for id in $ID_LIST; do
    # escape for sed
    esc=$(printf '%s' "$id" | sed -e 's/[\/&]/\\&/g')
    # Use simple global replacement
    printf 's/%s/%s/g\n' "$esc" "$REPL_ID" >> "$SED_SCRIPT"
done

# Count replacements per id in file content
echo "Replacement counts (content):" >> "$LOGFILE"
TOTAL_REPL=0
if [ "$IS_GZ" -eq 1 ]; then
    # use zcat
    for id in $ID_LIST; do
        CNT=$(zcat -- "$INFILE" 2>/dev/null | grep -o -F "$id" | wc -l || true)
        echo "  $id -> $CNT occurrences" >> "$LOGFILE"
        TOTAL_REPL=$((TOTAL_REPL + CNT))
    done
else
    for id in $ID_LIST; do
        CNT=$(grep -o -F "$id" -- "$INFILE" | wc -l || true)
        echo "  $id -> $CNT occurrences" >> "$LOGFILE"
        TOTAL_REPL=$((TOTAL_REPL + CNT))
    done
fi
echo "  Total occurrences: $TOTAL_REPL" >> "$LOGFILE"
echo "" >> "$LOGFILE"

# Perform replacement streamingly
if [ "$IS_GZ" -eq 1 ]; then
    # zcat -> sed -f -> gzip
    # Prepare header metadata lines
    DATE_NOW=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    NUM_IDS=$(printf '%s' "$ID_LIST" | wc -w)
    META_LINE="##anonymizeCommand=<Date=\"$DATE_NOW\",Tool=\"anonymize_vcf.sh\",Args=\"count=$NUM_IDS,replacement=\'$REPL_ID\'\",Log=\"$LOGFILE\">"
    INFO_LINE="##INFO=<ID=ANON,Number=0,Type=Flag,Description=\"This VCF has been anonymized: original identifiers replaced. See log: $LOGFILE\">"

    if zcat -- "$INFILE" | sed -f "$SED_SCRIPT" | awk -v meta="$META_LINE" -v info="$INFO_LINE" 'BEGIN{printed=0} /^#CHROM/ { if(!printed){ print meta; print info; printed=1 } print; next } { print }' | gzip > "$OUTFILE"; then
        echo "[OK] Wrote anonymized gz VCF to $OUTFILE" >> "$LOGFILE"
    else
        echo "[ERROR] Failed to write anonymized gz VCF" >> "$LOGFILE"
        exit 1
    fi
else
    DATE_NOW=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    NUM_IDS=$(printf '%s' "$ID_LIST" | wc -w)
    META_LINE="##anonymizeCommand=<Date=\"$DATE_NOW\",Tool=\"anonymize_vcf.sh\",Args=\"count=$NUM_IDS,replacement=\'$REPL_ID\'\",Log=\"$LOGFILE\">"
    INFO_LINE="##INFO=<ID=ANON,Number=0,Type=Flag,Description=\"This VCF has been anonymized: original identifiers replaced. See log: $LOGFILE\">"

    if sed -f "$SED_SCRIPT" -- "$INFILE" | awk -v meta="$META_LINE" -v info="$INFO_LINE" 'BEGIN{printed=0} /^#CHROM/ { if(!printed){ print meta; print info; printed=1 } print; next } { print }' > "$OUTFILE"; then
        echo "[OK] Wrote anonymized VCF to $OUTFILE" >> "$LOGFILE"
    else
        echo "[ERROR] Failed to write anonymized VCF" >> "$LOGFILE"
        exit 1
    fi
fi

# Count replacements in new file for verification
echo "Verification (post-replacement counts):" >> "$LOGFILE"
TOTAL_POST=0
if [ "$IS_GZ" -eq 1 ]; then
    for id in $ID_LIST; do
        CNT=$(zcat -- "$OUTFILE" 2>/dev/null | grep -o -F "$id" | wc -l || true)
        echo "  remaining $id -> $CNT occurrences" >> "$LOGFILE"
        TOTAL_POST=$((TOTAL_POST + CNT))
    done
else
    for id in $ID_LIST; do
        CNT=$(grep -o -F "$id" -- "$OUTFILE" | wc -l || true)
        echo "  remaining $id -> $CNT occurrences" >> "$LOGFILE"
        TOTAL_POST=$((TOTAL_POST + CNT))
    done
fi
echo "  Total remaining: $TOTAL_POST" >> "$LOGFILE"

echo "Filename replacement:" >> "$LOGFILE"
if [ "$BASENAME" != "$NEW_BASENAME" ]; then
    echo "  Renamed: $BASENAME -> $NEW_BASENAME" >> "$LOGFILE"
else
    echo "  No change to filename" >> "$LOGFILE"
fi

echo "Log written to: $LOGFILE"
echo "Output: $OUTFILE"

exit 0
