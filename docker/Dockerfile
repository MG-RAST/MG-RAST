FROM httpd:2.4.12

RUN apt-get update && apt-get install -y \
  git-core \
  liburi-perl \
  libwww-perl 


RUN mkdir -p /var/log/httpd/api.metagenomics/ && \
  cd / && \
  git clone -b api https://github.com/MG-RAST/MG-RAST.git && \
  cd /MG-RAST && \
  make


#RUN apt-get install -y PIPELINE_DEPENDENCIES HERE <------------------

RUN cd / && git clone https://github.com/MG-RAST/pipeline.git

RUN mkdir -p /sites/1/ && \
  cd /sites/1/ && \
  ln -s /MG-RAST/

# Configuration in mounted directory
RUN cd /MG-RAST/conf && ln -s /api-server/Conf.pm




# Execute:
# /usr/local/apache2/bin/httpd -DFOREGROUND -f /MG-RAST/conf/httpd.conf