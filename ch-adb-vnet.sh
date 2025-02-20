#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-c private subnet name"
        echo "-p public subnet name"
        echo "-v virtual network resource id"
        echo "-w workspace resource id"
        echo "-s subscription id"
        echo "-x Azure CLI login (optional)"
        exit
}

optstring=":hs:w:v:p:c:x"

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
      az account set --subscription ${subscription}
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

ws=`curl --location --globoff --request GET 'https://eastus2euap.management.azure.com/'${workSpaceResourceID}'?api-version=2025-02-01-preview' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '${bearerToken}`

MRGnameID=`echo $ws | jq .properties.managedResourceGroupId  | sed 's/\"//g'`
location=`echo $ws | jq .location  | sed 's/\"//g'`
enableNPIP=`echo $ws | jq .properties.parameters.enableNoPublicIp.value  | sed 's/\"//g'`

echo '{
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
        }' | jq



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

