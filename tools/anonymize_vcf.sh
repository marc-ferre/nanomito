#!/usr/bin/env bash
# SPDX-License-Identifier: CECILL-2.1
# anonymize_vcf.sh - Anonymize sample identifiers in VCF files
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

set -euo pipefail

# Version from git tags (fallback to 'unknown' if not in git repo)
# shellcheck disable=SC2034
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" describe --tags 2>/dev/null || echo 'unknown')"

# anonymize_vcf.sh
# Usage: anonymize_vcf.sh <id_list> <replacement_id> <vcf_file>
#
# <id_list>: comma- or space-separated list of identifiers to replace
# <replacement_id>: identifier to use as replacement

# Parse arguments
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <id_list> <replacement_id> <vcf_file_or_dir> [--hash]" >&2
    exit 2
fi

# read positional
ID_LIST_RAW="$1"
REPL_ID="$2"
INFILE="$3"
shift 3 || true

# defaults for options
HASH_FLAG=0
DRY_RUN=0
OUT_DIR=""
RECURSIVE=0

# parse remaining options
while [ "$#" -gt 0 ]; do
    case "$1" in
        --hash)
            HASH_FLAG=1
            shift
            ;;
        --recursive)
            RECURSIVE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --out-dir)
            if [ $# -lt 2 ]; then
                echo "--out-dir requires a directory argument" >&2
                exit 2
            fi
            OUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# reference RECURSIVE to avoid lint warnings
: "${RECURSIVE:-0}" >/dev/null 2>&1 || true

# Normalize id list: replace commas with spaces
ID_LIST=$(printf '%s' "$ID_LIST_RAW" | tr ',' ' ')

# helper: compute a short deterministic hash for a string (used for log filenames)
compute_short_hash() {
    local s="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        echo -n "$s" | sha256sum | awk '{print substr($1,1,12)}'
    elif command -v shasum >/dev/null 2>&1; then
        echo -n "$s" | shasum -a 256 | awk '{print substr($1,1,12)}'
    elif command -v md5 >/dev/null 2>&1; then
        echo -n "$s" | md5 | awk '{print substr($1,1,12)}'
    else
        # fallback: timestamp+pid (not deterministic across runs)
        date +%s%N-$$
    fi
}

# Define function to process a single file
process_file() {
    local FILE="$1"
    # Recompute per-file values
    local IS_GZ=0
    if [[ "$FILE" == *.gz ]]; then
        IS_GZ=1
    fi
    local DIRNAME
    DIRNAME=$(dirname -- "$FILE")
    local BASENAME
    BASENAME=$(basename -- "$FILE")
    local NEW_BASENAME="$BASENAME"
    for id in $ID_LIST; do
        esc_id=$(printf '%s' "$id" | sed -e 's/[\/&]/\\&/g')
        NEW_BASENAME=$(printf '%s' "$NEW_BASENAME" | sed -e "s/$esc_id/$REPL_ID/g")
    done
    # Determine output locations depending on OUT_DIR and whether input was a directory
    local OUTFILE
    local LOGFILE
    if [ -n "$OUT_DIR" ]; then
        # if the original INFILE was a directory, preserve relative paths
        if [ -d "$INFILE" ]; then
            rel_path=${FILE#"${INFILE}"/}
            out_parent_dir=$(dirname -- "$OUT_DIR/$rel_path")
            if [ "$DRY_RUN" -eq 0 ]; then
                mkdir -p "$out_parent_dir"
            fi
            OUTFILE="$out_parent_dir/$NEW_BASENAME"
            # write logs to the original (source) directory, using the anonymized basename
            LOGFILE="$DIRNAME/${NEW_BASENAME}.log"
        else
            if [ "$DRY_RUN" -eq 0 ]; then
                mkdir -p "$OUT_DIR"
            fi
            OUTFILE="$OUT_DIR/$NEW_BASENAME"
            # write logs to the original (source) directory, using the anonymized basename
            LOGFILE="$DIRNAME/${NEW_BASENAME}.log"
        fi
    else
        OUTFILE="$DIRNAME/$NEW_BASENAME"
            LOGFILE="$DIRNAME/${NEW_BASENAME}.log"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Would anonymize: $FILE -> $OUTFILE"
        echo "  Replace IDs: $ID_LIST_RAW -> $REPL_ID"
        # still compute counts and hashes for info below, but do not write files or logs
    else
        echo "[INFO] Anonymize VCF" > "$LOGFILE"
        date >> "$LOGFILE"
        echo "Input file: $FILE" >> "$LOGFILE"
        echo "Output file: $OUTFILE" >> "$LOGFILE"
        echo "Identifiers to replace: $ID_LIST_RAW" >> "$LOGFILE"
        echo "Replacement id: $REPL_ID" >> "$LOGFILE"
        echo "" >> "$LOGFILE"
    fi

    # Create sed script per-file
    local SED_SCRIPT
    SED_SCRIPT=$(mktemp)
    for id in $ID_LIST; do
        esc=$(printf '%s' "$id" | sed -e 's/[\/&]/\\&/g')
        printf 's/%s/%s/g\n' "$esc" "$REPL_ID" >> "$SED_SCRIPT"
    done

    if [ "$HASH_FLAG" -eq 1 ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            SHA_CMD="sha256sum"
        elif command -v shasum >/dev/null 2>&1; then
            SHA_CMD="shasum -a 256"
        else
            echo "[ERROR] No SHA256 command found (sha256sum or shasum)" >&2
            rm -f "$SED_SCRIPT"
            return 1
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "Identifier hashes:" >&2
        else
            echo "Identifier hashes:" >> "$LOGFILE"
        fi
        local HASHES_LIST=()
        for id in $ID_LIST; do
            H=$(printf '%s' "$id" | $SHA_CMD | awk '{print $1}')
            HASHES_LIST+=("$H")
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  $id -> $H" >&2
            else
                echo "  $id -> $H" >> "$LOGFILE"
            fi
        done
        HASHES_JOINED=$(IFS=,; printf '%s' "${HASHES_LIST[*]}")
        if [ "$DRY_RUN" -eq 0 ]; then
            echo "" >> "$LOGFILE"
        fi
    fi

    # Count occurrences
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Replacement counts (content):" >&2
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "Replacement counts (content):" >&2
        else
            echo "Replacement counts (content):" >> "$LOGFILE"
        fi
    fi
    local TOTAL_REPL=0
    if [ "$IS_GZ" -eq 1 ]; then
        for id in $ID_LIST; do
            CNT=$(zcat -- "$FILE" 2>/dev/null | grep -o -F "$id" | wc -l || true)
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  $id -> $CNT occurrences" >&2
            else
                echo "  $id -> $CNT occurrences" >> "$LOGFILE"
            fi
            TOTAL_REPL=$((TOTAL_REPL + CNT))
        done
    else
        for id in $ID_LIST; do
            CNT=$(grep -o -F "$id" -- "$FILE" | wc -l || true)
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  $id -> $CNT occurrences" >&2
            else
                echo "  $id -> $CNT occurrences" >> "$LOGFILE"
            fi
            TOTAL_REPL=$((TOTAL_REPL + CNT))
        done
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  Total occurrences: $TOTAL_REPL" >&2
        echo "" >&2
    else
        echo "  Total occurrences: $TOTAL_REPL" >> "$LOGFILE"
        echo "" >> "$LOGFILE"
    fi

    # Perform replacement and add header metadata
    DATE_NOW=$(date --utc +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    NUM_IDS=$(printf '%s' "$ID_LIST" | wc -w)
    META_LINE="##anonymizeCommand=<Date=\"$DATE_NOW\",Tool=\"anonymize_vcf.sh\",Args=\"count=$NUM_IDS,replacement=\'$REPL_ID\'\",Log=\"$LOGFILE\">"
    if [ "$HASH_FLAG" -eq 1 ]; then
        META_HASH_LINE="##anonymizeHashes=<Algorithm=\"SHA256\",Count=\"$NUM_IDS\",Hashes=\"$HASHES_JOINED\">"
    else
        META_HASH_LINE=""
    fi
    INFO_LINE="##INFO=<ID=ANON,Number=0,Type=Flag,Description=\"This VCF has been anonymized: original identifiers replaced. See log: $LOGFILE\">"

    if [ "$DRY_RUN" -eq 1 ]; then
        # do not write files
        echo "[DRY-RUN] Would write: $OUTFILE" >&2
    else
        if [ "$IS_GZ" -eq 1 ]; then
            if zcat -- "$FILE" | sed -f "$SED_SCRIPT" | awk -v meta="$META_LINE" -v info="$INFO_LINE" -v mh="$META_HASH_LINE" 'BEGIN{printed=0} /^#CHROM/ { if(!printed){ print meta; if(mh!=""){ print mh }; print info; printed=1 } print; next } { print }' | gzip > "$OUTFILE"; then
                echo "[OK] Wrote anonymized gz VCF to $OUTFILE" >> "$LOGFILE"
            else
                echo "[ERROR] Failed to write anonymized gz VCF" >> "$LOGFILE"
                rm -f "$SED_SCRIPT"
                return 1
            fi
        else
            if sed -f "$SED_SCRIPT" -- "$FILE" | awk -v meta="$META_LINE" -v info="$INFO_LINE" -v mh="$META_HASH_LINE" 'BEGIN{printed=0} /^#CHROM/ { if(!printed){ print meta; if(mh!=""){ print mh }; print info; printed=1 } print; next } { print }' > "$OUTFILE"; then
                echo "[OK] Wrote anonymized VCF to $OUTFILE" >> "$LOGFILE"
            else
                echo "[ERROR] Failed to write anonymized VCF" >> "$LOGFILE"
                rm -f "$SED_SCRIPT"
                return 1
            fi
        fi
    fi

    # Verify post replacement
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Verification (post-replacement counts):" >&2
        echo "  (skipped in dry-run)" >&2
    else
        echo "Verification (post-replacement counts):" >> "$LOGFILE"
        local TOTAL_POST=0
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

        echo "Log written to: $LOGFILE" >> /dev/stderr
        echo "Output: $OUTFILE" >> /dev/stderr
    fi
    rm -f "$SED_SCRIPT"
    return 0
}

# If input is a directory, process all .vcf and .vcf.gz files recursively
if [ -d "$INFILE" ]; then
    find "$INFILE" -type f \( -iname "*.vcf" -o -iname "*.vcf.gz" \) -print0 | while IFS= read -r -d '' f; do
        echo "Processing: $f"
        process_file "$f" || echo "Failed to process $f" >&2
    done
    exit 0
fi

# Otherwise expect a single file
if [ -f "$INFILE" ]; then
    process_file "$INFILE"
    exit $?
fi

echo "[ERROR] Input path not found: $INFILE" >&2
exit 1
