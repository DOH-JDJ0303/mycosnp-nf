#!/bin/bash

Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd', run_pandoc=F, output_format='all')"

pandoc +RTS -K512m -RTS waphl-mycosnp-report.knit.md \
    --to html4 \
    --from markdown+autolink_bare_uris+tex_math_single_backslash \
    --output waphl-mycosnp-report.html \
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
    --include-in-header waphl-mycosnp-report-header-html.html


/usr/local/bin/pandoc +RTS -K512m -RTS waphl-mycosnp-report.knit.md \
    --to latex \
    --from markdown+autolink_bare_uris+tex_math_single_backslash \
    --output waphl-mycosnp-report.tex \
    --embed-resources \
    --standalone \
    --highlight-style tango \
    --pdf-engine pdflatex \
    --variable graphics \
    --variable 'geometry:margin=1in' \
    --include-in-header waphl-mycosnp-report-header-pdf.html

pdflatex waphl-mycosnp-report.tex
