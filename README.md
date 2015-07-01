MG-RAST source code 
===================

This is the repository for the MG-RAST metagenome analysis system.
Take a look at [MG-RAST](http://metagenomics.anl.gov).

### WARNING
Don't try this at home.

### LICENSE
MG-RAST is made available under a BSD type LICENSE, see the LICENSE
file for details.

### Please note: The MG-RAST team is dedicated to supporting the
server at http://metagenomics.anl.gov, we are not resourced to help
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
2. PostGres 
3. Perl 
4. R 
5. Apache
6. NGINX

For the bioinformatics software and databases used in MG-RAST please see 
[the tools and data entry in our blog](http://blog.metagenomics.anl.gov/tools-and-data-used-in-mg-rast/)



### INSTRUCTIONS 
type make


### web-v3 docker

```bash
export TAG=`date +"%Y%m%d.%H%M"`
docker build --force-rm --no-cache --rm -t  mgrast/v3-web:${TAG} https://raw.githubusercontent.com/MG-RAST/MG-RAST/master/dockerfiles/web/Dockerfile
```

