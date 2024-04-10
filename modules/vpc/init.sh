#!/bin/bash
echo -e "GCP_PROJECT_ID=${GCP_PROJECT_ID}\nGCP_TOPIC=${GCP_TOPIC}\nHOST=${HOST}\nDATABASE=${DATABASE}\nPASSWORD=${PASSWORD}\nPGUSER=${PGUSER}\nDBPORT=${DBPORT}" > /tmp/.env
sudo mv -f /tmp/.env /home/prodApp/.env
cd /home/prodApp 
sudo /bin/bash bootstrap.sh
sudo chown -R csye6225:csye6225 /home/prodApp
sudo systemctl restart csye6225