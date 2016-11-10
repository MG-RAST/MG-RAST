# MG-RAST API

FROM mgrast/api-base

RUN mkdir -p /MG-RAST /var/log/httpd/api.metagenomics
COPY . /MG-RAST
RUN cd /MG-RAST && \
  make && \
  make api-doc && \
  cp -rv src/MGRAST/bin/* bin/. && \
  cp -rv src/MGRAST/pylib site/lib/. && \
  cd site/CGI && \
  rm -fv metagenomics.cgi upload.cgi m5nr.cgi m5nr_rest.cgi

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
