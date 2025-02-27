#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-w workspace resource id (required)"
        echo "-s subscription id (required)"
        echo "-a API version (defaults to 2025-02-01-preview)"
        echo "-d debug mode"
        echo "-x Azure CLI login (optional)"
        exit
}

# workflow : 
# get existing workspace metadata 
# check flag if all in one - if true .. 
# use workspace name to generate NSG, VNet and Subnets
# get resource ID of new vnet 
# build reset api for ws change 
# change
# wait for the change az databricks workspace wait
# if pip convert to npip az databricks workspace update --resource-group <> --name <> --enable-no-public-ip true
# add a Nat gateway

optstring=":hs:w:a:xd"

# defaults
apiVersion='2025-02-01-preview'
apiEndpoint='https://management.azure.com'
debugMode=0
pubSubnet="public-subnet"
prvSubnet="private-subnet"
addressPrefix='10.140.0.0/16'
publicCIDR='10.140.0.0/18'
privateCIDR='10.140.64.0/18'

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
    a) apiVersion=$OPTARG
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


bearerToken=`az account get-access-token | jq .accessToken | sed 's/\"//g'`
# bearerToken=`az account get-access-token | jq .accessToken | sed 's/^"\|"$//g'`

ws=`curl --location --globoff --request GET ${apiEndpoint}'/'${workSpaceResourceID}'?api-version='${apiVersion} \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '${bearerToken}`

MRGnameID=`echo $ws | jq .properties.managedResourceGroupId  | sed 's/\"//g'`
location=`echo $ws | jq .location  | sed 's/\"//g'`
enableNPIP=`echo $ws | jq .properties.parameters.enableNoPublicIp.value  | sed 's/\"//g'`

VnetNameID=`echo $ws | jq .properties.parameters.customVirtualNetworkId.value  | sed 's/\"//g'`


    if [[ ! $VnetNameID == "null" ]]
    then 
        echo "This workspace is vnet injected, please use the ch-adb-vnet.sh script"
        exit
    fi

echo "All in One Mode"
azws=`az resource show --ids ${workSpaceResourceID}`

if [ $debugMode == 1 ]
then 
   echo $azws | jq
fi

VnetName=${workspaceName}'-vnet'
nsgName=${workspaceName}'-nsg'
resourceGrpName=`echo $azws | jq .resourceGroup | sed 's/\"//g'`

VnetNameID='/subscriptions/'${subscription}'/resourceGroups/'${resourceGrpName}'/providers/Microsoft.Network/virtualNetworks/'${VnetName}
natGW=${workspaceName}'-natgw'
pipName=${workspaceName}'-pip'

# create the NSG
az network nsg create -g ${resourceGrpName} -l ${location} -n ${nsgName} 

# create the Vnet
az network vnet create -g ${resourceGrpName} -l ${location} -n ${VnetName} --address-prefix ${addressPrefix}
sleep 1

# create the subnets 
az network vnet subnet create -g ${resourceGrpName}  --vnet-name ${VnetName} -n ${pubSubnet} --address-prefixes ${publicCIDR} --network-security-group ${nsgName} --delegations Microsoft.Databricks/workspaces 
az network vnet subnet create -g ${resourceGrpName}  --vnet-name ${VnetName} -n ${prvSubnet} --address-prefixes ${privateCIDR} --network-security-group ${nsgName} --delegations Microsoft.Databricks/workspaces 

# create public ip 
az network public-ip create -g ${resourceGrpName} -n ${pipName}
# create nat gateway 
az network nat gateway create --resource-group ${resourceGrpName} --name ${natGW} --location ${location} --public-ip-addresses  ${pipName} 

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

sleep 1


echo update the Workspace 
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


echo "Waiting to complete change .... "
az databricks workspace wait --ids ${workSpaceResourceID} --updated
if [ $enableNPIP == "false" ]
then
   echo "Converting to NPIP"
   az databricks workspace update --ids ${workSpaceResourceID} --enable-no-public-ip true
fi
echo "attaching NAT gateway to public subnet" 
az network vnet subnet update -g ${resourceGrpName} --vnet-name ${VnetName} -n ${pubSubnet} --nat-gateway ${natGW}
echo "Done"