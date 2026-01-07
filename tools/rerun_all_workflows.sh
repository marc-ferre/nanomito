#!/usr/bin/env bash
# SPDX-License-Identifier: CECILL-2.1
# Batch relance des workflows Nanomito sur un ensemble de runs.
# Soumet pour chaque run: submit_nanomito.sh --skip-bchg (par défaut) afin de réanalyser avec les dernières annotations/AF.
#
# Usage:
#   tools/rerun_all_workflows.sh /chemin/vers/racine_runs [options]
#
# Options:
#   --dry-run           Affiche les commandes sans exécuter
#   --no-skip-bchg      Ne pas passer --skip-bchg (relance aussi bchg)
#   --only-needing      Ne soumettre que les runs qui semblent nécessiter la relance
#   --pattern GLOB      Ne traiter que les dossiers correspondant au motif (ex: 2405*)
#   --sleep SEC         Pause entre soumissions (défaut: 2s)
#   --include-unclassified  Passe à submit_nanomito.sh
#   --only-samples LIST      Passe à submit_nanomito.sh (ex: S1,S2)
#   --export-name NAME       Passe à submit_nanomito.sh
#   --extra "ARGS"        Args additionnels passés à submit_nanomito.sh tels quels
#   --summary FILE        Écrit un récap TSV (timestamp, run_dir, status, args)
#
# Notes:
# - Détection "--only-needing": cherche un VCF nanopo re *.ann.vcf (ou .vcf.gz) et vérifie
#   la présence d'un header INFO/AF et de tags préfixés MitoMap_/gnomAD_. Si absent → relance.
# - Vous pouvez adapter la logique de découverte des runs via --pattern.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMIT_SCRIPT="${SCRIPT_DIR}/submit_nanomito.sh"

if [[ ! -x "$SUBMIT_SCRIPT" ]]; then
  echo "[ERROR] Script introuvable ou non exécutable: $SUBMIT_SCRIPT" >&2
  exit 1
fi

DRY_RUN=false
SKIP_BCHG=true
ONLY_NEED=false
PATTERN="*"
SLEEP_SEC=2
INCLUDE_UNCLASSIFIED=false
ONLY_SAMPLES=""
EXPORT_NAME=""
EXTRA_ARGS=""
SUMMARY_FILE=""

ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-skip-bchg) SKIP_BCHG=false; shift ;;
    --only-needing) ONLY_NEED=true; shift ;;
    --pattern) PATTERN="${2:-*}"; shift 2 ;;
    --sleep) SLEEP_SEC="${2:-2}"; shift 2 ;;
    --include-unclassified) INCLUDE_UNCLASSIFIED=true; shift ;;
    --only-samples) ONLY_SAMPLES="${2:-}"; shift 2 ;;
    --export-name) EXPORT_NAME="${2:-}"; shift 2 ;;
    --extra) EXTRA_ARGS="${2:-}"; shift 2 ;;
    --summary) SUMMARY_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,120p' "$0" | sed -n '1,80p'
      exit 0
      ;;
    *)
      if [[ -z "$ROOT" ]]; then ROOT="$1"; shift; else echo "[ERROR] Argument inattendu: $1" >&2; exit 1; fi ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  echo "[ERROR] Spécifiez la racine des runs." >&2
  echo "Ex: tools/rerun_all_workflows.sh /workbench/runs --dry-run --only-needing" >&2
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "[ERROR] Répertoire introuvable: $ROOT" >&2
  exit 1
fi

needs_rerun() {
  # $1 = run_dir
  local run_dir="$1"
  # Cherche un VCF annoté Nanopore pour inspection
  local vcf
  vcf=$(find "$run_dir" -maxdepth 3 -type f \( -name "*.ann.vcf" -o -name "*.ann.vcf.gz" \) -print -quit 2>/dev/null || true)
  if [[ -z "$vcf" ]]; then
    # Pas de VCF trouvé → on considère qu'une relance est utile
    return 0
  fi
  # Lecture 200 premières lignes (header + début) selon compression
  local head_content=""
  if [[ "$vcf" == *.gz ]]; then
    head_content=$(zcat "$vcf" 2>/dev/null | head -n 200 2>/dev/null || true)
  else
    head_content=$(head -n 200 "$vcf" 2>/dev/null || true)
  fi
  if [[ -z "$head_content" ]]; then
    # Pas pu lire le VCF → on relance pour être sûr
    return 0
  fi
  # Vérifie présence du header INFO/AF (nouveau champ)
  if ! echo "$head_content" | grep -qE '^##INFO=<ID=AF,.*Description="Allele Frequency from sample for haplocheck"'; then
    return 0
  fi
  # Vérifie présence des préfixes d'annotations
  if ! echo "$head_content" | grep -q 'MitoMap_'; then
    return 0
  fi
  if ! echo "$head_content" | grep -q 'gnomAD_'; then
    return 0
  fi
  # Tout semble à jour → pas besoin de relancer
  return 1
}

if [[ -n "$SUMMARY_FILE" ]]; then
  # Initialise le fichier résumé avec en-tête TSV
  {
    echo -e "timestamp\trun_dir\tstatus\targs"
  } > "$SUMMARY_FILE"
fi

append_summary() {
  # $1=status, $2=run_dir, $3=args_str
  [[ -z "$SUMMARY_FILE" ]] && return 0
  local ts
  ts=$(date '+%F %T')
  printf '%s\t%s\t%s\t%s\n' "$ts" "$2" "$1" "$3" >> "$SUMMARY_FILE"
}

submit_one() {
  local run_dir="$1"
  local args=()
  $SKIP_BCHG && args+=("--skip-bchg")
  $INCLUDE_UNCLASSIFIED && args+=("--include-unclassified")
  [[ -n "$ONLY_SAMPLES" ]] && args+=("--only-samples" "$ONLY_SAMPLES")
  [[ -n "$EXPORT_NAME" ]] && args+=("--export-name" "$EXPORT_NAME")
  if [[ -n "$EXTRA_ARGS" ]]; then
    # shellcheck disable=SC2206
    extra_arr=( $EXTRA_ARGS )
    args+=("${extra_arr[@]}")
  fi
  local args_str
  args_str="${args[*]}"
  echo "[CMD] $SUBMIT_SCRIPT ${args_str} \"$run_dir\""
  if ! $DRY_RUN; then
    # shellcheck disable=SC2086
    "$SUBMIT_SCRIPT" ${args[@]} "$run_dir"
    append_summary "SUBMITTED" "$run_dir" "$args_str"
  else
    append_summary "DRY_RUN" "$run_dir" "$args_str"
  fi
  return 0
}

count_total=0
count_submitted=0
count_skipped=0

# Découverte des runs
shopt -s nullglob
for run_dir in "$ROOT"/$PATTERN/; do
  [[ -d "$run_dir" ]] || continue
  ((count_total++))
  if $ONLY_NEED; then
    if needs_rerun "$run_dir"; then
      submit_one "$run_dir"
      ((count_submitted++))
    else
      echo "[SKIP] $run_dir (semble déjà à jour)"
      ((count_skipped++))
      append_summary "SKIPPED_UP_TO_DATE" "$run_dir" "--only-needing ${PATTERN:+--pattern $PATTERN}"
    fi
  else
    submit_one "$run_dir"
    ((count_submitted++))
  fi
  sleep "$SLEEP_SEC"
done
shopt -u nullglob

echo "[SUMMARY] Total: $count_total | Soumis: $count_submitted | Sautés: $count_skipped"
