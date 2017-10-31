#!/bin/bash
trap "echo fail to run script;exit 1" ERR
apt-get update
apt-get install -y zip
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
apt-get install -y nodejs

echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | \
sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 417A0893
sudo apt-get install apt-transport-https
sudo apt-get update && sudo apt-get install azure-cli

apt-get install -y git
rm meta-azure-service-broker -rf
git clone https://github.com/Azure/meta-azure-service-broker
sed -i 's/info/debug/' meta-azure-service-broker/winston.json
az login --service-principal --tenant REPLACE_WITH_TENANTID --username REPLACE_WITH_CLIENTID --password REPLACE_WITH_CLIENTSECRET
export resourcegroupname="REPLACE_WITH_RESOURCEGROUPNAME"
export location="REPLACE_WITH_LOCATION"
export servername="REPLACE_WITH_SERVERNAME"
export adminlogin=ServerAdmin
export password=p@ssw0rdUser@123
export startip="0.0.0.0"
export endip="255.255.255.255"
export databasename=mySampleDatabase
az group create --name $resourcegroupname --location $location
az sql server create --name $servername --resource-group $resourcegroupname --location $location --admin-user $adminlogin --admin-password $password
az sql db create --resource-group $resourcegroupname --server $servername --name $databasename --sample-name AdventureWorksLT --service-objective S0
az sql server firewall-rule create --resource-group $resourcegroupname --server $servername -n AllowYourIp --start-ip-address $startip --end-ip-address $endip

