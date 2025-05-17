#!/bin/bash
#SBATCH --job-name=archiving
#SBATCH --constraint avx2
#SBATCH --time 60
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr

VERSION='25.05.17.1'

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


if rsync -av --stats --progress --delete "$RUN_DIR/" "$ARCHIVING_DIR/"
then
    echo "[OK] Run copied successfully"
else
    echo "[ERROR] While copying"
    exit 1 # die with error
fi

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=$(date +%s)
RUNTIME=$((END - START))
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
echo "Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"