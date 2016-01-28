# MG-RAST v3 website / API for development

FROM httpd:2.4.12

EXPOSE 80

# core dependencies
RUN apt-get update && apt-get install -y \
  git-core \
  libpq-dev \
  make \
  gcc \
  curl \
  wget \
  zip \
  rsyslog \
  vim

# perl dependencies
RUN apt-get install -y \
  perl-modules \
  liburi-perl \
  libwww-perl \
  libfreezethaw-perl \
  libhtml-strip-perl \
  libjson-perl \
  libdbi-perl \
  libdbd-mysql-perl \
  libdbd-pg-perl \
  libdigest-md5-perl \
  libdigest-md5-file-perl \
  libfile-slurp-perl \
  libhtml-strip-perl \
  libhtml-template-perl \
  libtemplate-plugin-number-format-perl \
  libclass-isa-perl \
  libgd-gd2-perl \
  liblist-moreutils-perl \
  libcache-memcached-perl \
  libdatetime-perl \
  liblist-allutils-perl \
  libposix-strptime-perl \
  libuuid-tiny-perl \
  libstatistics-descriptive-perl \
  libcaptcha-recaptcha-perl \
  libxml-simple-perl \
  libdatetime-perl \
  libmongodb-perl \
  libfreezethaw-perl \
  libtemplate-perl \
  libclass-isa-perl

ENV PERL_MM_USE_DEFAULT 1
RUN cpan Inline::Python

# python dependencies
RUN apt-get install -y python-dev python-pip && \
  pip install openpyxl==1.8.6 && \
  pip install gspread xlrd lepl cassandra-driver

# R dependencies
RUN apt-get install -y r-base r-cran-nlme r-cran-ecodist r-cran-rcolorbrewer r-cran-xml && \
  echo 'install.packages("matlab", repos = "http://cran.wustl.edu")' | R --no-save && \
  echo 'source("http://bioconductor.org/biocLite.R"); biocLite("pcaMethods"); biocLite("preprocessCore"); biocLite("DESeq")' | R --no-save

# dirs to be mounted
RUN mkdir -p /MG-RAST /pipeline /tools /data /m5nr /config /ssl /usr/sbin/.postgresql

# 3rd party dependency: FragGeneScan
RUN cd /tools && \
  git clone https://github.com/wltrimbl/FGS.git FragGeneScan && \
  cd FragGeneScan && \
  make clean && \
  make fgs

# 3rd party dependency: blat
RUN cd /tools && \
  curl -s -O http://hgwdev.cse.ucsc.edu/~kent/exe/linux/blatSuite.zip && \
  unzip blatSuite.zip && \
  rm -f blatSuite.zip

# kegg map data
RUN curl -s "http://shock.metagenomics.anl.gov/node/da268d29-918c-4205-8884-e6f3b175fe58?download" | tar -xvf - -C /data

# setup sendmail
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install postfix && \
  cp /usr/share/postfix/main.cf.debian /etc/postfix/main.cf && \
  postconf -e relayhost=[smtp.mcs.anl.gov] && \
  postconf -e myorigin=mcs.anl.gov

## if need m5nr blast formatted files run this
# /MG-RAST/bin/download_m5nr_blast.sh

## put image from docker into shock
# skycore push -no_etcd -private -shock shock.metagenomics.anl.gov <image name:tag>

## get image from shock into docker
# skycore pull -no_etcd -shock shock.metagenomics.anl.gov <image id or shock node>

## start with this docker command
# docker run --name ${user}-develop \
#   -v /homes/${user}/MG-RAST:/MG-RAST \
#   -v /homes/${user}/pipeline:/pipeline \
#   -v /homes/${user}/mgrast-config/services/develop:/config \
#   -v /homes/${user}/mgrast-config/services/ssl:/ssl \
#   -v /mcs/bio/mg-rast/data/md5nr:/m5nr \
#   -p 80 -p 443 mgrast/develop <image name:tag> \
#   bash -c "/etc/init.d/postfix start; \
#     cp /config/postgresql/* /usr/sbin/.postgresql/; \
#     chmod 600 /usr/sbin/.postgresql/*; \
#     chown daemon:daemon /usr/sbin/.postgresql/*; \
#     /usr/local/apache2/bin/httpd -DFOREGROUND -f /config/httpd.conf"
