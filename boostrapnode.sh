#!/bin/bash

curl -L https://omnitruck.chef.io/install.sh | sudo bash
sudo mkdir /etc/chef/
echo 'chef_server_url "https://manage.chef.io/organizations/loco"

log_level          :info
log_location       STDOUT

validation_client_name "chef-validator"
validation_key         "/etc/chef/validation.pem"
client_key             "/etc/chef/client.pem"'  > /etc/chef/client.rb
echo '{"runlist":["recipe[rasposmc]"]}' > /tmp/runlist.json
chef-client -j /tmp/runlist.json
