#!/usr/bin/env bash
set -euo pipefail

BASE="/Users/marcferre/Documents/Recherche/Projets/Nanomito/Analyses/Comparaisons/2025-01 Article/Anonymized"
printf "Sample,Errors,Warnings\n"
for d in "$BASE"/*; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  LOG="$d/logs/${name}-compare_vcf.log"
  if [ ! -f "$LOG" ]; then
    printf "%s,NO_LOG,NO_LOG\n" "$name"
    continue
  fi
  errs=$(grep -E -c '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[ERROR\]' "$LOG" 2>/dev/null || true)
  warns=$(grep -E -c '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[WARN\]' "$LOG" 2>/dev/null || true)
  printf "%s,%s,%s\n" "$name" "$errs" "$warns"
done
