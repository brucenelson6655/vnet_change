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
