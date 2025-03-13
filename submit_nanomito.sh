#!/bin/bash
#
# Submit workflows to Slurm
#
# submit_nanomito.sh /Path/to/FastQ/dir/
#
set -e

WF_DEMULTMT='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-demultmt.sh'
WF_MODMITO='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-modmito.sh'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi

echo "Submitting workflows to Slurm..."
cd $1
# FASTQ_DIR_PATH=`pwd`
# echo $FASTQ_DIR_PATH
SAMPLE_ID=${PWD##*/}
SAMPLE_ID=${SAMPLE_ID:-/} # to correct for the case where PWD is / (root)
echo "Sample id : $SAMPLE_ID"

cd ../../
RUN_DIR_PATH=`pwd`
echo "Run dir   : $RUN_DIR_PATH"
cd $RUN_DIR

OUT_DIR="processing/$SAMPLE_ID"
echo "Output dir: $OUT_DIR"

SLURM_PRE="slurm-$SAMPLE_ID"
SLURM_EXT="txt"

SLURM_FILE="$RUN_DIR_PATH/$OUT_DIR/$SLURM_PRE.1.$SLURM_EXT"
JOBID=$(sbatch --parsable --chdir=$RUN_DIR_PATH --job-name="d${SAMPLE_ID: -5}" --output="$SLURM_FILE" $WF_DEMULTMT $SAMPLE_ID)
echo "Submitted batch job $JOBID"
echo "> Output in $SLURM_FILE"

SLURM_FILE="$RUN_DIR_PATH/$OUT_DIR/$SLURM_PRE.2.$SLURM_EXT"
sbatch --dependency=afterok:${JOBID} --chdir=$RUN_DIR_PATH --job-name="m${SAMPLE_ID: -5}" --output="$SLURM_FILE" $WF_MODMITO $SAMPLE_ID
echo "> Output in $SLURM_FILE"
