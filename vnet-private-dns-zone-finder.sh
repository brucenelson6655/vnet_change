
VnetNameID="/subscriptions/3f2e4d32-8e8d-46d6-82bc-5bb8d962328b/resourceGroups/brn-ip-conserve/providers/Microsoft.Network/virtualNetworks/brn-noroute-vnet"

nameFilter='privatelink'

checkPrivateDNSzoneLinks() {
        PZVnetNameID=$1
        PZsubscriptionid=$(echo ${PZVnetNameID} | cut -d '/' -f 3 | sed 's/\"//g')
        VnetName=$(echo ${VnetNameID} | cut -d '/' -f 9 | sed 's/\"//g'  | tr -d "\r")

        az account set --subscription ${PZsubscriptionid}
        chkfilter=$2
        listcounter=0
        echo "["
        pdns_zone_ids=$(az network private-dns zone list | jq '.[].id' | sed 's/\"//g' | tr -d "\r" | grep ${chkfilter})
        # pdns_zone_ids=$(az network private-dns zone list | jq '.[].id' | sed 's/\"//g' | tr -d "\r")
        for pzone in $(echo ${pdns_zone_ids})
        do
            PZresourceGroup=$(echo ${pzone} | cut -d '/' -f 5 | sed 's/\"//g' | tr -d "\r")
            pzoneName=$(echo ${pzone} | cut -d '/' -f 9 | sed 's/\"//g' | tr -d "\r")
            PZVnetNameID=$(az network private-dns link vnet list  -g ${PZresourceGroup} -z ${pzoneName}  | jq '.[].virtualNetwork | select( .id | contains("'${VnetName}'")) | .id' | sed 's/\"//g')
            if [ ${PZVnetNameID} ]
            then 
                if [[ $listcounter > 0 ]] 
                then 
                echo ","
                fi
                PZVnetName=$(echo ${PZVnetNameID} | cut -d '/' -f 9)
                echo \{\"VirtualNetowrk\": \"${PZVnetName}\", \"ResourceGroup\": \"${PZresourceGroup}\", \"PrivateDNSzone\": \"${pzoneName}\"\}
                ((listcounter++))
            fi
        done
        echo "]"
}

ourJson=$(checkPrivateDNSzoneLinks ${VnetNameID} ${nameFilter})

echo $ourJson