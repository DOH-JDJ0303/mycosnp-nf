process WAPHL_REPORT {
    container 'jdj0303/waphl-mycosnp-report:1.0.2'
    stageInMode 'copy'

    input:
    path qc_report
    tuple val(meta), path(tsv)
    path fasttree
    path rapidnj
    path snpeff
    path waphl_report_files

    output:
    path "*_waphl-mycosnp-report.*"
    path "*.csv",                   optional: true
    path "*.jpg",                   optional: true

    when:
    task.ext.when == null || task.ext.when

    shell:
    '''
    # create file name with timestamp
    timestamp=$(date +%Y-%m-%d_%T)
    filename="${timestamp//:/.}_waphl-mycosnp-report"

    # move all files into same pwd
    mv waphl-report/* ./

    # render the report without running pandoc - this does not play well
    Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd', run_pandoc=F, output_format='all')"

    # create HTML report - update the html header as needed
    pandoc +RTS -K512m -RTS waphl-mycosnp-report.knit.md \
        --to html4 \
        --from markdown+autolink_bare_uris+tex_math_single_backslash \
        --output ${filename}.html \
        --embed-resources \
        --standalone \
        --variable bs3=TRUE \
        --section-divs \
        --template /usr/local/lib/R/site-library/rmarkdown/rmd/h/default.html \
        --no-highlight \
        --variable highlightjs=1 \
        --variable theme=bootstrap \
        --mathjax \
        --variable 'mathjax-url=https://mathjax.rstudio.com/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' \
        --include-in-header html-header.html

    # create PDF report - update the pdf header as needed
    pandoc +RTS -K512m -RTS waphl-mycosnp-report.knit.md \
        --to latex \
        --from markdown+autolink_bare_uris+tex_math_single_backslash \
        --output ${filename}.tex \
        --embed-resources \
        --standalone \
        --highlight-style tango \
        --pdf-engine pdflatex \
        --variable graphics \
        --variable 'geometry:margin=1in' \
        --include-in-header pdf-header.html

    pdflatex ${filename}.tex
    '''
}
