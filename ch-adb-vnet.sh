#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-c private subnet name"
        echo "-p public subnet name"
        echo "-v virtual network resource id"
        echo "-w workspace resource id"
        echo "-m managed resource group resource id"
        echo "-l location"
        echo "-i is NPIP enabled (true or false)"
        echo "-s subscription id"
        echo "-x Azure CLI login (optional)"
        exit
}

optstring=":hs:i:w:l:m:v:p:c:x"

if [ $# -eq 0 ] ; then 
  usage
  exit
fi

while getopts ${optstring} arg; do
  case ${arg} in
    h)
      echo "showing usage!"
      usage
      ;;
    w)
      workSpaceResourceID=$OPTARG
      workspaceName=$(basename "$workSpaceResourceID")
      ;;
    s) 
      subscription=$OPTARG
      echo $subscription
      az account set --subscription ${subscription}
      ;;
    l)
      location=$OPTARG
      ;;
    v)
      VnetNameID=$OPTARG
      ;;
    p)
      pubSubnet=$OPTARG
      ;;
    c)
      prvSubnet=$OPTARG
      ;;
    m)
      MRGnameID=$OPTARG
      ;;
    i)
      enableNPIP=$OPTARG
      ;;
    x)
      az login
      ;;
    :)
      echo "$0: Must supply an argument to -$OPTARG." >&2
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 2
      ;;
  esac
done


bearerToken=`az account get-access-token | jq .accessToken | sed 's/\"//g'`
# bearerToken=`az account get-access-token | jq .accessToken | sed 's/^"\|"$//g'`

curl --location --globoff --request PUT 'https://eastus2euap.management.azure.com/'${workSpaceResourceID}'?api-version=2025-02-01-preview' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '${bearerToken} \
--data '{
            "type": "Microsoft.Databricks/workspaces",
            "name": "'${workspaceName}'",
            "location": "'${location}'",
            "sku": {
                "name": "premium"
            },
            "properties": {
                "managedResourceGroupId": "'${MRGnameID}'",
                "parameters": {
                    "customPrivateSubnetName": {
                        "value": "'${pubSubnet}'"
                    },
                    "customPublicSubnetName": {
                        "value": "'${prvSubnet}'"
                    },
                    "customVirtualNetworkId": {
                        "value": "'${VnetNameID}'"
                    },
                    "enableNoPublicIp": {
                        "value": '${enableNPIP}'
                    }
                }
            }
        }'

