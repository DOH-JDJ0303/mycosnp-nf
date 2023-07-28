#!/bin/bash

rmd_path="$(echo ${0%.sh}).Rmd"
cp ${rmd_path} ./
Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd')"
