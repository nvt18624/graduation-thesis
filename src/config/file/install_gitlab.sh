#! /bin/bash

sudo apt update && sudo apt upgrade -y
sudo apt install -y curl openssh-server ca-certificates tzdata perl
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash

mv gitlab.rb /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure

## check connect to server ad
# sudo gitlab-rake gitlab:ldap:check