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
if [ -d "$ARCHIVING_DIR" ]; then
    echo "[WARNING] Archiving directory already exist: $ARCHIVING_DIR exist"
    echo "Do you want overwrite it? (y/n)"
    read YN
    if [ $YN -eq "y" ];
    then
        echo "Overwritting..."
    else
    	echo "Exiting..."
        exit 0
    fi
else
	mkdir $ARCHIVING_DIR
fi    


SLURM_FILE="$PROJECTS_DIR/slurm-$RUN_ID.txt"

sbatch --chdir=~/ --job-name="a${RUN_ID: -5}" --output="$SLURM_FILE" $WF_ARCHIVING $RUN_DIR $ARCHIVING_DIR
echo "> Output in $SLURM_FILE"