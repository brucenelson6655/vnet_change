#!/bin/zsh

echo "=== Script START ==="

# TODOs

# TODO: Logging Improvements
# TODO: For logging the output to the files, convert the statement into the function and use it everywhere.
# TODO: For the log file, we should also add some more logs to clarify which step/phase does the json blobs belongs to.

# TODO: Minimize the usage of the global variables. Convert the variables to local and pass them around into functions.

# TODO: Fix the prompt for the user input (if we are asking them to confirm stuff)
# TODO: Fix the prompt to accomodate for the zsh instead of bash.

# TODO: Print out the stable IP of the NAT Gateway and recommend user to add it to the universe file.

# TODO: (nit) Fix the indentation for the file.

# TODO: Update Test Cases for the correctness of the script
# 1. DB Managed PIP to Vnet Injected NPIP Workspace
# 2. VNet Injected PIP to Vnet Injected NPIP Workspace
# 3. Partial updates for the above workspaces.
# 4. DB Managed NPIP to Vnet Injected NPIP workspace.


usage() {
  echo "./$(basename $0) -h --> shows usage"
  echo "-w workspace resource id (required)"
  echo "The script relies on the fact that there is no other resource (except workspace) with the workspace name in the resource group containing the workspace. If this is not the case, please do not run the script"
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

# defaults
defaultApiVersion='2025-02-01-preview'
defaultApiEndpoint='https://management.azure.com'
pubSubnet="public-subnet"
prvSubnet="private-subnet"
defaultVnetCIDR='10.139.0.0/16'
defaultPublicCIDR='10.139.0.0/18'
defaultPrivateCIDR='10.139.64.0/18'

## set -x  # shows all commands being executed
# # set -e  # exits on any command failure
# # set -u  # exits on undefined variables

# TODO: Can we extract the input parsing into a function as well.
if [ $# -eq 0 ] ; then
  usage
  exit
fi

optstring=":hw:"
while getopts ${optstring} arg; do
  case ${arg} in
    h)
      echo "showing usage!"
      usage
      ;;
    w)
      globalWorkspaceResourceID=$OPTARG
      globalWorkspaceName=$(basename "$globalWorkspaceResourceID")
      workspaceLogFileNamePrefix=${globalWorkspaceName}'.'`date '+%Y%m%d%H%M%S'`
      touch ${workspaceLogFileNamePrefix}.log
      touch ${workspaceLogFileNamePrefix}.err
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

if [[ ! ${globalWorkspaceResourceID} ]]
then
    echo "Workspace resource ID is required !"
    exit
fi

subscription=`echo ${globalWorkspaceResourceID} | cut -d '/' -f 3`

log_message() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local message="$*"
    echo "[$timestamp] $message" >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    echo "[$timestamp] $message"
}

selectAzureDataPlaneSubscription() {
    local subscription=$1
    if [[ ! $subscription ]]
    then
        log_message "Subscription ID is required !" 
        exit
    fi
    local subscriptionid=`az account show --subscription ${subscription} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`
    if [[ ! $subscription == $subscriptionid ]]
    then 
        log_message "Login Required" 
        az login >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        if [[ $? > 0 ]]
        then 
            log_message "Login Failed Please check your access"
            exit
        else
            log_message "Login Successful !" 
        fi
    fi 
    log_message "Setting Active Subscription to $subscription"  
    az account set --subscription ${subscription} >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    if [[ $? > 0 ]]
    then 
        log_message "Subscription $subscription was not accessable"
        exit
    else
        return 0    
    fi
}

createNSGIfDoesNotExist() {
  # create the NSG
  # TODO: Check for the existence of the NSG
  local nsgresourceId=`az network nsg show -g ${globalResourceGroupName} -n ${newNsgName} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`

  if [ ! -z $nsgresourceId ]
  then
    echo "$newNsgName exists, we will use this NSG"
    echo -n "Are you sure? (Y or N): "
    read -k 1 -r REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      echo "proceeding"
    else
      exit
    fi
  else
    echo create NSG $newNsgName
    az network nsg create -g ${globalResourceGroupName} -l ${workspaceRegion} -n ${newNsgName} >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    # TODO: Can we also carve out the following into a function since this pattern seems used everywhere.
    if [[ $? > 0 ]]
    then
        echo error creating NSG - exiting
        exit
    fi
  fi
}

createVNetAndSubnetsIfDoesNotExist() {
  # TODO: Update the code to check for the existence of Vnet
  local vnetresourceid=`az network vnet show -g ${globalResourceGroupName} -n ${newVnetName} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`
  # create the Vnet
  if [ ! -z $vnetresourceid ]
  then
      echo "$newVnetName exists, we will use this Vnet"
      echo -n "Are you sure? (Y or N): "
      read -k 1 -r REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]
      then
        echo "proceeding"
      else
        exit
      fi
  else
      echo create vnet $newVnetName
      az network vnet create -g ${globalResourceGroupName} -l ${workspaceRegion} -n ${newVnetName} --address-prefix ${defaultVnetCIDR}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          echo error creating Vnet - exiting
          exit
      fi
  fi
  sleep 1

  # create the subnets
  # TODO: Update the code to check for the existence of subnets into the Vnet
  local pubSubnetid=`az network vnet subnet show -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${pubSubnet} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`
  # create the Vnet
  if [ ! -z $pubSubnetid ]
  then
      echo "$pubSubnet exists, we will use this Subnet"
      echo -n "Are you sure? (Y or N): "
      read -k 1 -r REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]
      then
        echo "proceeding"
      else
        exit
      fi
  else
      echo create
      az network vnet subnet create -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${pubSubnet} --address-prefixes ${defaultPublicCIDR} --network-security-group ${newNsgName} --delegations Microsoft.Databricks/workspaces  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          echo error creating pub subnet - exiting
          exit
      fi
  fi 

  local pvtsubnetid=`az network vnet subnet show -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${prvSubnet} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`
  # create the Vnet
  if [ ! -z $pvtsubnetid ]
  then
      echo "$prvSubnet exists, we will use this subnet"
      echo -n "Are you sure? (Y or N): "
      read -k 1 -r REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]
      then
        echo "proceeding"
      else
        exit
      fi
  else
      echo create private subnet $prvSubnet
      az network vnet subnet create -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${prvSubnet} --address-prefixes ${defaultPrivateCIDR} --network-security-group ${newNsgName} --delegations Microsoft.Databricks/workspaces  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          echo error creating pvt subnet - exiting
          exit
      fi
  fi
}

createIPIfDoesNotExist() {
  # test if public ip exists already
  piprid=`az network public-ip show -g ${globalResourceGroupName} -n ${newPublicIpName} | jq .id  | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`

  if [ ! -z $piprid ]
  then
    echo "pip $newPublicIpName exists, we will use this public ip"
    # read -p "Are you sure? (Y or N): " -n 1 -r
    # echo    # new line
    echo -n "Are you sure? (Y or N): "
    read -k 1 -r REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      echo "proceeding"
    else
      exit
    fi
  else
    echo create public ip
    az network public-ip create -g ${globalResourceGroupName} -n ${newPublicIpName} --location ${workspaceRegion} >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    if [[ $? > 0 ]]
    then
      echo error creating public IP - exiting
      exit
    fi
  fi
}

createNatGatewayIfDoesNotExist() {
    # TODO: Check if either of the subnets are linked with the NAT GW.
    natGatewayName=${globalWorkspaceName}'-natgw'
    # create nat gateway
    #check to see if we have a natgateway attached
    pubSubnetid=${VnetNameID}'/subnets/'${pubSubnet}
    pubnatgw=`az network vnet subnet show --ids ${pubSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`

    if [[ ! $pubnatgw == "null" ]]
    then
        #if so is it attached to the private subnet as well ?
        prvSubnetid=${VnetNameID}'/subnets/'${prvSubnet}
        prvnatgw=`az network vnet subnet show --ids ${prvSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`

        if [[ ! $prvnatgw == "null" ]]
        then
            echo "congrats its complete"
            exit
        else
            #lets attach that to the private sunet as well
            echo "attaching NAT gateway to private subnet"
            az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${prvSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        fi
        #if we are good here lets exit.
        exit
    fi

    #if not lets see if a natgateway exists
    natgwid=`az network nat gateway show --resource-group ${globalResourceGroupName} --name ${natGatewayName} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err`
    #if it exists - just need to attach it and exit
    echo NAT GW $natgwid
    if [[ ! -z $natgwid ]]
    then
        echo "$natGatewayName exists, we will use this NAT Gateway"
        # read -p "Are you sure? (Y or N): " -n 1 -r
        # echo    # new line
        echo -n "Are you sure? (Y or N): "
        read -k 1 -r REPLY
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "proceeding"
        else
            exit
        fi
    else
        #if not lets create a pip (if it doesn't exist) and then out nat gateway
        createIPIfDoesNotExist
        echo creating NAT gateway
        az network nat gateway create --resource-group ${globalResourceGroupName} --name ${natGatewayName} --location ${workspaceRegion} --public-ip-addresses  ${newPublicIpName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        if [[ $? > 0 ]]
        then
            echo error creating NAT gateway - exiting
            exit
        fi
    fi
        echo "attaching NAT gateway to public subnet"
        az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${pubSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        echo "attaching NAT gateway to private subnet"
        az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${prvSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
}

updateWorkspaceFromPIPtoNPIP() {
    echo "updating PIP to NPIP for workspace"
    if [[ ${workspaceExistingEnableNPIPConfiguration} == "false" ]]
    then
        echo "Converting to NPIP"
        az databricks workspace update --ids ${globalWorkspaceResourceID} --enable-no-public-ip true  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    else
        echo Workspace is NPIP
    fi
    createNatGatewayIfDoesNotExist
}

fetchWorkspaceMetadata() {
  # TODO: Can we export the output from this function and use it as input for other functions.
  ws=`az resource show --ids ${globalWorkspaceResourceID} 2>> ${workspaceLogFileNamePrefix}.err`
  if [[ $? > 0 ]]
  then
      echo error workspace metadata try using the -x flag to login - exiting
      exit
  fi
  echo $ws | jq >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err

  workspaceRegion=`echo $ws | jq .location  | sed 's/\"//g'`
  globalResourceGroupName=`echo $ws | jq .resourceGroup | sed 's/\"//g'`
  workspaceMRGResourceID=`echo $ws | jq .properties.managedResourceGroupId  | sed 's/\"//g'`
  workspaceExistingEnableNPIPConfiguration=`echo $ws | jq .properties.parameters.enableNoPublicIp.value  | sed 's/\"//g'`
  VnetNameID=`echo $ws | jq .properties.parameters.customVirtualNetworkId.value  | sed 's/\"//g'`

  echo "Region : " $workspaceRegion
  echo "Resource Group Name : " $globalResourceGroupName
  echo "Existing EnableNPIP Configuration: " $workspaceExistingEnableNPIPConfiguration
  echo "Workspace MRG Resource ID : " $workspaceMRGResourceID
  echo "Custom VNet Resource ID : " $VnetNameID
}

updateWorkspaceFromDBMangedtoVnetInjected() {
  VnetNameID='/subscriptions/'${subscription}'/resourceGroups/'${globalResourceGroupName}'/providers/Microsoft.Network/virtualNetworks/'${newVnetName}

  createNSGIfDoesNotExist

  createVNetAndSubnetsIfDoesNotExist

  echo '{
              "type": "Microsoft.Databricks/workspaces",
              "name": "'${globalWorkspaceName}'",
              "location": "'${workspaceRegion}'",
              "apiVersion": "'${defaultApiVersion}'",
              "sku": {
                  "name": "premium"
              },
              "properties": {
                  "managedResourceGroupId": "'${workspaceMRGResourceID}'",
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
                          "value": '${workspaceExistingEnableNPIPConfiguration}'
                      }
                  }
              }
          }' | jq
  sleep 1

  echo
  echo update the Workspace This could take up to 15 minutes ....
  echo

  az rest --method put \
    --url "${defaultApiEndpoint}/${globalWorkspaceResourceID}?api-version=${defaultApiVersion}" \
    --body '{
      "type": "Microsoft.Databricks/workspaces",
      "name": "'${globalWorkspaceName}'",
      "location": "'${workspaceRegion}'",
      "sku": {
          "name": "premium"
      },
      "properties": {
          "managedResourceGroupId": "'${workspaceMRGResourceID}'",
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
                  "value": '${workspaceExistingEnableNPIPConfiguration}'
              }
          }
      }
    }' >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err

  echo "Waiting to complete change .... "
  az databricks workspace wait --ids ${globalWorkspaceResourceID} --updated
}

updateWorkspace() {
  fetchWorkspaceMetadata

  newVnetName=${globalWorkspaceName}'-vnet'
  newNsgName=${globalWorkspaceName}'-nsg'
  newPublicIpName=${globalWorkspaceName}'-public-ip'

  # TODO: Instead of having two calls to the function updateWorkspaceFromPIPtoNPIP, can we have only one.
    # We can do the update of DB Managed to VNet Injected only if it is applicable.
    # If it is not applicable, we just move onto the next step and update PIP to NPIP (as applicable).

  # The workspace is VNet Injected. We only need to update the PIP to NPIP
  if [[ ! $VnetNameID == "null" ]]
  then
      echo "This workspace is vnet injected"
      pubSubnet=`echo $ws | jq .properties.parameters.customPublicSubnetName.value | sed 's/\"//g'`
      prvSubnet=`echo $ws | jq .properties.parameters.customPrivateSubnetName.value | sed 's/\"//g'`
      echo $prvSubnet $pubSubnet
      updateWorkspaceFromPIPtoNPIP
      exit
  fi

  # IF the workspace is DB Managed PIP, then update the workspace from
  # 1. DB Managed to VNet Injected
  # 2. PIP to  NPIP
  # This will help ensure that the final workspace is VNet Injected NPIP workspace.
  updateWorkspaceFromDBMangedtoVnetInjected
  updateWorkspaceFromPIPtoNPIP

  echo "Done"
}

selectAzureDataPlaneSubscription ${subscription}
if [[ $? > 0 ]]
then 
    echo login error - exiting
    exit
fi

updateWorkspace
