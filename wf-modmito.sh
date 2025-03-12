#!/bin/bash
#SBATCH --job-name=modmito
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 15
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr

VERSION='2025-03-12.2'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Run Id = Working directory
RUN_ID=${PWD##*/} # Assign directory name to run id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Sample Id = Argument
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
SAMPLE_ID=$1

# Basecalling model
MODEL_COMPLEX='sup,5mC_5hmC,6mA'

# Read selection strategy (start, both, either ,xor)
SELECT='both'

# Directories
RUN_DIR=`pwd`
PROCESS_DIR="$RUN_DIR/processing"
OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
SELECT_DIR="$OUT_DIR/select-$SELECT"

# Binary and Conda env
DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.9.1-linux-x64/bin/dorado'
MODMITO_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_modmito'
#MODKIT_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_modkit'

# References
REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'
REF_MT='/scratch/mferre/reference/chrM.fa'
REF_MT_2KB='/scratch/mferre/reference/chrM-mt_2kb.fa'
REF_MT_3KB='/scratch/mferre/reference/chrM-mt_3kb.fa'
REF_MT_10KB='/scratch/mferre/reference/chrM-mt_10kb.fa'

# Prefixes
BAM_PREFIX="$SAMPLE_ID.chrM.$MODEL_COMPLEX"

# Files
DEMULT_POD5_FILE="$OUT_DIR/$SAMPLE_ID.demultmt.pod5"
BAM_FILE="$OUT_DIR/$BAM_PREFIX.bam"
SORTED_BAM_FILE="$OUT_DIR/$BAM_PREFIX.sorted.bam"
BEDMETHYL_FILE="$OUT_DIR/$BAM_PREFIX.combine.bed"
PILEUP_LOG_FILE="$OUT_DIR/$BAM_PREFIX.pileup.log"
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

check_dir () { 
	if [ -d "$1" ]
	then 
   		echo "[OK] Directory $1 exists"
   	else
		echo "[ERROR] Directory $1 doesn't exist"
		exit 9999 # die with error code 9999
	fi
}
check_file () { 
	if [ -f "$1" ] && [ -s "$1" ]
	then 
   		echo "[OK] File $1 exists and is not empty"
   	else
		echo "[ERROR] File $1 is empty or doesn't exist"
		exit 9999 # die with error code 9999
	fi
}

START=`date +%s`

echo "Workflow: wf-modmito v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Output directory: $OUT_DIR"
echo "Read selection strategy: $SELECT"
echo "Pod5 file: $DEMULT_POD5_FILE"
echo "Model Complex: $MODEL_COMPLEX"
echo "Date: `date`"

echo
echo '******************************'
echo '* Modified bases Basecalling *'
echo '******************************'
check_file $DEMULT_POD5_FILE

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

echo "Dorado version: `$DORADO_BIN --version`"

echo "Output file prefix: $BAM_PRE"

$DORADO_BIN basecaller $MODEL_COMPLEX $DEMULT_POD5_FILE --reference $REF_MT_3KB > $BAM_FILE
check_file $BAM_FILE

echo
echo '****************************'
echo '* Sorted BAM and bedMethyl *'
echo '****************************'

. /local/env/envconda.sh
conda activate $MODMITO_ENV

echo "`samtools --version`"

samtools sort $BAM_FILE -o $SORTED_BAM_FILE
check_file $SORTED_BAM_FILE
samtools index $SORTED_BAM_FILE
check_file "${SORTED_BAM_FILE}.bai"

echo "Modkit version: `modkit --version`"

modkit pileup $SORTED_BAM_FILE $BEDMETHYL_FILE --log-filepath $PILEUP_LOG_FILE
check_file $BEDMETHYL_FILE

conda deactivate

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=`date +%s`
RUNTIME=$(echo "$END - $START")
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
echo ">>> Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"

if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm)" > $WORKFLOW_SUMMARY_FILE
	echo "[OK] File $WORKFLOW_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID	$SAMPLE_ID	modmito	$HOURS:$MINUTES" >> $WORKFLOW_SUMMARY_FILE
echo "[OK] Line added to $WORKFLOW_SUMMARY_FILE"