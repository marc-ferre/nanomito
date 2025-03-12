. /local/env/envpython-3.9.5.sh
. /local/env/envpython-3.11.9.sh
pip install pod5

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo/bin/rustup update
cd bioapp/

git clone https://github.com/heathsc/ont_demult.git
ls
cd ont_demult/
~/.cargo/bin/cargo build --release
~/.cargo/rustup default stable
~/.cargo/bin/rustup default stable
~/.cargo/bin/cargo build --release
./target/release/ont_demult -V

cd /scratch/mferre/workbench/231009-ker-natif

~/.local/bin/pod5 convert fast5 \
	-t 10 \
	-o pod5/converted.pod5 \
	/scratch/mferre/input/231009-ker-natif/fast5/*.fast5


### https://github.com/nanoporetech/dorado
# /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.4.3-linux-x64/bin/dorado basecaller \
# 	/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.4.3-linux-x64/models/dna_r10.4.1_e8.2_400bps_hac@v4.1.0 \
# 	/scratch/mferre/workbench/231009-ker-natif/converted.pod5 \
# 	> /scratch/mferre/workbench/231009-ker-natif/calls.bam
# . /local/env/envsamtools-1.15.sh
# samtools fastq calls.bam > calls.fastq
# exit
sbatch /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/test/test-bascalling.sh


### https://github.com/lh3/minimap2
# /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.26_x64-linux/minimap2 \
# 	-x map-ont \
# 	/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.mmi \
# 	/scratch/mferre/workbench/231009-ker-natif/calls.fastq \
# 	> /scratch/mferre/workbench/231009-ker-natif/approx-mapping.paf
sbatch /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/test/test-alignment.sh


srun --cpus-per-task=10 --mem=200G --pty bash

### https://github.com/heathsc/ont_demult
/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/ont_demult/target/release/ont_demult \
	--select both \
	--mapq-threshold 10 \
	--max-distance 100 \
	--max-unmatched 200 \
	--margin 10 \
	--cut-file cut.txt \
	--fastq calls.fastq.gz \
	--prefix ont_demult \
	--matched-only \
	--compress \
	approx-mapping.paf

### https://github.com/lh3/minimap2
/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.26_x64-linux/minimap2 \
	-ax map-ont \
	/scratch/mferre/reference/chrM-mt_2kb.fa \
	/scratch/mferre/workbench/231009-ker-natif/ont_demult_mt_2kb.fastq.gz \
	> /scratch/mferre/workbench/231009-ker-natif/alignment_mt_2kb.sam
/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.26_x64-linux/minimap2 \
	-ax map-ont \
	/scratch/mferre/reference/chrM-mt_3kb.fa \
	/scratch/mferre/workbench/231009-ker-natif/ont_demult_mt_3kb.fastq.gz \
	> /scratch/mferre/workbench/231009-ker-natif/alignment_mt_3kb.sam
/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.26_x64-linux/minimap2 \
	-ax map-ont \
	/scratch/mferre/reference/chrM-mt_10kb.fa \
	/scratch/mferre/workbench/231009-ker-natif/ont_demult_mt_10kb.fastq.gz \
	> /scratch/mferre/workbench/231009-ker-natif/alignment_mt_10kb.sam
	
. /local/env/envsamtools-1.15.sh
samtools view -b alignment_mt_2kb.sam > alignment_mt_2kb.bam
samtools view -b alignment_mt_3kb.sam > alignment_mt_3kb.bam
samtools view -b alignment_mt_10kb.sam > alignment_mt_10kb.bam
samtools merge alignments.bam alignment_mt_2kb.bam alignment_mt_3kb.bam alignment_mt_10kb.bam
rm *.sam
samtools sort alignments.bam -o alignments.sorted.bam
samtools index alignments.sorted.bam
exit





### https://github.com/heathsc/baldur
/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/baldur/target/release/baldur \
	-q 20 -Q 10 -M 30 -a 5 -D \
	-T /Users/marcferre/Documents/Recherche/Projets/Nanomito/Test/reference/chrM.fa \
	-n 202306308_LET_E_natif 202306308_LET_E_natif.bam
	
/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/baldur/target/release/baldur \
	--mapq-threshold 20 \
	--qual-threshold 10 \
	--max-qual 30 \
	--reference /Users/marcferre/Documents/Recherche/Projets/Nanomito/Test/reference/chrM.fa \
	--adjust 5 \
	--view \
	--output-deletions \
	--output-prefix baldur \
	--sample 202306308_LET_E_natif \
	202306308_LET_E_natif.bam
	

PREFIX=${PWD##*/}
PREFIX=${PREFIX:-/}
/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/baldur/target/release/baldur \
	--mapq-threshold 20 \
	--qual-threshold 10 \
	--max-qual 30 \
	--reference /Users/marcferre/Documents/Recherche/Projets/Nanomito/Test/reference/chrM.fa \
	--adjust 5 \
	--view \
	--output-deletions \
	--output-prefix ${PREFIX}.baldur \
	--sample ${PREFIX} \
	${PREFIX}.chrM.sup,5mC_5hmC,6mA.bam
	
	


srun --cpus-per-task=10 --mem=200G --pty bash

. /local/env/envpython-3.9.5.sh

~/.local/bin/pod5 filter --help
~/.local/bin/pod5 filter converted.pod5 --output chrM-both.pod5 --ids read_ids.txt --missing-ok

~/.local/bin/pod5 view --list-fields chrM-both.pod5

/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.4.3-linux-x64/bin/dorado basecaller \
	/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.4.3-linux-x64/models/dna_r10.4.1_e8.2_400bps_sup@v4.1.0 \
	chrM-both.pod5 \
	--modified-bases 5mCG_5hmCG \
	--reference /scratch/mferre/reference/chrM-mt_Ref.fa \
	> chrM-both.bam
	
	
	/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.0-linux-x64/bin/dorado basecaller sup,5mC_5hmC BES_N_natif_Pool3.chrM.pod5 --reference /scratch/mferre/reference/chrM.fa > BES_N_natif_Pool3.chrM.5mC_5hmC.bam

/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.0-linux-x64/bin/dorado basecaller sup,6mA BES_N_natif_Pool3.chrM.pod5 --reference /scratch/mferre/reference/chrM.fa > BES_N_natif_Pool3.chrM.6mA.bam

/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.0-linux-x64/bin/dorado basecaller sup,5mCG_5hmCG BES_N_natif_Pool3.chrM.pod5 --reference /scratch/mferre/reference/chrM.fa > BES_N_natif_Pool3.chrM.5mCG_5hmCG.bam




samtools view -h 230717_ker_l_natif_ligation.pass.cram "chrM" > 230717_ker_l_natif_ligation.chrM.sam
samtools view -b -h 230717_ker_l_natif_ligation.pass.cram "chrM" > 230717_ker_l_natif_ligation.chrM.bam



/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/modkit/target/release/modkit pileup 230717_ker_l_natif_ligation.chrM.bam 230717_ker_l_natif_ligation.chrM.bed --log-filepath pileup.log



/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/modkit/target/release/modkit pileup 230717_ker_l_natif_ligation.chrM.bam 230717_ker_l_natif_ligation.chrM.bed --cpg --ref /Users/marcferre/Documents/Recherche/Projets/Nanomito/References/chrM.fa




/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/modkit/target/release/modkit pileup BES_N_natif_Pool5kHz.chrM.5mC_5hmC.sorted.bam BES_N_natif_Pool5kHz.chrM.5mC_5hmC.combine.bed --log-filepath pileup.log --combine-mods --combine-strands




/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.5.3-linux-x64/bin/dorado demux --output-dir calls-demux --no-classify calls.bam



bcftools view -Oz -o pindel.vcf.gz pindel.vcf
htsfile pindel.vcf.gz



