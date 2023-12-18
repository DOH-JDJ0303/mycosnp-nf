process PRE_MYCOSNP_NEW_SAMPLESHEETS {
    label 'process_low'
    
    container 'ubuntu:jammy'

    input:
    tuple val(samples), val(qc_status), val(taxa), val(subtype)
    path samplesheet

    output:
    path "*-samplesheet.csv", emit: summary

    when:
    task.ext.when == null || task.ext.when

    new_samplesheet = "${taxa.replaceAll(/ /, "-")}-${subtype.replaceAll(/ /, "-")}-samplesheet.csv"
    script:
    """
    echo "sample,fastq_1,fastq_2" > ${new_samplesheet}
    for s in ${samples.join(' ')}
    do
        cat ${samplesheet} | awk -v s="\${s}" -F ',' '\$1 == s {print \$0}' >> ${new_samplesheet}
    done
    """
}
