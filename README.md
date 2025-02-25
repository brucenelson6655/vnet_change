README

Options : (required)
- -c private subnet name (optional: existing subnet name is the default)
- -p public subnet name (optional: existing subnet name is the default)
- -v virtual network resource id (optional: existing vnetid is the default)
- -w workspace resource id
- -s subscription id
- -a API version (defaults to 2025-02-01-preview)
- -x Azure CLI login (optional)
- -h command line help

Simple script for updating the workspace vnet or coverting a managed vnet to vnet injected. 

Needed are : 
- the workspace's resource id
- the new or updated virtual network info :
  - vnet resource id
  - public subnet name
  - private subnet name
- and the subscription id this workspace lives in

#### IMPORTANT : if you are converting a workspace with a managed vnet to vnet injection then you must include vnet id, and subnet names

Use Cases : 
- CIDR Change : update the CIDR ranges in the Azure subnets and run the command with only the subscription and workspace resuorce id.
- Vnet or Subnet changes : Include the new Vnet resource ID is using a new Vnet. And Subnet names that are being changed.
    - Note : if you are using a new Vnet with the same subnet names you only need to include the new VNet Resuorce ID. The script will fill in the existing subnet names from the old Vnet.
- Converting a Managed workspace to vnet injection you *must* include the vnet resource id and both public and private subnet names. 

An easy way to run this tool is to create a run script with the parameters as environment variables: 

Example :
```
wid=<workspace resource id>
vid=<virtual network resource id>
prv=<private subnet name>
pub=<public subnet name>
sub=<subscription id>>

sh ./ch-adb-vnet.sh -v $vid -w $wid -s $sub -c $prv -p $pub
```
Enjoy !

