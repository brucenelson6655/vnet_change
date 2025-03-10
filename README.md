### Simple script for updating the workspace vnet or coverting a managed vnet to a vnet injected Azure Databricks Workspace. 

### ch-adb-vnet.sh 
 
#### Options : 
- -c private subnet name (optional: existing subnet name is the default)
- -p public subnet name (optional: existing subnet name is the default)
- -v virtual network resource id (optional: existing vnetid is the default)
- -w workspace resource id
- -a API version (defaults to 2025-02-01-preview)
- -d debug mode
- -x Azure CLI login (optional)
- -h command line help



#### You will need : 
- the workspace's resource id
- the new or updated virtual network info :
  - vnet resource id
  - public subnet name
  - private subnet name


#### IMPORTANT : if you are converting an Azure Databricks workspace with a managed vnet to vnet injection then you must include a vnet id, and subnet names.

#### Use Cases : 
- CIDR Change : update the CIDR ranges in the Azure subnets and run the command with only the subscription and workspace resource id.
- Vnet or Subnet changes : Include the new Vnet resource ID if using a new Vnet. And include subnet names that are being changed.
    - Note : if you are using a new Vnet with the same subnet names you only need to include the new VNet Resource ID. The script will fill in the existing subnet names from the old Vnet.
- If converting a managed workspace to a vnet injected workspace you *must* include the vnet resource id and both public and private subnet names. 

An easy way to run this tool is to create a run script with the parameters as environment variables: 

#### Example :
```
wid=<workspace resource id>
vid=<virtual network resource id>
prv=<private subnet name>
pub=<public subnet name>
sub=<subscription id>>

sh ./ch-adb-vnet.sh -v $vid -w $wid -s $sub -c $prv -p $pub
```

### ch-adb-vnet-all-in-one.sh 

#### This script is for converting a Managed Vnet workspace to vnet injected and converts PIP to NPIP. It creates the Vnet, subnets and NSG if needed, and NAT Gateway for the workspace conversion and also converts the workspace to NPIP if using PIP.

#### Options : 
- -w workspace resource id
- -a API version (defaults to 2025-02-01-preview)
- -d debug mode
- -x Azure CLI login (optional)
- -h command line help

Enjoy !

