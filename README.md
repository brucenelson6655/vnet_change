README

Options : (required)
- -c private subnet name
- -p public subnet name
- -v virtual network resource id
- -w workspace resource id
- -s subscription id
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
