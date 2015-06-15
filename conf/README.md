

API server
----------


Build image:
```bash
export TAG=`date +"%Y%m%d.%H%M"`
docker build --force-rm --no-cache --rm -t  mgrast/api:${TAG}  https://raw.githubusercontent.com/MG-RAST/MG-RAST/api/docker/Dockerfile
```

Get config: (private mcs git repo)
```bash
if cd /home/core/mgrast-config; then git pull; else cd /home/core/ ; git clone git@git.mcs.anl.gov:mgrast-config.git ; fi
```


Start container:
```bash
docker run -t -i --name api -v ~/mgrast-config/services/api-server:/api-server-conf -v /media/ephemeral/api-server-data:/api-server-data -p 80:80 mgrast/api:${TAG} /usr/local/apache2/bin/httpd -DFOREGROUND -f /MG-RAST/conf/httpd.conf
```