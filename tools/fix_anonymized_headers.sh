#!/usr/bin/env bash
# SPDX-License-Identifier: CECILL-2.1
# fix_anonymized_headers.sh - Fix headers in anonymized VCF files
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

set -euo pipefail

# Version from git tags (fallback to 'unknown' if not in git repo)
# shellcheck disable=SC2034
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" describe --tags 2>/dev/null || echo 'unknown')"

# fix_anonymized_headers.sh
# Usage: tools/fix_anonymized_headers.sh [root_dir]
#
# Scans for directories named '*_anonymized', and for each uncompressed VCF inside
# attempts to replace the Log="..." value in the header '##anonymizeCommand' to
# point to a matching '.anonymize.log' file located in the corresponding source
# directory (the anon dir name without the '_anonymized' suffix).

ROOT_DIR="${1:-.}"
changed=0

shopt -s nullglob

find "$ROOT_DIR" -type d -name '*_anonymized' -print0 | while IFS= read -r -d '' anon_dir; do
  src_dir="${anon_dir%_anonymized}"
  if [ ! -d "$src_dir" ]; then
    echo "Skipping $anon_dir (no source dir: $src_dir)"
    continue
  fi
  echo "Processing anonymized dir: $anon_dir -> source: $src_dir"

  find "$anon_dir" -type f \( -iname "*.vcf" -o -iname "*.vcf.gz" \) -print0 | while IFS= read -r -d '' vfile; do
    if [[ "$vfile" == *.gz ]]; then
      echo "  Skip gz file: $vfile"
      continue
    fi

    cmdline=$(grep -m1 '^##anonymizeCommand=' "$vfile" || true)
    if [ -z "$cmdline" ]; then
      echo "  No anonymizeCommand header in: $vfile"
      continue
    fi

    repl=$(printf '%s' "$cmdline" | sed -n "s/.*replacement='\([^']*\)'.*/\1/p")
    if [ -z "$repl" ]; then
      echo "  Cannot extract replacement id from header in: $vfile"
      continue
    fi

    cur_log=$(printf '%s' "$cmdline" | sed -n 's/.*Log="\([^"]*\)".*/\1/p') || true
    if [ -z "$cur_log" ]; then
      echo "  No Log field in header for: $vfile"
      continue
    fi

    anon_base=$(basename -- "$vfile")

    if [[ "$anon_base" == *"$repl"* ]]; then
      left=${anon_base%%"$repl"*}
      right=${anon_base#*"$repl"}
    else
      left=${anon_base%%_*}_
      right=${anon_base#*_}
    fi

    # build candidate pattern in source dir
    pattern="${left}*${right}.log"
    # expand candidates (iterate to avoid word-splitting issues)
    candidates=()
    for f in "$src_dir"/$pattern; do
      if [ -f "$f" ]; then
        candidates+=("$f")
      fi
    done

    real_candidates=("${candidates[@]}")

    if [ ${#real_candidates[@]} -eq 0 ]; then
      echo "  No matching log in source for $vfile (pattern: $pattern)"
      continue
    elif [ ${#real_candidates[@]} -gt 1 ]; then
      echo "  Multiple candidate logs in source for $vfile, skipping:"
      for rc in "${real_candidates[@]}"; do
        echo "    $rc"
      done
      continue
    fi

    new_log=${real_candidates[0]}
    echo "  Found source log: $new_log"

    # Replace Log="..." in anonymizeCommand and update INFO line that references the log
    tmpf=$(mktemp)
    awk -v new="$new_log" '
    /^##anonymizeCommand=/ { gsub(/Log="[^"]*"/, "Log=\"" new "\"") }
    /^##INFO=<ID=ANON/ { gsub(/See log: [^\"]*/, "See log: " new) }
    { print }
    ' "$vfile" > "$tmpf"

    mv "$vfile" "$vfile".bak
    mv "$tmpf" "$vfile"
    echo "  Updated header in: $vfile (backup: $vfile.bak)"
    changed=$((changed+1))

  done
done

echo "Done. Files updated: $changed"
