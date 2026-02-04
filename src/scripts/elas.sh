#!/bin/bash

# Update & Upgrade
sudo apt-get update && sudo apt-get upgrade -y

# Download Elasticsearch
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-9.2.0-amd64.deb
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-9.2.0-amd64.deb.sha512

# Verify Checksum
shasum -a 512 -c elasticsearch-9.2.0-amd64.deb.sha512

# Install Elasticsearch
sudo dpkg -i elasticsearch-9.2.0-amd64.deb

ES_CONF="/etc/elasticsearch/elasticsearch.yml"

# Disable SSL
sudo sed -i '/xpack\.security\.http\.ssl:/,/enabled:/ {
    s/enabled:[[:space:]]*true/enabled: false/
}' $ES_CONF

# Add config only if not already present
sudo grep -qxF "cluster.name: thien" "$ES_CONF" || echo "cluster.name: thien" | sudo tee -a "$ES_CONF"
sudo grep -qxF "network.host: 0.0.0.0" "$ES_CONF" || echo "network.host: 0.0.0.0" | sudo tee -a "$ES_CONF"
sudo grep -qxF "transport.host: 0.0.0.0" "$ES_CONF" || echo "transport.host: 0.0.0.0" | sudo tee -a "$ES_CONF"

# Fix file ownership just in case
sudo chown root:elasticsearch "$ES_CONF"
sudo chmod 640 "$ES_CONF"

# Reload & Start Elasticsearch
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch.service
sudo systemctl start elasticsearch.service
sudo systemctl restart elasticsearch.service


# Generate tokens + password
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana | sudo tee /home/ubuntu/token-kibana.txt
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic >> /home/ubuntu/elastic_password.txt
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system >> /home/ubuntu/password_kibana_system.txt

