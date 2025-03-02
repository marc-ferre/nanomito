#!/bin/bash
#SBATCH --job-name=wf-fullmap
#SBATCH --cpus-per-task=10
#SBATCH --mem=50G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2024-03-14.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

SAMPLE_ID=${PWD##*/} # Assign directory name to sample id
SAMPLE_ID=${SAMPLE_ID:-/} # Correct for the case where PWD=/

DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.3-linux-x64/bin/dorado'

CALLS_FILE=`find ~+ -type f -name 'calls.bam'`
REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'

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
echo "Calls file: $CALLS_FILE"
echo "Date: `date`"
echo
echo '******************************'
echo '* Mapping Standard Reference *'
echo '******************************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

check_file $CALLS_FILE
$DORADO_BIN aligner $REF_WHOLE $CALLS_FILE > $SAMPLE_ID.fullmap.bam

. /local/env/envsamtools-1.15.sh
samtools sort $SAMPLE_ID.fullmap.bam -o $SAMPLE_ID.fullmap.sorted.bam
check_file $SAMPLE_ID.fullmap.sorted.bam
samtools index $SAMPLE_ID.fullmap.sorted.bam
check_file $SAMPLE_ID.fullmap.sorted.bam.bai

samtools view -b -h $SAMPLE_ID.fullmap.sorted.bam "chrM" > $SAMPLE_ID.fullmap.chrM.bam
check_file $SAMPLE_ID.fullmap.chrM.bam
samtools index $SAMPLE_ID.fullmap.chrM.bam
check_file $SAMPLE_ID.fullmap.chrM.bam.bai

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

cat slurm-$SLURM_JOB_ID.out | mail -s "[$SLURM_JOB_NAME] $SAMPLE_ID $SLURM_JOB_ID" marc.ferre@univ-angers.fr
echo
echo "Sended by email"