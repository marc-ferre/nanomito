#!/bin/bash
#SBATCH --job-name=wf-modmito
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 15
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2025-01-10.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

SAMPLE_ID=${PWD##*/} # Assign directory name to sample id
SAMPLE_ID=${SAMPLE_ID:-/} # Correct for the case where PWD=/

MODEL_COMPLEX='sup,5mC_5hmC,6mA'

POD5_DIR='/scratch/mferre/workbench/241202_run10/no_sample_id/20241202_1702_MN19558_FBA90343_6e5d6a93/pod5'
DEMULT_PREFIX="$SAMPLE_ID.ont_demult"
DEMULT_FILE="./select-both/${DEMULT_PREFIX}_res.matched.txt"

POD5_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/.local/bin/pod5'
DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.8.3-linux-x64/bin/dorado'
MODKIT_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/modkit_v0.3.1_centos7_x86_64/modkit'

MINIMAP2_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.28_x64-linux/minimap2'
REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'
REF_CHRM='/scratch/mferre/reference/chrM.fa'
REF_MT_2KB='/scratch/mferre/reference/chrM-mt_2kb.fa'
REF_MT_3KB='/scratch/mferre/reference/chrM-mt_3kb.fa'
REF_MT_10KB='/scratch/mferre/reference/chrM-mt_10kb.fa'

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
	if [ -f "$1" ]
	then 
   		echo "[OK] File $1 exists"
   	else
		echo "[ERROR] File $1 doesn't exist"
		exit 9999 # die with error code 9999
	fi
	if [ -s "$1" ]
	then 
   		echo "[OK] File $1 not empty"
   	else
		echo "[ERROR] File $1 is empty"
		exit 9999 # die with error code 9999
	fi
}

START=`date +%s`

echo "Workflow: $SLURM_JOB_NAME v.$VERSION by $AUTHOR"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Working directory: `pwd`"
echo "Raw data directory: $POD5_DIR"
echo "Result file from ont_demult: $DEMULT_FILE"
echo "Model Complex: $MODEL_COMPLEX"
echo "Date: `date`"

echo
echo '***********************'
echo '* Retrieving raw data *'
echo '***********************'

. /local/env/envpython-3.9.5.sh
echo "`$POD5_BIN --version`"

check_file $DEMULT_FILE
cut -f1 $DEMULT_FILE | tail -n +2 > read_ids.txt

check_dir $POD5_DIR
POD5_FILE="$SAMPLE_ID.chrM.pod5"
$POD5_BIN filter $POD5_DIR --output $POD5_FILE --ids read_ids.txt --missing-ok

echo
echo '******************************'
echo '* Modified bases Basecalling *'
echo '******************************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

echo "Dorado version: `$DORADO_BIN --version`"
echo "Modkit version: `$MODKIT_BIN --version`"

BAM_PRE="$SAMPLE_ID.chrM.$MODEL_COMPLEX"
echo "Output file prefix: $BAM_PRE"

$DORADO_BIN duplex $MODEL_COMPLEX $POD5_FILE --reference $REF_MT_3KB > $BAM_PRE.bam
check_file $BAM_PRE.bam

. /local/env/envsamtools-1.15.sh
samtools sort $BAM_PRE.bam -o $BAM_PRE.sorted.bam
samtools index $BAM_PRE.sorted.bam

# Create bedMethyl file
$MODKIT_BIN pileup $BAM_PRE.sorted.bam $BAM_PRE.combine.bed --log-filepath $BAM_PRE.pileup.log
check_file $BAM_PRE.combine.bed

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
