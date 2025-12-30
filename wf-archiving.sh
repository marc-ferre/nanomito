#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
#SBATCH --job-name=archiving
#SBATCH --constraint avx2
#SBATCH --time 600
#SBATCH --mail-type=FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" describe --tags 2>/dev/null || echo 'unknown')"

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 2 # die with error
fi
RUN_DIR=$1
RUN_ID=$(basename "$RUN_DIR")

if [ $# -eq 1 ]
	then
		echo "[ERROR] Second argument missing"
		exit 2 # die with error
fi
ARCHIVING_DIR=$2

START=$(date +%s)

echo "Workflow: wf-archiving v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Archiving directory: $ARCHIVING_DIR"
echo "Date: $(date)"

# Initialize archiving summary file
PROCESS_DIR="$RUN_DIR/processing"
ARCHIVING_SUMMARY="$PROCESS_DIR/archiving_summary.$RUN_ID.tsv"
ERROR_LOG=""

echo
echo '*************'
echo '* Clean run *'
echo '*************'

clean_dir () {
	DIR_TO_CLEAN=$1

	if [ -d "$DIR_TO_CLEAN" ]
	then		
			if rm -Rf "$DIR_TO_CLEAN"
			then
    			echo "[OK] Directory cleaned successfully: $DIR_TO_CLEAN"
			else
    			echo "[ERROR] Can't clean directory: $DIR_TO_CLEAN"
    			exit 2 # die with error
			fi
	else
		echo "[WARNING] Directory doesn't exist: $DIR_TO_CLEAN"
	fi
}

echo
echo '************'
echo '* Copy run *'
echo '************'

echo "From: $RUN_DIR "
echo "To  : $ARCHIVING_DIR "


if rsync -av --stats --progress --delete "$RUN_DIR/" "$ARCHIVING_DIR/" 2>&1 | tee /tmp/rsync_output_$$.txt
then
    echo "[OK] Run copied successfully"
    ARCHIVE_STATUS="success"
    
    # Calculate size with du for human-readable format (force English locale for decimal point)
    TOTAL_SIZE=$(LC_NUMERIC=C du -sh "$ARCHIVING_DIR" 2>/dev/null | cut -f1 || echo "N/A")
else
    echo "[ERROR] While copying"
    ARCHIVE_STATUS="failed"
    ERROR_LOG="rsync failed during archiving"
    TOTAL_SIZE="N/A"
fi

# Clean up temp file
rm -f /tmp/rsync_output_$$.txt

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=$(date +%s)
RUNTIME=$((END - START))
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
RUNTIME_FORMATTED=$(printf "%02d:%02d:%02d" $HOURS $MINUTES $SECONDS)
echo "Runtime: $RUNTIME_FORMATTED (hh:mm:ss)"

# Write archiving summary file
echo "Writing archiving summary to: $ARCHIVING_SUMMARY"
{
    echo -e "Status\tArchiving directory\tTotal size\tRuntime (hh:mm:ss)\tError"
    echo -e "$ARCHIVE_STATUS\t$ARCHIVING_DIR\t$TOTAL_SIZE\t$RUNTIME_FORMATTED\t$ERROR_LOG"
} > "$ARCHIVING_SUMMARY"

echo "[OK] Archiving summary written to: $ARCHIVING_SUMMARY"

# Exit with error if archiving failed
if [ "$ARCHIVE_STATUS" = "failed" ]; then
    exit 1
fi