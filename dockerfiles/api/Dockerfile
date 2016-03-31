# MG-RAST API

FROM httpd:2.4.12

# MG-RAST dependencies
RUN apt-get update && apt-get install -y \
  git-core \
  libpq-dev \
  make \
  curl \
  vim \
  emacs \
  perl-modules \
  liburi-perl \
  libwww-perl \
  libjson-perl \
  libdbi-perl \
  libdbd-mysql-perl \
  libdbd-pg-perl \
  libdigest-md5-perl \
  libfile-slurp-perl \
  libhtml-strip-perl \
  liblist-moreutils-perl \
  libcache-memcached-perl \
  libhtml-template-perl \
  libdigest-md5-perl \
  libdigest-md5-file-perl \
  libdatetime-perl \
  libdatetime-format-ISO8601-perl \
  liblist-allutils-perl \
  libposix-strptime-perl \
  libuuid-tiny-perl \
  libmongodb-perl \
  libfreezethaw-perl \
  libtemplate-perl \
  libclass-isa-perl

RUN mkdir -p /var/log/httpd/api.metagenomics/ && \
  cd / && \
  git clone -b api https://github.com/MG-RAST/MG-RAST.git && \
  cd /MG-RAST && \
  make && \
  make api-doc && \
  cd site/CGI && \
  rm -fv metagenomics.cgi linkin.cgi m5nr.cgi m5nr_rest.cgi

# R dependencies
RUN apt-get install -y r-base r-cran-nlme r-cran-ecodist r-cran-rcolorbrewer r-cran-xml && \
  echo 'install.packages("matlab", repos = "http://cran.wustl.edu")' | R --no-save && \
  echo 'source("http://bioconductor.org/biocLite.R"); biocLite("pcaMethods"); biocLite("preprocessCore"); biocLite("DESeq")' | R --no-save

# pipeline dependencies
RUN apt-get install -y python-dev python-pip && \
  pip install openpyxl==1.8.6 && \
  pip install gspread xlrd lepl cassandra-driver && \
  cd / && \
  git clone https://github.com/MG-RAST/pipeline.git && \
  cd pipeline && \
  ln -s /MG-RAST/site/CGI/Tmp temp

ENV PERL_MM_USE_DEFAULT 1
RUN cpan Inline::Python

# setup sendmail
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install postfix && \
  cp /usr/share/postfix/main.cf.debian /etc/postfix/main.cf && \
  postconf -e relayhost=[smtp.mcs.anl.gov] && \
  postconf -e myorigin=mcs.anl.gov

RUN mkdir -p /sites/1/ && \
  cd /sites/1/ && \
  ln -s /MG-RAST/

# Configuration in mounted directory
RUN cd /MG-RAST/conf && ln -s /api-server-conf/Conf.pm && \
  cd /pipeline/conf && ln -s /api-server-conf/PipelineAWE_Conf.pm

# certificates need to be in daemon home directory
RUN ln -s /api-server-conf/postgresql/ /usr/sbin/.postgresql

# m5nr blast files in mounted dir
RUN mkdir -p /m5nr && \
  ln -s /api-server-data/20100309 /m5nr/20100309 && \
  ln -s /api-server-data/20131215 /m5nr/20131215

# Execute:
# /etc/init.d/postfix start
# /usr/local/apache2/bin/httpd -DFOREGROUND -f /api-server-conf/httpd.conf
