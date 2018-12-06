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
ftp://ftp.metagenomics.anl.gov/manual.pdf


### INSTRUCTIONS 
type make

### API server

```bash
export TAG=`date +"%Y%m%d.%H%M"`
git clone -b api https://github.com/MG-RAST/MG-RAST.git
cd MG-RAST
docker build -t mgrast/api:${TAG} .
skycore push mgrast/api:${TAG}
```

