#!/bin/bash
# C. Savonen
# CCDL for ALSF 2019

# Purpose:Run an consensus analysis of SNV callers

# Set this so the whole loop stops if there is an error
set -e
set -o pipefail

# The sqlite database made from the callers will be called:
dbfile=scratch/testing_snv_db.sqlite

# Designate output file 
consensus_file=analyses/snv-callers/results/consensus/consensus_snv.maf.tsv

# BED and GTF file paths
exon_file=scratch/gencode.v27.primary_assembly.annotation.bed
all_mut_wgs_bed=scratch/intersect_strelka_mutect_WGS.bed
all_mut_wxs_bed=data/WXS.hg38.100bp_padded.bed
coding_wgs_bed=scratch/intersect_exon_lancet_strelka_mutect_WGS.bed
coding_wxs_bed=scratch/intersect_exon_WXS.bed

# Set a default for the VAF filter if none is specified
vaf_cutoff=${OPENPBTA_VAF_CUTOFF:-0}

# Unless told to run the plots, the default is to skip them
# To run plots, set OPENPBTA_PLOTS to 1 or more
run_plots_nb=${OPENPBTA_PLOTS:-0}

################################ Set Up Database ################################
python3 analyses/snv-callers/scripts/01-setup_db.py \
  --db-file $dbfile \
  --strelka-file data/pbta-snv-strelka2.vep.maf.gz \
  --mutect-file data/pbta-snv-mutect2.vep.maf.gz \
  --lancet-file data/pbta-snv-lancet.vep.maf.gz \
  --vardict-file data/pbta-snv-vardict.vep.maf.gz \
  --meta-file data/pbta-histologies.tsv

##################### Merge callers' files into total files ####################
Rscript analyses/snv-callers/scripts/02-merge_callers.R \
  --db_file $dbfile \
  --output_file $consensus_file \
  --vaf_filter $vaf_cutoff \
  --overwrite

########################## Add consensus to db ################################
python3 analyses/snv-callers/scripts/01-setup_db.py \
  --db-file $dbfile \
  --consensus-file $consensus_file

###################### Create intersection BED files ###########################
# Make All mutations BED file
bedtools intersect \
  -a data/WGS.hg38.strelka2.unpadded.bed \
  -b data/WGS.hg38.mutect2.unpadded.bed > $all_mut_wgs_bed

# Convert GTF to BED file for use in bedtools
# Here we are only extracting lines with as a CDS i.e. are coded in protein
gunzip -c data/gencode.v27.primary_assembly.annotation.gtf.gz \
  | awk '$3 ~ /CDS/' \
  | convert2bed --do-not-sort --input=gtf - \
  > $exon_file
  
# Make WGS coding BED file
bedtools intersect \
  -a data/WGS.hg38.strelka2.unpadded.bed \
  -b data/WGS.hg38.mutect2.unpadded.bed \
  data/WGS.hg38.lancet.300bp_padded.bed \
  $exon_file \
  > $coding_wgs_bed

# Make WXS coding BED file
bedtools intersect \
  -a data/WXS.hg38.100bp_padded.bed  \
  -b $exon_file 
  > $coding_wxs_bed

######################### Calculate consensus TMB ##############################
Rscript analyses/snv-callers/scripts/03-calculate_tmb.R \
  --consensus analyses/snv-callers/results/consensus/consensus_snv.maf.tsv \
  --db_file $dbfile \
  --output analyses/snv-callers/results/consensus \
  --metadata data/pbta-histologies.tsv \
  --all_bed_wgs $all_mut_wgs_bed \
  --all_bed_wxs $all_mut_wxs_bed \
  --coding_bed_wgs $coding_wgs_bed \
  --coding_bed_wxs $coding_wxs_bed \
  --overwrite
  
############################# Comparison Plots #################################
if [ "$run_plots_nb" -gt "0" ]
then
 Rscript -e "rmarkdown::render('analyses/snv-callers/compare_snv_callers_plots.Rmd', clean = TRUE)"
fi
