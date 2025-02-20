#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-c private subnet name (optional: existing subnet name is the default)"
        echo "-p public subnet name (optional: existing subnet name is the default)"
        echo "-v virtual network resource id (optional: existing vnet id is the default)"
        echo "-w workspace resource id (required)"
        echo "-s subscription id (required)"
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

if [[ ! $VnetNameID ]]
then 
    VnetNameID=`echo $ws | jq .properties.parameters.customVirtualNetworkId.value  | sed 's/\"//g'`
    if [ ! $VnetNameID ] || [ $VnetNameID == "null" ]
    then 
        echo "This workspace is not vnet injected, missing Vnet Resource ID is required"
        exit
    fi
fi

if [[ ! $pubSubnet ]]
then 
    pubSubnet=`echo $ws | jq .properties.parameters.customPublicSubnetName.value  | sed 's/\"//g'`
    if [ ! $pubSubnet ] || [ $pubSubnet == "null" ]
    then 
        echo "This workspace is not vnet injected, missing public subnet name is required"
        exit
    fi
fi

if [[ ! $prvSubnet ]]
then 
    prvSubnet=`echo $ws | jq .properties.parameters.customPrivateSubnetName.value  | sed 's/\"//g'`
    if [ ! $prvSubnet ] || [ $prvSubnet == "null" ]
    then 
        echo "This workspace is not vnet injected, missing private subnet name is required"
        exit
    fi
fi

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

echo "Please review the updated vnet and subnet settings (above)"
read -p "Are you sure? (Y or N): " -n 1 -r
echo    # new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # update tthe Workspace 
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
fi
