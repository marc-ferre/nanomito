#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh /Path/to/run/dir/
#
set -e

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
cd $1

# Directories
RUN_DIR=`pwd`
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=`basename $RUN_DIR`
SLURM_PRE="slurm-$RUN_ID"
SLURM_EXT='txt'

# Workflow files
WF_BCHG='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-bchg.sh'
WF_SUBWF='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-subwf.sh'

# Mail parameters
MAIL_USER='marc.ferre@univ-angers.fr'
MAIL_TYPE_ALL='ALL'
MAIL_TYPE_END='END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_ISSUE='FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_NONE='NONE'

echo "=== Submit workflows to Slurm ==="
echo "Run dir: $RUN_DIR"

mkdir $PROCESS_DIR
JOBID_LIST=''

WF_ID='bchg'
SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" $WF_BCHG $RUN_DIR)

echo "> Submitted batch job $JOBID"
echo "  Output in $SLURM_FILE"
JOBID_LIST="$JOBID $JOBID_LIST"

WF_ID='subwf'
SLURM_FILE="$PROCESS_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"

JOBID=$(sbatch --dependency=afterok:${JOBID} --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${RUN_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" $WF_SUBWF)

echo "> Submitted batch job $JOBID"
echo "  Output in $SLURM_FILE"
JOBID_LIST="$JOBID $JOBID_LIST"

echo "=== $SAMPLES_COUNT sample(s)/$JOBS_COUNT batch job(s) submitted ==="
echo "|"
echo "| Use following command to cancel all jobs:"
echo "|"
echo "| scancel $JOBID_LIST"
echo "|"
echo "|"
