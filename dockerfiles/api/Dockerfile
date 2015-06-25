FROM httpd:2.4.12

# MG-RAST dependencies
RUN apt-get update && apt-get install -y \
  git-core \
  libpq-dev \
  make \
  curl \
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
  liblist-allutils-perl \
  libposix-strptime-perl \
  libuuid-tiny-perl


RUN mkdir -p /var/log/httpd/api.metagenomics/ && \
  cd / && \
  git clone -b api https://github.com/MG-RAST/MG-RAST.git && \
  cd /MG-RAST && \
  make

# pipeline dependencies
RUN apt-get install -y \
  python-dev \
  python-pip \
  libtemplate-perl

RUN pip install gspread xlrd openpyxl lepl

RUN cd / && git clone https://github.com/MG-RAST/pipeline.git


RUN mkdir -p /sites/1/ && \
  cd /sites/1/ && \
  ln -s /MG-RAST/

# Configuration in mounted directory
RUN cd /MG-RAST/conf && ln -s /api-server-conf/Conf.pm && \
  cd /pipeline/conf && ln -s /api-server-conf/PipelineAWE_Conf.pm

# m5nr blast files in mounted dir
RUN mkdir -p /m5nr && \
  ln -s /api-server-data/20100309 /m5nr/20100309 && \
  ln -s /api-server-data/20131215 /m5nr/20131215

# Execute:
# /usr/local/apache2/bin/httpd -DFOREGROUND -f /MG-RAST/conf/httpd.conf
