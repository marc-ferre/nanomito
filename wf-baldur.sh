#!/bin/zsh
VERSION='2025-03-09.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

PREFIX=${PWD##*/}
PREFIX=${PREFIX:-/}

BALDUR_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/baldur/target/release/baldur'

echo "Workflow: wf-baldur v.$VERSION by $AUTHOR"
echo "Prefix: $PREFIX"
echo "Working directory: `pwd`"
echo "Date: `date`"
START=`date +%s`

$BALDUR_BIN \
	--mapq-threshold 20 \
	--qual-threshold 10 \
	--max-qual 30 \
	--max-indel-qual 20 \
	--homopolymer-limit 4 \
	--reference /Users/marcferre/Documents/Recherche/Projets/Nanomito/Test/reference/chrM.fa \
	--adjust 5 \
	--view \
	--output-deletions \
	--output-prefix ${PREFIX}.baldur \
	--sample ${PREFIX} \
	${PREFIX}.chrM.sup,5mC_5hmC,6mA.bam
	
echo ">>> Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"