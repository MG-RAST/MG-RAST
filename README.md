MG-RAST source code 
===================

This is the repository for the MG-RAST metagenome analysis system.
Take a look at [MG-RAST](http://www.mg-rast.org).

### WARNING
Don't try this at home.

### LICENSE
MG-RAST is made available under a BSD type LICENSE, see the LICENSE
file for details.

### Please note: The MG-RAST team is dedicated to supporting the
server at http://www.mg-rast.org, we are not resourced to help
with local installations. So as much as we'd like to we can't help
with local installations of this software.

### REQUIREMENTS 

Hardware 

MG-RAST is a pipeline, an archive, a complex
web interface and several other tools. The entire systems was designed
for a Linux/Unix system. We run it on a dedicated small cluster for
the server infrastructure and heavily utilize CLOUD computing
resources.

Systems-Software

1. MySQL
2. Cassandra
3. Perl
4. Python
5. R
6. Apache
7. NGINX

For the bioinformatics software and databases used in MG-RAST please see our manual:
ftp://ftp.mg-rast.org/manual.pdf


### INSTRUCTIONS 
type make

### API server

Build image and push to dockerhub:
```bash

git clone https://github.com/MG-RAST/MG-RAST.git
cd MG-RAST
docker build --build-arg GIT_DESCRIBE=$(git describe --tags) -t mgrast/api-server:dev .

docker push mgrast/api-server:dev

```

Get config: (private mcs git repo, for details see fleet unit)
```bash
if cd /home/core/mgrast-config; then git pull; else cd /home/core/ ; git clone git@git.mcs.anl.gov:mgrast-config.git ; fi
```

Download data
```bash
docker run -t -i --name api -v /media/ephemeral/api-server-data:/m5nr mgrast/api /MG-RAST/bin/download_m5nr_blast.sh
docker rm api
```

Start container:
```bash
docker run -t -i --name api  -v /home/core/mgrast-config/services/api-server:/api-server-conf -v /media/ephemeral/api-server-data:/m5nr -p 80:80 mgrast/api-server /usr/local/apache2/bin/httpd -DFOREGROUND -f /MG-RAST/conf/httpd.conf
```

