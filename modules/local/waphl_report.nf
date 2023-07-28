process MAKE_REPORT {
    container 'docker pull jdj0303/waphl-mycosnp-report:1.0'

    input:
    path  qc_report,        optional: true
    path  fasttree,         optional: true
    path  rapidnj,          optional: true
    path  quicksnp,         optional: true
    path  tree_files,       optional: true
    path  snp_matrix,       optional: true
    path  snpeff_report,    optional: true
    val   multiqc_version // This forces the pipeline to run this stage last

    output:
    path "waphl-mycosnp-report.pdf"

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd')"
    """
}