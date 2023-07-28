process MAKE_REPORT {
    container 'jdj0303/waphl-mycosnp-report:1.0'

    input:
    tuple path(qc_report), path(fasttree), path(rapidnj), path(quicksnp), path(snp_matrix), path(snpeff_report)
    path mutliqc_report // this forces the pipeline to wait till the end

    output:
    path "waphl-mycosnp-report.pdf"

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd')"
    """
}