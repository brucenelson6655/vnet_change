#!/bin/bash

usage() {
        echo "./$(basename $0) -h --> shows usage"
        echo "-w workspace resource id (required)"
        echo "-a API version (defaults to 2025-02-01-preview)"
        echo "-d debug mode"
        echo "-Z dry run mode" 
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

optstring=":hw:a:xdZ"

# defaults
apiVersion='2025-02-01-preview'
apiEndpoint='https://management.azure.com'
debugMode=0
dryrunMode=0
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
      workSpaceLog=${workspaceName}'.'`date '+%Y%m%d%H%M%S'`
      ;;
    a) apiVersion=$OPTARG
      ;;
    d)
      echo "debug"
      debugMode=1
      set -xv
      ;;
    Z)
      echo "Dry Run Mode Set\nNochanges will be applied, for verification purposes only"
      dryrunMode=1
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

subscription=`echo ${workSpaceResourceID} | cut -d '/' -f 3`

if [[ ! $subscription ]]
then 
    echo "Subscription ID is required !"
    exit
fi

az account set --subscription ${subscription}



pubpip() {
    # test if public ip exists already 
        piprid=`az network public-ip show -g ${resourceGrpName} -n ${pipName} | jq .id  | sed 's/\"//g' 2>> ${workSpaceLog}.err`
        
        if [ ! -z $piprid ]
        then
            echo "pip $pipName exists, we will use this public ip" 
            read -p "Are you sure? (Y or N): " -n 1 -r
            echo    # new line
            if [[ $REPLY =~ ^[Yy]$ ]]
            then
                echo "proceeding"
            else
                exit
            fi
        else
            echo create public ip 
            az network public-ip create -g ${resourceGrpName} -n ${pipName} --location ${location} >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
            if [[ $? > 0 ]]
            then 
                echo error creating public IP - exiting
                exit
            fi
        fi
}

natgway() {
 # create nat gateway 
    #check to see if we have a natgateway attached 
    pubSubnetid=${VnetNameID}'/subnets/'${pubSubnet}
    pubnatgw=`az network vnet subnet show --ids ${pubSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workSpaceLog}.err` 

    if [ ! $pubnatgw == "null" ]
    then
        #if so is it attached to the private subnet as well ?
        prvSubnetid=${VnetNameID}'/subnets/'${prvSubnet}
        prvnatgw=`az network vnet subnet show --ids ${prvSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workSpaceLog}.err` 
        
        if [ ! $prvnatgw == "null" ]
        then
            echo "congrats its complete"
            exit
        else 
            #lets attach that to the private sunet as well
            echo "attaching NAT gateway to private subnet" 
            az network vnet subnet update -g ${resourceGrpName} --vnet-name ${VnetName} -n ${prvSubnet} --nat-gateway ${natGW}  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
        fi
        #if we are good here lets exit. 
        exit
    fi

    #if not lets see if a natgateway exists
    natgwid=`az network nat gateway show --resource-group ${resourceGrpName} --name ${natGW} | jq .id | sed 's/\"//g' 2>> ${workSpaceLog}.err`
    #if it exists - just need to attach it and exit
    echo NAT GW $natgwid
    if [ ! -z $natgwid ]
    then 
        echo "$natGW exists, we will use this NAT Gateway" 
        read -p "Are you sure? (Y or N): " -n 1 -r
        echo    # new line
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "proceeding"
        else
            exit
        fi
    else
        #if not letscreate a pip (if it doesn't exist) and then out nat gateway
        pubpip
        echo creating NAT gateway
        az network nat gateway create --resource-group ${resourceGrpName} --name ${natGW} --location ${location} --public-ip-addresses  ${pipName}  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
        if [[ $? > 0 ]]
        then 
            echo error creating NAT gateway - exiting
            exit
        fi
    fi
        echo "attaching NAT gateway to public subnet" 
        az network vnet subnet update -g ${resourceGrpName} --vnet-name ${VnetName} -n ${pubSubnet} --nat-gateway ${natGW}  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
        echo "attaching NAT gateway to private subnet" 
        az network vnet subnet update -g ${resourceGrpName} --vnet-name ${VnetName} -n ${prvSubnet} --nat-gateway ${natGW}  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
}

convertNPIP() {
    if [ $enableNPIP == "false" ]
    then
        echo "Converting to NPIP"
        az databricks workspace update --ids ${workSpaceResourceID} --enable-no-public-ip true  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
        
    else
        echo Workspace is NPIP
    fi
    
    natgway
}


bearerToken=`az account get-access-token | jq .accessToken | sed 's/\"//g'`
if [[ $? > 0 ]]
then 
    echo error with getting bearer token - exiting
    exit
fi

ws=`curl --location --globoff --request GET ${apiEndpoint}'/'${workSpaceResourceID}'?api-version='${apiVersion} \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '${bearerToken}`

if [[ $? > 0 ]]
then 
    echo error workspace metadata try using the -x flag to login - exiting
    exit
fi

MRGnameID=`echo $ws | jq .properties.managedResourceGroupId  | sed 's/\"//g'`
location=`echo $ws | jq .location  | sed 's/\"//g'`
enableNPIP=`echo $ws | jq .properties.parameters.enableNoPublicIp.value  | sed 's/\"//g'`

VnetNameID=`echo $ws | jq .properties.parameters.customVirtualNetworkId.value  | sed 's/\"//g'`

if [$debugMode == 1]
then
   echo "Debug Mode : " 
   echo "NPIP : " $enableNPIP
   echo "MRG ID : " $MRGnameID
   echo "Region : " $location
   echo "VNet ID : " $VnetNameID
   if [[ $VnetNameID == "null" ]]
   then 
        echo "This is a Managed Vnet workspace"
   fi
fi


if [$dryrunMode == 1] 
then
   echo "Dry Run Mode" 
else 
   echo "All in One Mode"
fi

azws=`az resource show --ids ${workSpaceResourceID}`
if [[ $? > 0 ]]
then 
    echo error getting workspace metadata - exiting
    exit
fi

if [ $debugMode == 1 ]
then 
   echo $azws | jq 
fi

echo $azws | jq > ${workSpaceLog}.log 2> ${workSpaceLog}.err

VnetName=${workspaceName}'-vnet'
nsgName=${workspaceName}'-nsg'
resourceGrpName=`echo $azws | jq .resourceGroup | sed 's/\"//g'`


natGW=${workspaceName}'-natgw'
pipName=${workspaceName}'-pip'

if [[ ! $VnetNameID == "null" ]]
then 
    echo "This workspace is vnet injected"
    pubSubnet=`echo $azws | jq .properties.parameters.customPublicSubnetName.value | sed 's/\"//g'`
    prvSubnet=`echo $azws | jq .properties.parameters.customPrivateSubnetName.value | sed 's/\"//g'`
    echo $prvSubnet $pubSubnet
    convertNPIP
    exit
fi


VnetNameID='/subscriptions/'${subscription}'/resourceGroups/'${resourceGrpName}'/providers/Microsoft.Network/virtualNetworks/'${VnetName}

# create the NSG
az network nsg create -g ${resourceGrpName} -l ${location} -n ${nsgName} >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
if [[ $? > 0 ]]
then 
    echo error creating NSG - exiting
    exit
fi

# create the Vnet
az network vnet create -g ${resourceGrpName} -l ${location} -n ${VnetName} --address-prefix ${addressPrefix}  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
if [[ $? > 0 ]]
then 
    echo error creating Vnet - exiting
    exit
fi
sleep 1

# create the subnets 
az network vnet subnet create -g ${resourceGrpName}  --vnet-name ${VnetName} -n ${pubSubnet} --address-prefixes ${publicCIDR} --network-security-group ${nsgName} --delegations Microsoft.Databricks/workspaces  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
if [[ $? > 0 ]]
then 
    echo error creating pub subnet - exiting
    exit
fi
az network vnet subnet create -g ${resourceGrpName}  --vnet-name ${VnetName} -n ${prvSubnet} --address-prefixes ${privateCIDR} --network-security-group ${nsgName} --delegations Microsoft.Databricks/workspaces  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err
if [[ $? > 0 ]]
then 
    echo error creating pvt subnet - exiting
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

sleep 1


echo 
echo update the Workspace This could take up to 15 minutes .... 
echo
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
        }'  >> ${workSpaceLog}.log 2>> ${workSpaceLog}.err


echo "Waiting to complete change .... "
az databricks workspace wait --ids ${workSpaceResourceID} --updated

convertNPIP

echo "Done"
