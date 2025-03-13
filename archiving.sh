#!/bin/bash
#
# Archiving a run
#
# archiving.sh /Path/to/run/dir/
#
set -e

WF_ARCHIVING='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-archiving.sh'

PROJECTS_DIR='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/projects'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi

echo "Archiving run..."
cd $1
RUN_DIR=`pwd`
RUN_ID=$(basename $RUN_DIR)
echo "Run id : $RUN_ID"

ARCHIVING_DIR="$PROJECTS_DIR/$RUN_ID"
mkdir $ARCHIVING_DIR

SLURM_FILE="$PROJECTS_DIR/slurm-$RUN_ID.txt"

sbatch --chdir=~/ --job-name="a${RUN_ID: -5}" --output="$SLURM_FILE" $WF_ARCHIVING $RUN_DIR $ARCHIVING_DIR
echo "> Output in $SLURM_FILE"