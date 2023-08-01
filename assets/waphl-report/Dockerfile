# Use a base image with Ubuntu
FROM bioconductor/bioconductor_docker

# required R packages
RUN R -e "install.packages('tidyverse')" # keep this separate because it takes forever
RUN R -e "install.packages(c('ggnewscale', 'phangorn', 'knitr', 'kableExtra', 'BiocManager', 'rmarkdown', 'tinytex'), repos='https://cran.rstudio.com/')"
RUN R -e "tinytex::install_tinytex()"
RUN R -e "BiocManager::install('treeio'); BiocManager::install('ggtree')"

# install pdflatex
RUN sudo apt -y update && sudo apt-get -y install texlive-latex-base && sudo apt-get -y install texlive-fonts-recommended && sudo apt-get -y install texlive-fonts-extra && sudo apt-get -y install texlive-latex-extra


# set up rmarkdown by running it once with no input files - will install needed software
ADD waphl-mycosnp-report.Rmd waphl-mycosnp-report.Rmd
RUN Rscript -e "rmarkdown::render('waphl-mycosnp-report.Rmd',output_format='pdf_document')"
