#!/bin/bash
#SBATCH --job-name=wf-nanomito
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2024-03-13.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

SAMPLE_ID=${PWD##*/} # Assign directory name to sample id
SAMPLE_ID=${SAMPLE_ID:-/} # Correct for the case where PWD=/

DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.3-linux-x64/bin/dorado'
POD5_DIR=`find . -type d -name 'pod5_pass'`
MODIFIED_BASES='5mC_5hmC'

MINIMAP2_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.26_x64-linux/minimap2'
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
   		echo "[OK] File $1 created"
   	else
		echo "[ERROR] File $1 not created"
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

echo "Workflow: Nanomito v.$VERSION by $AUTHOR"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Input data directory: $POD5_DIR"
echo "Modified bases: $MODIFIED_BASES"
echo "Date: `date`"

echo
echo '***************'
echo '* Basecalling *'
echo '***************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

echo "Dorado version: `$DORADO_BIN --version`"
check_dir $POD5_DIR

$DORADO_BIN basecaller sup $POD5_DIR --kit-name <barcode-kit-name> --modified-bases $MODIFIED_BASES > calls.bam
check_file calls.bam 

. /local/env/envsamtools-1.15.sh
samtools fastq calls.bam > calls.fastq
gzip calls.fastq
check_file calls.fastq.gz

echo
echo '******************************'
echo '* Mapping Standard Reference *'
echo '******************************'
echo "Minimap2 version: `$MINIMAP2_BIN --version`"

$MINIMAP2_BIN -x map-ont $REF_WHOLE calls.fastq.gz > approx-mapping.paf
check_file approx-mapping.paf

echo
echo '******************'
echo '* Demultiplexing *'
echo '******************'
echo "`$ONT_DEMULT_BIN --version`"

$ONT_DEMULT_BIN --select both \
	--mapq-threshold 10 \
	--max-distance 100 \
	--max-unmatched 200 \
	--margin 10 \
	--cut-file $CUT_FILE \
	--fastq calls.fastq.gz \
	--prefix ont_demult \
	--matched-only \
	--compress \
	approx-mapping.paf
check_file ont_demult_res.txt.gz

TOTAL_COUNT=$((`zcat ont_demult_res.txt.gz | wc -l` - 1))

MATCH_CHRM=`zcat ont_demult_res.txt.gz | grep -P 'chrM\t' | wc -l`
zcat ont_demult_res.txt.gz | head -1 > ont_demult_res.match_chrM.txt
zcat ont_demult_res.txt.gz | grep -P 'chrM\t' >> ont_demult_res.match_chrM.txt

MATCH_EITHER=`zcat ont_demult_res.txt.gz | grep -P '\tMatch' | wc -l`
zcat ont_demult_res.txt.gz | head -1 > ont_demult_res.match_either.txt
zcat ont_demult_res.txt.gz | grep -P '\tMatch' >> ont_demult_res.match_either.txt

MATCH_BOTH=`zcat ont_demult_res.txt.gz | grep -P 'Matched\tmt_' | wc -l`
zcat ont_demult_res.txt.gz | head -1 > ont_demult_res.match_both.txt
zcat ont_demult_res.txt.gz | grep -P 'Matched\tmt_' >> ont_demult_res.match_both.txt

echo "=> Reads aligned to reference: $TOTAL_COUNT"
echo "==> Reads matching chrM: $MATCH_CHRM"
echo "===> Reads matching EITHER strands: $MATCH_EITHER"
echo "====> Reads matching BOTH strands: $MATCH_BOTH"

echo
echo '*****************************'
echo '* Mapping Custom References *'
echo '*****************************'
	
$MINIMAP2_BIN -ax map-ont $REF_MT_2KB ont_demult_mt_2kb.fastq.gz > alignment_mt_2kb.sam
$MINIMAP2_BIN -ax map-ont $REF_MT_3KB ont_demult_mt_3kb.fastq.gz > alignment_mt_3kb.sam
$MINIMAP2_BIN -ax map-ont $REF_MT_10KB ont_demult_mt_10kb.fastq.gz > alignment_mt_10kb.sam

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

cat slurm-$SLURM_JOB_ID.out | mail -s "[$SLURM_JOB_NAME] $SAMPLE_ID $SLURM_JOB_ID" marc.ferre@univ-angers.fr
echo
echo "Sended by email"