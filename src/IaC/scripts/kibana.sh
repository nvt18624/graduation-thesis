#! /bin/bash

sudo apt-get update -y

wget https://artifacts.elastic.co/downloads/kibana/kibana-9.2.0-amd64.deb
shasum -a 512 kibana-9.2.0-amd64.deb
sudo dpkg -i kibana-9.2.0-amd64.deb
echo "server.host: 0.0.0.0" | sudo tee -a /etc/kibana/kibana.yml

sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable kibana.service
sudo systemctl start kibana.service


