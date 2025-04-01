#!/bin/zsh

echo "=== Script START ==="
echo "=== Script can execute upto 30 minutes for the updates. Please wait until the script finishes the execution. ==="
echo
echo "=== Prequisites ==="
echo "=== The script use azure cli. If you don't have it installed, please follow go/azurecli for installation"
echo

# TODO: Add the workspace check mode.

# TODO: Logging Improvements
# TODO: For logging the output to the files, convert the statement into the function and use it everywhere.
# TODO: For the log file, we should also add some more logs to clarify which step/phase does the json blobs belongs to.

# TODO: (nit) Fix the prompt for the user input (if we are asking them to confirm stuff)
# TODO: (nit) Fix the indentation for the file.

usage() {
  echo "=== HELP ==="
  echo "./$(basename $0) -h --> shows usage"
  echo "-w workspace resource id (required). The format for workspace resource id is '/subscriptions/653bb673-e55d-452c-a90b-d064d5d53ca4/resourceGroups/resourceGroupName/providers/Microsoft.Databricks/workspaces/workspaceName'. This information should already be present in the JIRA Ticket."
  echo
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

# TODO: (nit) Can we extract the input parsing into a function as well.
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
      workspaceLogFileNamePrefix=${globalWorkspaceName}'.'$(date '+%Y%m%d%H%M%S')
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

subscription=$(echo ${globalWorkspaceResourceID} | cut -d '/' -f 3)

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
    local subscriptionid=$(az account show --subscription ${subscription} | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
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
        log_mesaage "You may not have persmissions for subscription " ${subscription}
        log_message "Go to go/iam-requests to request access." 
        exit
    else
        return 0
    fi
}

createNSGIfDoesNotExist() {
  # create the NSG
  local nsgresourceId=$(az network nsg list |  jq '.[] | select(.name=="'${newNsgName}'")' | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)

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
    log_message create NSG $newNsgName
    az network nsg create -g ${globalResourceGroupName} -l ${workspaceRegion} -n ${newNsgName} >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    # TODO: Carve out the following into a function since this pattern seems used everywhere.
    if [[ $? > 0 ]]
    then
        log_message error creating NSG - exiting
        exit
    fi
  fi
}

createVNetAndSubnetsIfDoesNotExist() {
  local vnetresourceid=$(az network vnet list |  jq '.[] | select(.name=="'${newVnetName}'")' | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
  # create the Vnet
  if [ ! -z $vnetresourceid ]
  then
      log_message "$newVnetName exists, we will use this Vnet"
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
      log_message create vnet $newVnetName
      az network vnet create -g ${globalResourceGroupName} -l ${workspaceRegion} -n ${newVnetName} --address-prefix ${defaultVnetCIDR}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          log_message error creating Vnet - exiting
          exit
      fi
  fi
  sleep 1

  # create the subnets
  local pubSubnetid=$(az network vnet subnet list -g ${globalResourceGroupName}  --vnet-name ${newVnetName} |  jq '.[] | select(.name=="'${pubSubnet}'")' | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
  # create the subnet
  if [ ! -z $pubSubnetid ]
  then
      log_message "$pubSubnet exists, we will use this Subnet"
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
      log_message create public subnet $pubSubnet
      az network vnet subnet create -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${pubSubnet} --address-prefixes ${defaultPublicCIDR} --network-security-group ${newNsgName} --delegations Microsoft.Databricks/workspaces --service-endpoints Microsoft.Storage >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          log_message error creating pub subnet - exiting
          exit
      fi
  fi

  local pvtSubnetid=$(az network vnet subnet list -g ${globalResourceGroupName}  --vnet-name ${newVnetName} |  jq '.[] | select(.name=="'${pvtSubnet}'")' | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
  # create the subnet
  if [ ! -z $pvtsubnetid ]
  then
      log_message "$prvSubnet exists, we will use this subnet"
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
      log_message create private subnet $prvSubnet
      az network vnet subnet create -g ${globalResourceGroupName}  --vnet-name ${newVnetName} -n ${prvSubnet} --address-prefixes ${defaultPrivateCIDR} --network-security-group ${newNsgName} --delegations Microsoft.Databricks/workspaces  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
      if [[ $? > 0 ]]
      then
          log_message error creating pvt subnet - exiting
          exit
      fi
  fi
}

createIPIfDoesNotExist() {
  # test if public ip exists already
  piprid=$(az network public-ip list -g ${globalResourceGroupName} |  jq '.[] | select(.name=="'${newPublicIpName}'")' | jq .id  | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)

  if [ ! -z $piprid ]
  then
    log_message "pip $newPublicIpName exists, we will use this public ip"
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
    log_message create public ip
    az network public-ip create -g ${globalResourceGroupName} -n ${newPublicIpName} --location ${workspaceRegion} >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
    if [[ $? > 0 ]]
    then
      log_message error creating public IP - exiting
      exit
    fi
  fi

  globalPublicIpAddress=$(az network public-ip show -g ${globalResourceGroupName} -n ${newPublicIpName} | jq .ipAddress  | sed 's/\"//g')
}

createNatGatewayIfDoesNotExist() {
    natGatewayName=${globalWorkspaceName}'-dbdg-natgw'
    # create nat gateway
    #check to see if we have a natgateway attached
    pubSubnetid=${VnetNameID}'/subnets/'${pubSubnet}
    pubnatgw=$(az network vnet subnet show --ids ${pubSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)

    if [[ ! $pubnatgw == "null" ]]
    then
        natGatewayName=$(basename $pubnatgw)
        natgwpip=$(az network nat gateway show --resource-group ${globalResourceGroupName} --name ${natGatewayName} | jq -r '.publicIpAddresses[0].id' | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
        newPublicIpName=$(basename $natgwpip)
        globalPublicIpAddress=$(az network public-ip show -g ${globalResourceGroupName} -n ${newPublicIpName} | jq .ipAddress  | sed 's/\"//g')
        print "NAT Gateway Name = $natGatewayName"
        print "Public IP = $globalPublicIpAddress"
        #if so is it attached to the private subnet as well ?
        prvSubnetid=${VnetNameID}'/subnets/'${prvSubnet}
        prvnatgw=$(az network vnet subnet show --ids ${prvSubnetid} | jq .natGateway.id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)

        if [[ ! $prvnatgw == "null" ]]
        then
            return
        else
            #lets attach that to the private sunet as well
            log_message "attaching NAT gateway to private subnet"
            az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${prvSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        fi
        #if we are good here lets return.
        return
    fi

    #if not lets see if a natgateway exists
    natgwid=$(az network nat gateway list --resource-group ${globalResourceGroupName} |  jq '.[] | select(.name=="'${natGatewayName}'")' | jq .id | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
    #if it exists - just need to attach it and exit
    if [[ ! -z $natgwid ]]
    then
        log_message "$natGatewayName exists, we will use this NAT Gateway"
        echo -n "Are you sure? (Y or N): "
        read -k 1 -r REPLY
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "proceeding"
            natgwpip=$(az network nat gateway show --resource-group ${globalResourceGroupName} --name ${natGatewayName} | jq -r '.publicIpAddresses[0].id' | sed 's/\"//g' 2>> ${workspaceLogFileNamePrefix}.err)
            newPublicIpName=$(basename $natgwpip)
            globalPublicIpAddress=$(az network public-ip show -g ${globalResourceGroupName} -n ${newPublicIpName} | jq .ipAddress  | sed 's/\"//g')
            print "NAT Gateway Name = $natGatewayName"
            print "Public IP = $globalPublicIpAddress"
        else
            exit
        fi
    else
        #if not lets create a pip (if it doesn't exist) and then out nat gateway
        createIPIfDoesNotExist
        log_message creating NAT gateway
        az network nat gateway create --resource-group ${globalResourceGroupName} --name ${natGatewayName} --location ${workspaceRegion} --public-ip-addresses  ${newPublicIpName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        if [[ $? > 0 ]]
        then
            log_message error creating NAT gateway - exiting
            exit
        fi
        
    fi
        log_message "attaching NAT gateway to public subnet"
        az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${pubSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        log_message "attaching NAT gateway to private subnet"
        az network vnet subnet update -g ${globalResourceGroupName} --vnet-name ${newVnetName} -n ${prvSubnet} --nat-gateway ${natGatewayName}  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
}

updateWorkspaceFromPIPtoNPIP() {
    log_message "Verifying PIP to NPIP for workspace"
    if [[ ${workspaceExistingEnableNPIPConfiguration} == "false" ]]
    then
        log_message "Converting to NPIP"
        az databricks workspace update --ids ${globalWorkspaceResourceID} --enable-no-public-ip true  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err
        log_message "Waiting for workspace update to complete .... "
        az databricks workspace wait --ids ${globalWorkspaceResourceID} --updated
    else
        log_message "Workspace is NPIP"
    fi
    createNatGatewayIfDoesNotExist
}

fetchWorkspaceMetadata() {
  ws=$(az resource show --ids ${globalWorkspaceResourceID} 2>> ${workspaceLogFileNamePrefix}.err)
  if [[ $? > 0 ]]
  then
      log_message "error getting workspace metadata, please verify that your Databricks workspace resource ID is correct !"
      exit
  fi
  echo $ws | jq >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err

  workspaceRegion=$(echo $ws | jq .location  | sed 's/\"//g')
  globalResourceGroupName=$(echo $ws | jq .resourceGroup | sed 's/\"//g')
  workspaceMRGResourceID=$(echo $ws | jq .properties.managedResourceGroupId  | sed 's/\"//g')
  workspaceExistingEnableNPIPConfiguration=$(echo $ws | jq .properties.parameters.enableNoPublicIp.value  | sed 's/\"//g')
  VnetNameID=$(echo $ws | jq .properties.parameters.customVirtualNetworkId.value  | sed 's/\"//g')

  echo "##################################################"
  echo "**************************************************"
  echo "Subscription: $subscription"
  echo "Region: $workspaceRegion"
  echo "Workspace Name: $globalWorkspaceName"
  echo "Resource Group Name: $globalResourceGroupName"
  echo "Existing EnableNPIP Configuration: $workspaceExistingEnableNPIPConfiguration"
  echo "Custom VNet Resource ID: $VnetNameID"
  echo "**************************************************"
  echo "##################################################"

  echo -n "Should we start updating the workspace? (Y or N): "
  read -k 1 -r REPLY
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    echo "proceeding"
  else
    exit
  fi
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
          }' | jq  >> ${workspaceLogFileNamePrefix}.log 2>> ${workspaceLogFileNamePrefix}.err


  echo
  log_message update the Workspace This could take up to 15 minutes ....
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

  log_message "Waiting for workspace update to complete .... "
  az databricks workspace wait --ids ${globalWorkspaceResourceID} --updated
}

updateWorkspace() {
  fetchWorkspaceMetadata

  newVnetName=${globalWorkspaceName}'-dbdg-vnet'
  newNsgName=${globalWorkspaceName}'-dbdg-nsg'
  newPublicIpName=${globalWorkspaceName}'-dbdg-public-ip'

  if [[ $VnetNameID == "null" ]]
  then
      log_message "This workspace is Databricks Managed and will be updated to VNet Injected"
      updateWorkspaceFromDBMangedtoVnetInjected
  else
      log_message "This workspace is Vnet Injected"
      pubSubnet=$(echo $ws | jq .properties.parameters.customPublicSubnetName.value | sed 's/\"//g')
      prvSubnet=$(echo $ws | jq .properties.parameters.customPrivateSubnetName.value | sed 's/\"//g')
      newVnetName=$(basename $VnetNameID)
      log_message "private subnet name = $prvSubnet"
      log_message "public subnet name = $pubSubnet"
  fi

  updateWorkspaceFromPIPtoNPIP

  log_message "The workspace update has been completed."
  echo "##################################################"
  echo "**************************************************"
  echo "Next Steps:"
  echo "Step 1: Please create a classic cluster and run the following command '%sh curl -s ifconfig.me'"
  echo "Step 2: Ensure the IP received from the previous step matches the IP ${globalPublicIpAddress}."
  echo "Step 3: Put out a PR to add the public IP to the file -> 'envoy/traffic/workspace-cidrs.jsonnet'. Example PR -> https://github.com/databricks-eng/universe/pull/977086"
  echo "(Optional) If your workspace has IP ACLs configured, please allowlist the IP of the clusters to the IP ACL list."
  echo "(Optional) We created the service endpoint for the storage. If you don't need it, please delete it manually."
  echo "**************************************************"
  echo "##################################################"
}

selectAzureDataPlaneSubscription ${subscription}
if [[ $? > 0 ]]
then
    echo login error - exiting
    exit
fi

updateWorkspace
