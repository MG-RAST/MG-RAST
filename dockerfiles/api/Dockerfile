# MG-RAST API

FROM httpd:2.4

# MG-RAST dependencies
RUN apt-get update && apt-get install -y \
  libpq-dev \
  make \
  curl \
  ncbi-blast+ \
  perl-modules \
  liburi-perl \
  liburi-encode-perl \
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

RUN mkdir -p /MG-RAST /var/log/httpd/api.metagenomics
COPY . /MG-RAST
RUN cd /MG-RAST && \
  make && \
  make api-doc && \
  cp -rv src/MGRAST/bin/* bin/. && \
  cp -rv src/MGRAST/pylib site/lib/. && \
  cd site/CGI && \
  rm -fv metagenomics.cgi linkin.cgi m5nr.cgi m5nr_rest.cgi

# R dependencies
RUN apt-get install -y r-base r-cran-nlme r-cran-ecodist r-cran-rcolorbrewer r-cran-xml && \
  echo 'install.packages("matlab", repos = "http://cran.wustl.edu")' | R --no-save && \
  echo 'source("http://bioconductor.org/biocLite.R"); biocLite("pcaMethods"); biocLite("preprocessCore"); biocLite("DESeq")' | R --no-save

# python dependencies
RUN apt-get install -y python-dev python-pip && \
  pip install \
  openpyxl==1.8.6 \
  gspread \
  xlrd \
  lepl \
  cassandra-driver

ENV PERL_MM_USE_DEFAULT 1
RUN cpan Inline::Python

RUN mkdir -p /sites/1/ && \
  cd /sites/1/ && \
  ln -s /MG-RAST/

# Configuration in mounted directory
RUN cd /MG-RAST/conf && ln -s /api-server-conf/Conf.pm

# certificates need to be in daemon home directory
RUN ln -s /api-server-conf/postgresql/ /usr/sbin/.postgresql

# m5nr blast files in mounted dir
RUN mkdir -p /m5nr

# Execute:
# /etc/init.d/postfix start
# /usr/local/apache2/bin/httpd -DFOREGROUND -f /api-server-conf/httpd.conf
