#!/bin/bash
# This script runs the sex-prediction-from-RNASeq analysis
# Author's Name Bill Amadio 2019

set -e
set -o pipefail

# This script should always run as if it were being called from
# the directory it lives in.

script_directory="$(perl -e 'use File::Basename;
  use Cwd "abs_path";
  print dirname(abs_path(@ARGV[0]));' -- "$0")"
cd "$script_directory" || exit

#--------USER-SPECIFIED ARGUMENTS

# output directory of script 01, input directory of scripts 02 and 03
PROCESSED=processed_data

# outtput directory of script 02, input directory of script 03
MODELS=models

# output directory of script 03
RESULTS=results

# argument for script 01 processing and script 02 and 03 input file specification
SEED=36354

# argument for script 01 output file specification and script 02 and 03 input and output file specification
FILENAME_LEAD=kallisto_stranded

# argument for script 02 processing and script 03 input file specification
TRANSCRIPT_TAIL_PERCENT=0.25

# argument for script 01 processing
TRAIN_PERCENT=0.7

#--------END USER-SPECIFIED ARGUMENTS

# output files for script 01, input files for script 02
# the training expression set and the labels
TRAIN_EXPRESSION_FILE_NAME=${FILENAME_LEAD}_${SEED}_train_expression.RDS
TRAIN_TARGETS_FILE_NAME=${FILENAME_LEAD}_${SEED}_train_targets.tsv

# output files for script 01, input files for script 03
# the test expression set and the labels
TEST_EXPRESSION_FILE_NAME=${FILENAME_LEAD}_${SEED}_test_expression.RDS
TEST_TARGETS_FILE_NAME=${FILENAME_LEAD}_${SEED}_test_targets.tsv

# output file for script 01
FULL_TARGETS_FILE_NAME=${FILENAME_LEAD}_${SEED}_full_targets.tsv

# the first step is to split the data into a training and test set
Rscript --vanilla 01-clean_split_data.R \
  --expression ../../data/pbta-gene-expression-kallisto.stranded.rds \
  --metadata ../../data/pbta-histologies.tsv \
  --output_directory $PROCESSED \
  --train_expression_file_name $TRAIN_EXPRESSION_FILE_NAME \
  --test_expression_file_name $TEST_EXPRESSION_FILE_NAME \
  --train_targets_file_name $TRAIN_TARGETS_FILE_NAME  \
  --test_targets_file_name $TEST_TARGETS_FILE_NAME \
  --full_targets_file_name $FULL_TARGETS_FILE_NAME \
  --seed $SEED \
  --train_percent $TRAIN_PERCENT

# argument for script 02 processing
# this specifies what column in the target data frame will be used as labels
# during training
TRAIN_TARGET_COLUMN=reported_gender

# output files for script 02
# re: the elasticnet model
MODEL_OBJECT_FILE_NAME=${FILENAME_LEAD}_${SEED}_${TRANSCRIPT_TAIL_PERCENT}_model_object.RDS
MODEL_TRANSCRIPTS_FILE_NAME=${FILENAME_LEAD}_${SEED}_${TRANSCRIPT_TAIL_PERCENT}_model_transcripts.RDS
MODEL_COEFS_FILE_NAME=${FILENAME_LEAD}_${SEED}_${TRANSCRIPT_TAIL_PERCENT}_model_coefs.tsv

# elastic net model training
Rscript --vanilla 02-train_elasticnet.R \
 --train_expression_file_name ${PROCESSED}/$TRAIN_EXPRESSION_FILE_NAME \
 --train_targets_file_name ${PROCESSED}/$TRAIN_TARGETS_FILE_NAME \
 --output_directory $MODELS \
 --model_object_file_name $MODEL_OBJECT_FILE_NAME \
 --model_transcripts_file_name $MODEL_TRANSCRIPTS_FILE_NAME \
 --model_coefs_file_name $MODEL_COEFS_FILE_NAME \
 --train_target_column $TRAIN_TARGET_COLUMN \
 --transcript_tail_percent $TRANSCRIPT_TAIL_PERCENT

# if there is a test set, e.g., the entire dataset was not used for training
if [ ! $TRAIN_PERCENT == 1 ]; then

  # the same filenames are used for evaluating predictions of reported_gender
  # and germline_sex_estimate
  RESULTS_FILENAME_LEAD=${FILENAME_LEAD}_${SEED}_${TRANSCRIPT_TAIL_PERCENT}
  CM_SET_FILE=${RESULTS_FILENAME_LEAD}_prediction_details.tsv
  CM_SET=${RESULTS_FILENAME_LEAD}_confusion_matrix.RDS
  SUMMARY_FILE=${RESULTS_FILENAME_LEAD}_two_class_summary.RDS

  # we will evaluate the model's performance on both of these columns
  targetColumns=("reported_gender" "germline_sex_estimate")
  for t in ${targetColumns[@]}; do

    # set up results directory for the column being evaluated
    TEST_TARGET_COLUMN=${t}
    RESULTS_OUTPUT_DIRECTORY=${RESULTS}/${TEST_TARGET_COLUMN}

    # model evaluation
    Rscript --vanilla 03-evaluate_model.R \
      --test_expression_file_name ${PROCESSED}/$TEST_EXPRESSION_FILE_NAME \
      --test_targets_file_name ${PROCESSED}/$TEST_TARGETS_FILE_NAME \
      --model_object_file_name ${MODELS}/$MODEL_OBJECT_FILE_NAME \
      --model_transcripts_file_name ${MODELS}/$MODEL_TRANSCRIPTS_FILE_NAME \
      --output_directory $RESULTS_OUTPUT_DIRECTORY \
      --test_target_column $TEST_TARGET_COLUMN \
      --cm_set_file_name $CM_SET_FILE \
      --cm_file_name $CM_SET \
      --summary_file_name $SUMMARY_FILE
  done
fi

