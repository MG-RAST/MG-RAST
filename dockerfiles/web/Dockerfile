FROM httpd:2.4.12


EXPOSE 80

RUN apt-get update && apt-get install -y \
  git-core \
  make \
  libfreezethaw-perl \
  libhtml-strip-perl \
  libdbi-perl \
  libhtml-template-perl \
  libtemplate-plugin-number-format-perl \
  libdbd-mysql-perl \
  libclass-isa-perl \
  libgd-gd2-perl \
  libwww-perl \
  liblist-moreutils-perl \
  libcache-memcached-perl \
  libstatistics-descriptive-perl \
  libdbd-pg-perl


# v3 website
RUN mkdir -p /sites/ && \
  cd /sites/ && \ 
  git clone -b master https://github.com/MG-RAST/MG-RAST.git && \ 
  cd MG-RASTv4 && \
  make && \
  ln -s /config/Conf.pm /usr/share/perl5/Conf.pm 


RUN mkdir -p /mcs/bio/mg-rast/prod/ && \
  ln -s /sites /mcs/bio/mg-rast/prod/sites


# v4-uploader for v3
RUN cd / && git clone https://github.com/MG-RAST/MG-RASTv4.git && mv /MG-RASTv4/* /sites/MG-RAST/site/CGI/Html/


# metazen
RUN cd /sites/ && git clone https://github.com/MG-RAST/metazen.git && \
  cd metazen && \
  make

# certificates need to be in daemon home directory
RUN ln -s /config/.postgresql/ /usr/sbin/.postgresql

# docker run -t -i --name web -v /home/core/mgrast-config/services/web_v3/:/config -p 80:80 httpd:2.4.12 bash

# Start
#bash -c "/bin/chmod 600 /config/.postgresql/* ; /bin/chown daemon:daemon /config/.postgresql/* ; /usr/local/apache2/bin/apachectl -f /config/httpd.conf -D FOREGROUND"

