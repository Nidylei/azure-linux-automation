#!/bin/bash

export ENVIRONMENT="REPLACE_WITH_ENVIRONMENT"
export CLIENT_ID="REPLACE_WITH_CLIENTID"
export CLIENT_SECRET="REPLACE_WITH_CLIENTSECRET"
export SUBSCRIPTION_ID="REPLACE_WITH_SUBSCRIPTIONID"
export TENANT_ID="REPLACE_WITH_TENANTID"
export SECURITY_USER_NAME="demouser"
export SECURITY_USER_PASSWORD="demopassword"
export AZURE_BROKER_DATABASE_PROVIDER="sqlserver"
export AZURE_BROKER_DATABASE_SERVER=REPLACE_WITH_SERVERNAME.database.windows.net
export adminlogin=ServerAdmin
export password=p@ssw0rdUser@123
export startip="0.0.0.0"
export endip="255.255.255.255"
export databasename=mySampleDatabase
export AZURE_BROKER_DATABASE_USER=$adminlogin
export AZURE_BROKER_DATABASE_PASSWORD=$password
export AZURE_BROKER_DATABASE_NAME=$databasename
export AZURE_SQLDB_ALLOW_TO_CREATE_SQL_SERVER="true"
export AZURE_BROKER_DATABASE_ENCRYPTION_KEY='abcdefghijklmnopqrstuvwxyz123456'
export AZURE_SQLDB_SQL_SERVER_POOL='[
    {
      "resourceGroup":"REPLACE_WITH_RESOURCEGROUPNAME",
      "location": "REPLACE_WITH_LOCATION",
      "sqlServerName": "REPLACE_WITH_SERVERNAME",
     "administratorLogin": "ServerAdmin",
    "administratorLoginPassword": "p@ssw0rdUser@123"
    }
]'
 
#Start test 
cd meta-azure-service-broker/
npm install
echo test start time: `date`
npm test
npm -s run-script integration
echo test end time: `date`