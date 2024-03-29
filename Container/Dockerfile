#
# Container image for CCB's NHANES database project
# Author: Nathan Palmer
# Copyright: Harvard Medical School
#
#
# docker build --progress plain --tag nhanes-workbench -f Container/Dockerfile .
# docker \
#     run \
#         --rm \
#         --name nhanes-workbench \
#         -d \
#         -v LOCAL_DIRECTORY:/HostData \
#         -p 8787:8787 \
#         -p 2200:22 \
#         -p 1433:1433 \
#         -e 'CONTAINER_USER_USERNAME=test' \
#         -e 'CONTAINER_USER_PASSWORD=test' \
#         -e 'ACCEPT_EULA=Y' \
#         -e 'SA_PASSWORD=yourStrong(!)Password' \
#         nhanes-workbench

FROM rocker/binder:4.3.2

#------------------------------------------------------------------------------
# Basic initial system configuration
#------------------------------------------------------------------------------

USER root

# install standard Ubuntu Server packages
RUN yes | unminimize

# we're going to create a non-root user at runtime and give the user sudo
RUN apt-get update && \
	apt-get -y install sudo \
	&& echo "Set disable_coredump false" >> /etc/sudo.conf
	
# set locale info
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
	&& apt-get update && apt-get install -y locales \
	&& locale-gen en_US.utf8 \
	&& /usr/sbin/update-locale LANG=en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV TZ=America/New_York

WORKDIR /tmp

#------------------------------------------------------------------------------
# Install system tools and libraries via apt
#------------------------------------------------------------------------------

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
	&& apt-get install \
		-y \
		ca-certificates \
		curl \
		less \
		libgomp1 \
		libpango-1.0-0 \
		libxt6 \
		libsm6 \
		make \
		texinfo \
		libtiff-dev \
		libpng-dev \
		libicu-dev \
		libpcre3 \
		libpcre3-dev \
		libbz2-dev \
		liblzma-dev \
		gcc \
		g++ \
		openjdk-8-jre \
		openjdk-8-jdk \
		gfortran \
		libreadline-dev \
		libx11-dev \
		libcurl4-openssl-dev \ 
		libssl-dev \
		libxml2-dev \
		wget \
		libtinfo5 \
		openssh-server \
		ssh \
		xterm \
		xauth \
		screen \
		tmux \
		git \
		libgit2-dev \
		nano \
		emacs \
		vim \
		man-db \
		zsh \
		unixodbc \
		unixodbc-dev \
		gnupg \
		krb5-user \
		python3-dev \
		python3 \ 
		python3-pip \
		alien \
		libaio1 \
		pkg-config \ 
		libkrb5-dev \
		unzip \
		cifs-utils \
		lsof \
		libnlopt-dev \
		libopenblas-openmp-dev \
		libpcre2-dev \
		systemd \
		libcairo2-dev \
		libharfbuzz-dev \
		libfribidi-dev \
		cmake \
		qpdf \
	&& rm -rf /var/lib/apt/lists/*

#------------------------------------------------------------------------------
# Configure system tools
#------------------------------------------------------------------------------

# required for ssh and sshd	
RUN mkdir /var/run/sshd	

# enable password authedtication over SSH
RUN sed -i 's!^#PasswordAuthentication yes!PasswordAuthentication yes!' /etc/ssh/sshd_config

# configure X11
RUN sed -i "s/^.*X11Forwarding.*$/X11Forwarding yes/" /etc/ssh/sshd_config \
    && sed -i "s/^.*X11UseLocalhost.*$/X11UseLocalhost no/" /etc/ssh/sshd_config \
    && grep "^X11UseLocalhost" /etc/ssh/sshd_config || echo "X11UseLocalhost no" >> /etc/ssh/sshd_config	

# tell git to use the cache credential helper and set a 1 day-expiration
RUN git config --system credential.helper 'cache --timeout 86400'

#------------------------------------------------------------------------------
# Install SQL Server
#------------------------------------------------------------------------------
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-preview.list | sudo tee /etc/apt/sources.list.d/mssql-server-preview.list
RUN apt-get update
RUN apt-get install -y mssql-server
RUN mkdir -p -m 770 /var/opt/mssql && chgrp -R 0 /var/opt/mssql

#------------------------------------------------------------------------------
# Install and configure database connectivity components
#------------------------------------------------------------------------------
	
# # install FreeTDS driver
# WORKDIR /tmp
# RUN wget ftp://ftp.freetds.org/pub/freetds/stable/freetds-1.1.40.tar.gz
# RUN tar zxvf freetds-1.1.40.tar.gz
# RUN cd freetds-1.1.40 && ./configure --enable-krb5 && make && make install
# RUN rm -r /tmp/freetds*

# # tell unixodbc where to find the FreeTDS driver shared object
# RUN echo '\n\
# [FreeTDS]\n\
# Driver = /usr/local/lib/libtdsodbc.so \n\
# ' >> /etc/odbcinst.ini

# install pyodbc
RUN pip3 install pyodbc

#------------------------------------------------------------------------------
# Install basic R packages
#------------------------------------------------------------------------------

# use the remotes package to manage installations
RUN Rscript -e "install.packages('remotes')"

# configure and install rJava
RUN R CMD javareconf
RUN Rscript -e "remotes::install_cran('rJava', type='source')"

# install devtools
RUN Rscript -e "remotes::install_cran('devtools')"

#----------------------------------------------------------------------------------------------------
# install standard data science and bioinformatics packages
RUN Rscript -e "remotes::install_cran('Rcpp')"
RUN Rscript -e "remotes::install_cran('roxygen2')"
RUN Rscript -e "remotes::install_cran('tidyverse')"
RUN Rscript -e "remotes::install_cran('git2r')"
RUN Rscript -e "remotes::install_cran('getPass')"
RUN Rscript -e "remotes::install_cran('xlsx')"
RUN Rscript -e "remotes::install_cran('data.table')"
RUN Rscript -e "remotes::install_cran('dplyr')"
RUN Rscript -e "remotes::install_cran('forestplot')"
RUN Rscript -e "remotes::install_cran('splines')"
RUN Rscript -e "remotes::install_cran('tidyr')"
RUN Rscript -e "remotes::install_cran('stringr')"
RUN Rscript -e "remotes::install_cran('survival')"
RUN Rscript -e "remotes::install_cran('codetools')"
RUN Rscript -e "remotes::install_cran('glmnet')"
RUN Rscript -e "remotes::install_cran('glmpath')"
RUN Rscript -e "remotes::install_cran('testthat')"
RUN Rscript -e "remotes::install_cran('DBI')"
RUN Rscript -e "remotes::install_cran('odbc')"
RUN Rscript -e "remotes::install_cran('readr')"
RUN Rscript -e "remotes::install_cran('kableExtra')"
RUN Rscript -e "remotes::install_cran('plotROC')"
RUN Rscript -e "remotes::install_cran('sjPlot')"
RUN Rscript -e "remotes::install_cran('survey')"
RUN Rscript -e "remotes::install_cran('mitools')"
RUN Rscript -e "remotes::install_cran('tinytex')"
RUN Rscript -e "remotes::install_cran('bookdown')"
RUN Rscript -e "remotes::install_cran('reshape')"
RUN Rscript -e "remotes::install_cran('lme4')"
RUN Rscript -e "remotes::install_cran('survminer')"
RUN Rscript -e "remotes::install_cran('rvest')"

# # -- vanilla because there is a bug that causes the R intro / preamble text to get pushed into the compiler
# RUN Rscript --vanilla -e "remotes::install_cran('lme4', repos='"$R_REPOSITORY"')"
# RUN Rscript --vanilla -e "remotes::install_cran('survminer', repos='"$R_REPOSITORY"')"

# install R packages for connecting to SQL Server and working with resulting data sets
RUN Rscript -e "devtools::install_github('https://github.com/nathan-palmer/FactToCube.git', ref='v1.0.0')"
RUN Rscript -e "devtools::install_github('https://github.com/nathan-palmer/MsSqlTools.git', ref='v1.0.0')"
RUN Rscript -e "devtools::install_github('https://github.com/nathan-palmer/SqlTools.git', ref='v1.0.0')"

# additional packages for NHANES analyses
RUN Rscript -e "remotes::install_cran('broom')"
RUN Rscript -e "remotes::install_cran('Hmisc')"
RUN Rscript -e "remotes::install_cran('nonnest2')"
RUN Rscript -e "remotes::install_cran('reshape2')"
RUN Rscript -e "remotes::install_cran('jsonlite')"
RUN Rscript -e "remotes::install_cran('viridis')"
RUN Rscript -e "remotes::install_cran('optparse')"

# # need old version of rvest in order for the hack that parses URLs to work in the NHANES download script
# RUN Rscript -e "remove.packages('rvest')"
# RUN Rscript -e "remotes::install_cran('rvest', repos='https://packagemanager.posit.co/cran/__linux__/focal/2021-01-29')"

#install nhanesA and phonto from github in order to have the latest version (CRAN will take a while to update)
RUN Rscript -e "devtools::install_github('ccb-hms/phonto')"
RUN Rscript -e "devtools::install_github('cjendres1/nhanes@97f1850')"

#------------------------------------------------------------------------------
# Download and DB Build Process
#------------------------------------------------------------------------------

# Copy startup script
RUN mkdir /startup
COPY Container/startup.sh /startup/startup.sh
RUN chmod 700 /startup/startup.sh

# Create a mount point for host filesystem data
RUN mkdir /HostData

# Copy the download and demo scripts
RUN mkdir /NHANES
COPY Code/R/download.R /NHANES/download.R
COPY Code/R/excluded_tables.tsv /NHANES/excluded_tables.tsv
COPY Code/R/regressionExample.R /NHANES/regressionExample.R
RUN chmod -R 777 /NHANES

RUN mkdir /NHANES/Data
RUN chmod -R 777 /NHANES/Data

ARG ACCEPT_EULA=Y
ARG SA_PASSWORD=yourStrong(!)Password

# copy the container build tests
COPY Testing/Code/containerBuildTests.R /NHANES/containerBuildTests.R

RUN curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
RUN curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list

RUN apt-get update && \
	ACCEPT_EULA=Y apt-get install -y msodbcsql17

# optional: for bcp and sqlcmd
RUN ACCEPT_EULA=Y apt-get install -y mssql-tools

RUN echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

# run the download and database build
RUN runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr &' \ 
	&& Rscript /NHANES/download.R --container-build=TRUE

# run the ETL process to load variable metadata
COPY Code/R/etlVariableCodebook.R /NHANES/etlVariableCodebook.R
WORKDIR /tmp
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
	&& apt-get install \
		-y \
		python3.9 \
		python3-pip

RUN git clone https://github.com/ccb-hms/NHANES-metadata.git
WORKDIR /tmp/NHANES-metadata

RUN git fetch --tags
RUN git checkout tags/v3.10.0

# install packages, which require newer version of rvest in conflict with the download / build script
RUN Rscript -e "remotes::install_version('DT', repos='https://packagemanager.posit.co/cran/__linux__/focal/2022-11-04', upgrade=TRUE, version='0.26')"

# ------------------------------------------------------------------------------
# Optional: NHANES-metadata Creation Process 
# ------------------------------------------------------------------------------

# RUN python3.9 -m pip install pydantic==1.7
# RUN python3.9 -m pip install pandas==2.0.2
# RUN python3.9 -m pip install Owlready2==0.40
# RUN python3.9 -m pip install text2term==2.3.2

# WORKDIR /tmp/NHANES-metadata/code

# RUN Rscript get_nhanes_metadata.R

# RUN python3.9 generate_ontology_tables.py
# RUN python3.9 generate_ontology_mappings.py
# RUN python3.9 generate_nhanes_mapping_report.py
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ETL Variable Codebooks, Translate Tables
# ------------------------------------------------------------------------------

WORKDIR /tmp/NHANES-metadata

RUN runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr &' \
	&& Rscript /NHANES/etlVariableCodebook.R

# translate the coded responses
COPY Code/Sql/spTranslateTable.sql /NHANES/spTranslateTable.sql
COPY Code/R/stageSprocs.R /NHANES/stageSprocs.R
WORKDIR /NHANES
RUN runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr &' \
	&& Rscript /NHANES/stageSprocs.R

# run the script to translate the raw coded tables
COPY Code/R/translateRawTables.R /NHANES/translateRawTables.R
WORKDIR /NHANES

RUN runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr &' \
	&& Rscript /NHANES/translateRawTables.R

#------------------------------------------------------------------------------
# Final Odds and Ends
#------------------------------------------------------------------------------

# allow modification of these locations so users can install R packages without warnings
RUN chmod -R 777 /usr/local/lib/R/library
RUN chmod -R 777 /usr/local/lib/R/doc/html/packages.html

# Declare which version of the container this is, and make it available inside the container 
ENV EPICONDUCTOR_CONTAINER_VERSION v0.4.1
ENV EPICONDUCTOR_COLLECTION_DATE 2024-02-12

RUN echo "EPICONDUCTOR_CONTAINER_VERSION=$EPICONDUCTOR_CONTAINER_VERSION" >> /usr/local/lib/R/etc/Renviron.site
RUN echo "EPICONDUCTOR_COLLECTION_DATE=$EPICONDUCTOR_COLLECTION_DATE" >> /usr/local/lib/R/etc/Renviron.site

RUN echo "EPICONDUCTOR_CONTAINER_VERSION=$EPICONDUCTOR_CONTAINER_VERSION" >> /etc/environment
RUN echo "EPICONDUCTOR_COLLECTION_DATE=$EPICONDUCTOR_COLLECTION_DATE" >> /etc/environment

RUN runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr &' \
	&& Rscript /NHANES/containerBuildTests.R

CMD ["/startup/startup.sh"]
