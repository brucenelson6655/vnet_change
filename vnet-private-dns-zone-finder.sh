
VnetNameID=${1}

if [ -z $VnetNameID ] 
then 
    echo "Usage $0 <vnet resource ID>"
    echo "Works best piping out put to jq" 
    exit
fi

# you can uncoment the name filter to narrow down specific resource groups etc  
# nameFilter='<Name Filter>' #optional

# uncomment for searching agains a specific Azure tenant 
# userTenantId='<tenant id>' #optional

checkPrivateDNSzoneLinks() {
        PZVnetNameID=$1
        PZtenantId=$2

        if [ ! ${PZtenantId} ]
        then 
           PZsubscriptionid=$(echo ${PZVnetNameID} | cut -d '/' -f 3 | sed 's/\"//g')
        else 
           PZsubscriptionid=$(az account list | jq '.[] | select( .state | contains("Enabled")) | select( .tenantId | contains("'${PZtenantId}'")) | .id' | sed 's/\"//g' | tr -d "\r")
        fi

        listcounter=0
        echo "["
        for i in $(echo ${PZsubscriptionid} )
        do
            az account set --subscription ${i}

            VnetName=$(echo ${VnetNameID} | cut -d '/' -f 9 | sed 's/\"//g'  | tr -d "\r")

            chkfilter=${nameFilter}
            
            
            if [ ${chkfilter} ]
            then 
                pdns_zone_ids=$(az network private-dns zone list | jq '.[].id' | sed 's/\"//g' | tr -d "\r" | grep ${chkfilter})
            else
                pdns_zone_ids=$(az network private-dns zone list | jq '.[].id' | sed 's/\"//g' | tr -d "\r")
            fi
            for pzone in $(echo ${pdns_zone_ids})
            do   
                PZresourceGroup=$(echo ${pzone} | cut -d '/' -f 5 | sed 's/\"//g' | tr -d "\r")
                pzoneName=$(echo ${pzone} | cut -d '/' -f 9 | sed 's/\"//g' | tr -d "\r" )
                PZVnetNameID=$(az network private-dns link vnet list  -g ${PZresourceGroup} -z ${pzoneName}  | jq '.[].virtualNetwork | select( .id | contains("'${VnetName}'")) | .id' | sed 's/\"//g')
                if [ ${PZVnetNameID} ]
                then 
                    PZVnetName=$(echo ${PZVnetNameID} | cut -d '/' -f 9)
                    PZVlinkname=$(az network private-dns link vnet list --resource-group ${PZresourceGroup} --zone-name ${pzoneName} | jq '.[] | select( .virtualNetwork.id | contains("'${VnetName}'")) | .name' | sed 's/\"//g')
                    PZVfallback=$(az network private-dns link vnet list --resource-group ${PZresourceGroup} --zone-name ${pzoneName} | jq '.[] | select( .virtualNetwork.id | contains("'${VnetName}'")) | .resolutionPolicy' | sed 's/\"//g')
                    if [[ $PZVfallback == "NxDomainRedirect" ]]
                    then 
                      PZVfallback="Yes"
                    else
                      PZVfallback="No"
                    fi

                    if [[ $listcounter > 0 ]] 
                    then 
                    echo ","
                    fi
                    
                    echo \{\"Subscription\": \"${i}\", \"VirtualNetowrk\": \"${PZVnetName}\", \"ResourceGroup\": \"${PZresourceGroup}\", \"PrivateDNSzone\": \"${pzoneName}\", \"VnetLinkName\": \"${PZVlinkname}\", \"FallBackEnabled\": \"${PZVfallback}\"\}
                    ((listcounter++))
                fi
            done
            
        done
        echo "]"
}

ourJson=$(checkPrivateDNSzoneLinks ${VnetNameID} ${userTenantId})

echo $ourJson