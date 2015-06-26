
# MG-RAST v3 website


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
RUN cd / && \ 
  git clone -b master https://github.com/MG-RAST/MG-RAST.git && \ 
  cd MG-RAST && \
  make && \
  ln -s /config/Conf.pm /usr/share/perl5/Conf.pm 



# v4-uploader for v3
RUN cd / && git clone https://github.com/MG-RAST/MG-RASTv4.git && mv /MG-RASTv4/* /MG-RAST/site/CGI/Html/


# metazen
RUN cd / && git clone https://github.com/MG-RAST/metazen.git && \
  cd metazen && \
  make

# certificates need to be in daemon home directory
RUN ln -s /config/postgresql/ /usr/sbin/.postgresql


# Start
#bash -c "/bin/chmod 600 /config/postgresql/* ; /bin/chown daemon:daemon /config/postgresql/* ; /usr/local/apache2/bin/apachectl -f /config/httpd.conf -D FOREGROUND"

