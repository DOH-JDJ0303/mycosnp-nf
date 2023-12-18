#!/bin/bash

# pre-mycosnp-stats.sh v1.1.0
# Author: Jared Johnson, jared.johnson@doh.wa.gov

version="v1.0.0"

# inputs
sample=$1
assembly=$2
ref=$3
faqcs_stats=$4
faqcs_qual=$5
min_depth=$6
min_phred=$7
min_gc=$8
max_gc=$9
min_gen_len=${10}
max_gen_len=${11}

#----- HELP & VERSION -----#
# help message
if [ ${sample} == "-h" ] || [ ${sample} == "--help" ] || [ ${sample} == "-help" ]
then
    echo -e "pre-mycosnp-stats.sh [sample_name] [path/to/sample_assembly] [path/to/ref_assembly] [path/to/faqcs/*.stats.txt] [path/to/faqcs/*.for_qual_histogram.txt] [min_depth] [min_phred] [min_gc] [max_gc] [min_gen_len] [max_gen_len]" && exit 0
fi

# version
if [ ${sample} == "-v" ] || [ ${sample} == "--version" ] || [ ${sample} == "-version" ]
then
    echo -e ${version} && exit 0
fi

# decompress the sample and/or reference assemblies - if needed
gzip -d ${assembly} ${ref} || true

#----- ASSEMBLY STATS -----#
# sample assembly length
sample_length=$(cat ${assembly%.gz} | grep -v ">" | tr -d '\n\t\r ' | wc -c)
# reference assembly length
ref_length=$(cat ${ref%.gz} | grep -v ">" | tr -d '\n\t\r ' | wc -c)
# sample % GC
sample_gc_count=$(cat ${assembly%.gz} | grep -v ">" | grep -Eo "G|C" | wc -l)
sample_gc_perc=$(echo -e "${sample_gc_count}\t${sample_length}" | awk '{print 100*$1/$2}')
# reference %GC
ref_gc_count=$(cat ${ref%.gz} | grep -v ">" | grep -Eo "G|C" | wc -l)
ref_gc_perc=$(echo -e "${ref_gc_count}\t${ref_length}" | awk '{print 100*$1/$2}')

#----- READ STATS -----#
# total trimmed reads
trmd_reads=$(cat ${faqcs_stats} | grep 'Reads #:' | sed -n 2p | cut -f 3 -d ' ')
# total trimmed bases
trmd_bases=$(cat ${faqcs_stats} | grep 'Total bases:' | sed -n 2p | cut -f 3 -d ' ')
# average trimmed read Phred score
avg_phred=$(cat ${faqcs_qual} | awk '{print $3,$1*$3}' | awk '{bases += $1} {qual += $2} END {print qual/bases}')
# estimated average depth of coverage
est_depth=$((trmd_bases/ref_length))

#----- COMPILE INTO SUMMARY LINE -----#
line="${trmd_reads},${avg_phred},${est_depth},${sample_length},${ref_length},${sample_gc_perc},${ref_gc_perc}"

#----- DETERMINE QC PASS/FAIL -----#
qc_phred=$(echo ${line} | tr ',' '\t' | awk -v min_phred=${min_phred} '$2 < min_phred {print "Phred > "min_phred";"}')
qc_depth=$(echo ${line} | tr ',' '\t' | awk -v min_depth=${min_depth} '$3 < min_depth {print "Coverage > "min_depth";"}')
qc_gen_len=$(echo ${line} | tr ',' '\t' | awk -v min_gen_len=${min_gen_len} -v max_gen_len=${max_gen_len} '$4 < min_gen_len*1000000 || $4 > max_gen_len*1000000 {print "Genome length out of range ("min_gen_len"-"max_gen_len" Mb);"}')
qc_gc=$(echo ${line} | tr ',' '\t' | awk -v min_gc=${min_gc} -v max_gc=${max_gc} '$6 < min_gc || $6 > max_gc {print "%GC out of range ("min_gc"-"max_gc")"}')

qc_message="${qc_phred}${qc_depth}${qc_gen_len}${qc_gc}"

if [ "${qc_message}" == "" ]
then
    qc_status="PASS,NA"
else
    qc_status="FAIL,${qc_message}"
fi

echo "${sample},${qc_status},${line}"
