#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-c private subnet name (optional: existing subnet name is the default)"
        echo "-p public subnet name (optional: existing subnet name is the default)"
        echo "-v virtual network resource id (optional: existing vnet id is the default)"
        echo "-w workspace resource id (required)"
        echo "-a API version (defaults to 2025-02-01-preview)"
        echo "-d debug mode"
        echo "-x Azure CLI login (optional)"
        exit
}

optstring=":hw:v:p:c:a:xbd"

# defaults
apiVersion='2025-02-01-preview'
apiEndpoint='https://management.azure.com'
batchMode=0
debugMode=0
vnetPrepFail=0

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
      subscription=`echo ${workSpaceResourceID} | cut -d '/' -f 3`
      ;;
    v)
      VnetNameID=$OPTARG
      ;;
    a) apiVersion=$OPTARG
      ;;
    p)
      pubSubnet=$OPTARG
      ;;
    c)
      prvSubnet=$OPTARG
      ;;
    b)
      echo "batch"
      batchMode=1
      ;;
    d)
      echo "debug"
      debugMode=1
      set -xv
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


if [[ ! $workSpaceResourceID ]]
then 
    echo "Workspace resource ID is required !"
    exit
fi


if [[ ! $subscription ]]
then 
    echo "Subscription ID is required !"
    exit
fi

az account set --subscription ${subscription}
bearerToken=`az account get-access-token | jq .accessToken | sed 's/\"//g'`
# bearerToken=`az account get-access-token | jq .accessToken | sed 's/^"\|"$//g'`

ws=`curl --location --globoff --request GET ${apiEndpoint}'/'${workSpaceResourceID}'?api-version='${apiVersion} \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '${bearerToken}`

echo $ws | jq

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

checkVnetSubnets () {
    subnetID=${VnetNameID}'/subnets/'$1
    subResource=`az resource show --ids ${subnetID}`
    delegation=`echo $subResource | jq .properties.delegations[0].properties.serviceName | sed 's/\"//g'`
    nsgID=`echo $subResource | jq .properties.networkSecurityGroup.id | sed 's/\"//g'`
    
    if [ $nsgID == 'null' ]
    then
        echo NSG is missing from your $1 subnet
        vnetPrepFail=1
    fi
    if [ ! $delegation == "Microsoft.Databricks/workspaces" ]
    then
        echo delegation is missing from your $1 subnet
        vnetPrepFail=1
    fi
    echo # new line
}

if [[ ! $pubSubnet ]]
then 
    pubSubnet=`echo $ws | jq .properties.parameters.customPublicSubnetName.value  | sed 's/\"//g'`
    if [ ! $pubSubnet ] || [ $pubSubnet == "null" ]
    then 
        echo "This workspace is not vnet injected, missing public subnet name is required"
        exit
    fi
else
    echo checking $pubSubnet preperation
    checkVnetSubnets $pubSubnet
fi


if [[ ! $prvSubnet ]]
then 
    prvSubnet=`echo $ws | jq .properties.parameters.customPrivateSubnetName.value  | sed 's/\"//g'`
    if [ ! $prvSubnet ] || [ $prvSubnet == "null" ]
    then 
        echo "This workspace is not vnet injected, missing private subnet name is required"
        exit
    fi
else
    echo checking $prvSubnet preperation
    checkVnetSubnets $prvSubnet
fi

if [[ $vnetPrepFail == 1 ]]
then
    echo Exiting : please confirm your subnets have NSG and delegation configured and retry
    exit
fi

echo '{
            "type": "Microsoft.Databricks/workspaces",
            "name": "'${workspaceName}'",
            "location": "'${location}'",
            "apiVersion": "'${apiVersion}'",
            "sku": {
                "name": "premium"
            },
            "properties": {
                "managedResourceGroupId": "'${MRGnameID}'",
                "parameters": {
                    "customPrivateSubnetName": {
                        "value": "'${prvSubnet}'"
                    },
                    "customPublicSubnetName": {
                        "value": "'${pubSubnet}'"
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
    curl --location --globoff --request PUT ${apiEndpoint}'/'${workSpaceResourceID}'?api-version='${apiVersion} \
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
                            "value": "'${prvSubnet}'"
                        },
                        "customPublicSubnetName": {
                            "value": "'${pubSubnet}'"
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

echo # new line
echo "Waiting to complete change .... "
az databricks workspace wait --ids ${workSpaceResourceID} --updated
echo done