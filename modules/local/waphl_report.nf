process MAKE_REPORT {
    container 'docker pull jdj0303/waphl-mycosnp-report:1.0'

    input:
    tuple path(qc_report), path(fasttree), path(rapidnj), path(quicksnp), path(tree_files), path(snp_matrix), path(snpeff_report)

    output:
    path "waphl-mycosnp-report.pdf"

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd')"
    """
}