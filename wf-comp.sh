#!/bin/zsh
VERSION='2024-11-04.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

PREFIX=${PWD##*/}
PREFIX=${PREFIX:-/}

VCF_NANOPORE=( ./*.baldur.vcf.gz )
[[ -e $VCF_NANOPORE ]] || { echo "Matched no files" >&2; exit 1; }
VCF_ILLUMINA=( ./*_Nk_kermit.vcf.gz )
[[ -e $VCF_ILLUMINA ]] || { echo "Matched no files" >&2; exit 1; }

echo "Workflow: wf-comp v.$VERSION by $AUTHOR"
echo "Working directory: `pwd`"
echo "Nanopore VCF: $VCF_NANOPORE"
echo "Illumina VCF: $VCF_ILLUMINA"
echo "Date: `date`"
START=`date +%s`

# Index
tabix -p vcf -f $VCF_NANOPORE
tabix -p vcf -f $VCF_ILLUMINA

bcftools isec $VCF_NANOPORE $VCF_ILLUMINA -p "isec-$PREFIX"
bedtools jaccard -a $VCF_NANOPORE -b $VCF_ILLUMINA > "jaccard-$PREFIX.txt"
	
echo ">>> Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"