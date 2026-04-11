#! /bin/bash

sudo apt update && sudo apt upgrade -y
sudo apt install nginx -y
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.3.3-amd64.deb
sudo dpkg -i filebeat-9.3.3-amd64.deb
sudo apt install -y curl openssh-server ca-certificates tzdata perl
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash

mv gitlab.rb /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure

