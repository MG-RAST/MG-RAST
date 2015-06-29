# MG-RAST v3 website

FROM httpd:2.4.12

EXPOSE 80

RUN apt-get update && apt-get install -y \
  git-core \
  libpq-dev \
  make \
  perl-modules \
  liburi-perl \
  libwww-perl \
  libfreezethaw-perl \
  libhtml-strip-perl \
  libdbi-perl \
  libdbd-mysql-perl \
  libdbd-pg-perl \
  libhtml-template-perl \
  libtemplate-plugin-number-format-perl \
  libclass-isa-perl \
  libgd-gd2-perl \
  liblist-moreutils-perl \
  libcache-memcached-perl \
  libstatistics-descriptive-perl \
  libcaptcha-recaptcha-perl \
  libxml-simple-perl \
  libdatetime-perl

# v3 website
RUN cd / && \ 
  git clone -b master https://github.com/MG-RAST/MG-RAST.git && \ 
  cd MG-RAST && \
  make && \
  ln -s /config/Conf.pm /MG-RAST/conf/Conf.pm

# v4-uploader for v3
RUN cd / && git clone https://github.com/MG-RAST/MG-RASTv4.git && mv /MG-RASTv4/* /MG-RAST/site/CGI/Html/

# pipeline dependencies
RUN apt-get install -y python-dev python-pip
RUN pip install gspread xlrd openpyxl lepl
RUN cd / && git clone https://github.com/MG-RAST/pipeline.git

# 3rd party dependencies
RUN mkdir -p /tools && \
  apt-get install -y gcc wget r-base
RUN cd /tools && \
  wget circos.ca/distribution/circos-0.67-7.tgz && \
  tar zxvf circos-0.67-7.tgz && \
  rm -f circos-0.67-7.tgz
RUN cd /tools && \
  git clone https://github.com/wltrimbl/FGS.git FragGeneScan && \
  cd FragGeneScan && \
  make clean && \
  make fgs

# metazen
RUN cd / && \
  git clone https://github.com/MG-RAST/metazen.git && \
  cd metazen && \
  make

# certificates need to be in daemon home directory
RUN ln -s /config/postgresql/ /usr/sbin/.postgresql

# Start
#bash -c "/bin/chmod 600 /config/postgresql/* ; /bin/chown daemon:daemon /config/postgresql/* ; /usr/local/apache2/bin/apachectl -f /config/httpd.conf -D FOREGROUND"

