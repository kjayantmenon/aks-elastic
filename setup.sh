#! /bin/bash
source ./aks-es.config


export LOCATION="$LOCATION"
export AKS_NAME="$AKS_NAME"
export RG=$AKS_NAME-$LOCATION
export AKS_VNET_NAME=$AKS_NAME-vnet
export AKS_CLUSTER_NAME=$AKS_NAME-cluster
export AKS_VNET_CIDR=172.16.0.0/16
export AKS_NODES_SUBNET_NAME=$AKS_NAME-subnet
export AKS_NODES_SUBNET_PREFIX=172.16.0.0/23
export SERVICE_CIDR=10.0.0.0/16
export DNS_IP=10.0.0.10
export NETWORK_PLUGIN=azure
export NETWORK_POLICY=calico
export SYSTEM_NODE_COUNT=3
export USER_NODE_COUNT=2
export NODES_SKU=Standard_D8ds_v4
export K8S_VERSION=$(az aks get-versions  -l $LOCATION --query 'orchestrators[-2].orchestratorVersion' -o tsv)
export SYSTEM_POOL_NAME=systempool
export STORAGE_POOL_ZONE1_NAME=espoolz1
export STORAGE_POOL_ZONE2_NAME=espoolz2
export STORAGE_POOL_ZONE3_NAME=espoolz3
export IDENTITY_NAME=$AKS_NAME`date +"%d%m%y"`

#Select subscription
az account set --subscription="$SUBSCRIPTION"

#Delete the Resource Group if it already exists

#if [ $(az group exists --name $RG --subscription $SUBSCRIPTION) =false]; then
if [ $(az group exists --name $RG --subscription $SUBSCRIPTION ) = true ]; then    
    echo "deleting the resource group..."
    #az group delete --name "$RG"  --no-wait --subscription "$SUBSCRIPTION" --yes
fi

# Create Resource Group
az group create --name $RG --location $LOCATION
RG_ID=$(az group show -n $RG  --query id -o tsv)

# Create User Managed Identity
az identity create --name $IDENTITY_NAME --resource-group $RG
IDENTITY_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RG --query id -o tsv)
IDENTITY_CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RG --query clientId -o tsv)

# Create Network
az network vnet create \
  --name $AKS_VNET_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix $AKS_VNET_CIDR \
  --subnet-name $AKS_NODES_SUBNET_NAME \
  --subnet-prefix $AKS_NODES_SUBNET_PREFIX
VNETID=$(az network vnet show -g $RG --name $AKS_VNET_NAME --query id -o tsv)
AKS_VNET_SUBNET_ID=$(az network vnet subnet show --name $AKS_NODES_SUBNET_NAME -g $RG --vnet-name $AKS_VNET_NAME --query "id" -o tsv)

# Allow Managed Identity access to Resource Group and VNet
az role assignment create --assignee $IDENTITY_CLIENT_ID --scope $RG_ID --role Contributor
az role assignment create --assignee $IDENTITY_CLIENT_ID --scope $VNETID --role Contributor

# Validate Role Assignment
az role assignment list --assignee $IDENTITY_CLIENT_ID --all -o table

# Create AKS Cluster
az aks create \
  -g $RG \
  -n $AKS_CLUSTER_NAME \
  -l $LOCATION \
  --node-count $SYSTEM_NODE_COUNT \
  --node-vm-size $NODES_SKU \
  --network-plugin $NETWORK_PLUGIN \
  --network-policy $NETWORK_POLICY \
  --kubernetes-version $K8S_VERSION \
  --generate-ssh-keys \
  --service-cidr $SERVICE_CIDR \
  --dns-service-ip $DNS_IP \
  --vnet-subnet-id $AKS_VNET_SUBNET_ID \
  --enable-addons monitoring \
  --enable-managed-identity \
  --assign-identity $IDENTITY_ID \
  --nodepool-name $SYSTEM_POOL_NAME \
  --uptime-sla \
  --zones 1 2 3 \
  --node-osdisk-type Ephemeral \
  --node-osdisk-size 128


# Configure kubenet Access
az aks get-credentials -n $AKS_CLUSTER_NAME -g $RG

# Validate Nodes availability over Zones
kubectl get nodes
kubectl describe nodes -l agentpool=systempool | grep -i topology.kubernetes.io/zone