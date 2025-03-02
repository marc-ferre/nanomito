#!/bin/bash
#SBATCH --job-name=wf-demultmt
#SBATCH --cpus-per-task=12
#SBATCH --mem=150G
#SBATCH --time 30
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2025-01-10.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

SAMPLE_ID=${PWD##*/} # Assign directory name to sample id
SAMPLE_ID=${SAMPLE_ID:-/} # Correct for the case where PWD=/

#FASTQ_FILE="$SAMPLE_ID.fastq.gz"
FASTQ_FILE=`find ~+ -type f -name "*$SAMPLE_ID.fastq.gz"`
MAPPING_FILE="$SAMPLE_ID.paf"
DEMULT_PREFIX="$SAMPLE_ID.ont_demult"

MINIMAP2_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.28_x64-linux/minimap2'
REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'
REF_MT_2KB='/scratch/mferre/reference/chrM-mt_2kb.fa'
REF_MT_3KB='/scratch/mferre/reference/chrM-mt_3kb.fa'
REF_MT_10KB='/scratch/mferre/reference/chrM-mt_10kb.fa'

ONT_DEMULT_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/ont_demult/target/release/ont_demult'
CUT_FILE='/scratch/mferre/reference/cut.txt'

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
echo "Input file: $FASTQ_FILE"
echo "Date: `date`"

echo
echo '******************************'
echo '* Mapping Standard Reference *'
echo '******************************'

echo "Minimap2 version: `$MINIMAP2_BIN --version`"
check_file $FASTQ_FILE

$MINIMAP2_BIN -x map-ont -t 10 $REF_WHOLE $FASTQ_FILE > $MAPPING_FILE

echo
echo '******************'
echo '* Demultiplexing *'
echo '******************'
echo "`$ONT_DEMULT_BIN --version`"

demult () {

	# Read selection strategy (start, both, either ,xor)
	SELECT=$1
	
	echo
	echo '|'
	echo "| $SELECT"
	echo '|'
	
	mkdir select-$SELECT
	check_dir select-$SELECT
	cd select-$SELECT

	check_file ../$MAPPING_FILE
	
	$ONT_DEMULT_BIN --select $SELECT \
		--loglevel info \
		--mapq-threshold 10 \
		--max-distance 100 \
		--max-unmatched 200 \
		--margin 10 \
		--cut-file $CUT_FILE \
		--fastq $FASTQ_FILE \
		--prefix ${DEMULT_PREFIX} \
		--matched-only \
		--compress \
		../$MAPPING_FILE
	check_file ${DEMULT_PREFIX}_res.txt.gz

	TOTAL_COUNT=$((`zcat ${DEMULT_PREFIX}_res.txt.gz | wc -l` - 1))
	
	zcat ${DEMULT_PREFIX}_res.txt.gz | head -1 > ${DEMULT_PREFIX}_res.match_chrM.txt
	zcat ${DEMULT_PREFIX}_res.txt.gz | grep -P 'chrM\t' >> ${DEMULT_PREFIX}_res.match_chrM.txt
	MATCH_CHRM=$((`cat ${DEMULT_PREFIX}_res.match_chrM.txt | wc -l` - 1))

	zcat ${DEMULT_PREFIX}_res.txt.gz | head -1 > ${DEMULT_PREFIX}_res.matched.txt
	zcat ${DEMULT_PREFIX}_res.txt.gz | grep -P 'Matched\tmt_' >> ${DEMULT_PREFIX}_res.matched.txt
	MATCHED=$((`cat ${DEMULT_PREFIX}_res.matched.txt | wc -l` - 1))

	echo "=> Reads aligned to reference: $TOTAL_COUNT"
	echo "==> Reads matching chrM: $MATCH_CHRM"
	echo "===> Reads matching $SELECT strands: $MATCHED"
	
	$MINIMAP2_BIN -ax map-ont $REF_MT_2KB ${DEMULT_PREFIX}_mt_2kb.fastq.gz > alignment_mt_2kb.sam
	$MINIMAP2_BIN -ax map-ont $REF_MT_3KB ${DEMULT_PREFIX}_mt_3kb.fastq.gz > alignment_mt_3kb.sam
	$MINIMAP2_BIN -ax map-ont $REF_MT_10KB ${DEMULT_PREFIX}_mt_10kb.fastq.gz > alignment_mt_10kb.sam

	. /local/env/envsamtools-1.15.sh
	samtools view -b alignment_mt_2kb.sam > alignment_mt_2kb.bam
	samtools view -b alignment_mt_3kb.sam > alignment_mt_3kb.bam
	samtools view -b alignment_mt_10kb.sam > alignment_mt_10kb.bam
	rm *.sam

	samtools merge $SAMPLE_ID.bam alignment_mt_2kb.bam alignment_mt_3kb.bam alignment_mt_10kb.bam
	check_file $SAMPLE_ID.bam
	samtools sort $SAMPLE_ID.bam -o $SAMPLE_ID.sorted.bam
	samtools index $SAMPLE_ID.sorted.bam
	check_file $SAMPLE_ID.sorted.bam
	check_file $SAMPLE_ID.sorted.bam.bai
	
	cd ..
}

demult both
# demult start
# demult either

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=`date +%s`
RUNTIME=$(echo "$END - $START")
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
echo "Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"
