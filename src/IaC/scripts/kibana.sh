#!/bin/bash

sudo apt-get update -y

wget https://artifacts.elastic.co/downloads/kibana/kibana-9.2.0-amd64.deb
shasum -a 512 kibana-9.2.0-amd64.deb
sudo dpkg -i kibana-9.2.0-amd64.deb

# Lấy password kibana_system đã được tạo bởi elas.sh
KIBANA_PASS=$(grep "New value:" /home/ubuntu/password_kibana_system.txt | awk '{print $NF}')

sudo tee -a /etc/kibana/kibana.yml <<EOF
server.host: 0.0.0.0
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "${KIBANA_PASS}"
EOF

sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable kibana.service
sudo systemctl start kibana.service
