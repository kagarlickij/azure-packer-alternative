| Build status  | License |
| ------------- | ------------- |
| [![Build Status](https://dev.azure.com/kagarlickij/packer-azure/_apis/build/status/packer-azure-ci?branchName=master)](https://dev.azure.com/kagarlickij/packer-azure/_build/latest?definitionId=8&branchName=master)  | [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)  |

# Task
## Packer temporary virtual machine:
1. Must be placed in pre-defined Azure VNet's Subnet (instead of default temporary VNet and Subnet created by Packer)
2. Must have Private IP only (instead of defaults with Public IP)
3. Must be set by Ansible using variables from:
  * Packer
  * Ansible
  * Consul
  * Vault

## Production (resulting) virtual machine:
1. Must be placed in pre-defined Azure VNet's Subnet
2. Must have Private IP only
3. Must be set by Ansible

# Solution
![diagram](diagram.png)

# Packer Authentication for Azure
The Packer Azure builders provide a couple of ways to authenticate to Azure:
1. Azure Active Directory interactive login
2. Azure Managed Identity
3. Azure Active Directory Service Principal

Azure DevOps Service Connection for Azure doesn't work with Packer, so:
For manual (CLI) execution "Azure Active Directory interactive login" method is recommended (see example below)
For execution in Azure DevOps pipeline "Azure Active Directory Service Principal" is used (see pipeline logs from "Build status" badge)

# Required input
## Tags
[azure_tags](https://www.packer.io/docs/builders/azure-arm.html#azure_tags) Tags are applied to every resource deployed by a Packer build, i.e. Resource Group, VM, NIC, etc.  
In this example two tags are used:
* `project`
* `environment`

## Azure Active Directory Service Principal
[azure_client_id](https://www.packer.io/docs/builders/azure-arm.html#azure_client_id) The Active Directory service principal associated with builder  
[azure_client_secret](https://www.packer.io/docs/builders/azure-arm.html#azure_client_secret) The password or secret for service principal  
[azure_tenant_id](https://www.packer.io/docs/builders/azure-arm.html#azure_tenant_id) The Active Directory tenant identifier with which `azure_client_id` and `azure_subscription_id` are associated  
[azure_subscription_id](https://www.packer.io/docs/builders/azure-arm.html#azure_subscription_id) Subscription under which the build will be performed  

More information available in [Packer](https://www.packer.io/docs/builders/azure-arm.html) and [Microsoft](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer#create-azure-credentials) docks

## Packer network-related options
[packerVnetName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_name) option enables private communication with the VM, no public IP address is used or provisioned  
[packerVnetResourceGroupName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_resource_group_name) option specify the resource group containing the virtual network  
[packerVnetSubnetName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_subnet_name) option specify Subnet from `packer_vnet_name` the virtual network  

## Packer managed image-related options
[packerImagesResourceGroupName](https://www.packer.io/docs/builders/azure-arm.html#packer_images_resource_group_name) Specify the managed image resource group name where the result of the Packer build will be saved  
[packerImageName](https://www.packer.io/docs/builders/azure-arm.html#packer_image_name) Specify the managed image name where the result of the Packer build will be saved

## Production (resulting) virtual machine options
`prodVmResourceGroupName` aka `--resource-group` Name of resource group  
`prodVmName` aka `--name` The name of the Virtual Machine  
`prodVmRegion` aka `--location` Location  
`packerImageId` aka `--image` The name of the operating system image  

[Documentation](https://docs.microsoft.com/en-us/cli/azure/vm?view=azure-cli-latest#az-vm-create)

## Production (resulting) virtual machine network-related options
`prodVnetResourceGroupName` Name of resource group that contains VNet  
`prodVnetName` Name of the VNet  
`prodVnetSubnetName` The name of the subnet  

[Documentation](https://docs.microsoft.com/en-us/cli/azure/vm?view=azure-cli-latest#az-vm-create)

# Ansible provisioner
Ansible provisioner for Packer has a number of issues:
1. [Packer's Ansible connection plugin fails for Windows](https://stackoverflow.com/questions/59599834/packers-ansible-connection-plugin-fails-for-windows)
2. [Packer's {{ .WinRMPassword }} var is empty for azure-arm builder](https://stackoverflow.com/questions/59624603/packers-winrmpassword-var-is-empty-for-azure-arm-builder)

Because of those two issues:
1. Ansible is executed as "shell-local" provisioner
2. Another "shell-local" provisioner creates user for Ansible and deletes this user when Ansible execution is complete

# Deploy approval
Environment in ADOS Pipelines will be created automatically by Pipeline  
[To Set Deploy approval open `Approvals and checks` params of Environment and add Approval](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass)  
[Deploy notifications don't work in ADOS yet](https://stackoverflow.com/questions/59702813/azure-devops-doesnt-send-deployment-approval/)  

# Execution environment
## Azure DevOps
Azure DevOps [pipeline](pipeline.yaml) is recommended way to execute Packer  
Pipeline supports Pull requests verification and VM image build based on commit to mainline (`master` branch)  
Azure DevOps agent must have access to the virtual network that is used for VM image build  
Azure DevOps pipeline is executed in Docker [packer-ansible-docker-runtime](https://hub.docker.com/repository/docker/kagarlickij/packer-ansible-runtime/) runtime with preinstalled Packer, Ansible and necessary Python packages

## Build manual execution (CLI on local machine)
If Packer is executed locally, variables must be specified as params, e.g.:  
```
export VAULT_ADDR='http://3.88.239.92:8200'
export VAULT_DEV_ROOT_TOKEN_ID='s.Bf***hg'
export CONSUL_HTTP_ADDR='http://54.226.159.29:8500'
export ANSIBLE_PASS='***'

packer build -force \
    -var "project=ere" \
    -var "environment=sbx" \
    -var "azure_subscription_id=b31bc8ae-8938-41f1-b0b2-f707d811d596" \
    -var "packer_vnet_resource_group_name=packer-vnet-rg" \
    -var "packer_vnet_name=packer-vnet" \
    -var "packer_vnet_subnet_name=packer-vnet-subnet1" \
    -var "packer_images_resource_group_name=packer-images-rg" \
    -var "packer_image_name=packer-image" \
    -var "ansible_user=ansible" \
    -var "ansible_user_password=$ANSIBLE_PASS" \
    ./template.json
```

## Deploy manual execution (CLI on local machine)
```
export ANSIBLE_PASS='***'

az vm create --resource-group 'prod-vm-rg' --name 'prod-vm' --image '/subscriptions/b31bc8ae-8938-41f1-b0b2-f707d811d596/resourceGroups/packer-images-rg/providers/Microsoft.Compute/images/packer-image' --location 'East US' --subnet '/subscriptions/b31bc8ae-8938-41f1-b0b2-f707d811d596/resourceGroups/prod-vnet-rg/providers/Microsoft.Network/virtualNetworks/prod-vnet/subnets/prod-vnet-subnet1' --public-ip-address "" --admin-username 'ansible' --admin-password $ANSIBLE_PASS

az vm run-command invoke --command-id RunPowerShellScript --resource-group 'prod-vm-rg' --name 'prod-vm' --scripts 'Invoke-WebRequest https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 -OutFile ConfigureRemotingForAnsible.ps1; .\ConfigureRemotingForAnsible.ps1 -ForceNewSSLCert'

VM_PR_IP=$(az vm list-ip-addresses --resource-group 'prod-vm-rg' --name 'prod-vm' --query "[].virtualMachine.network.privateIpAddresses[]" --output tsv)

printf "[all]\n$VM_PR_IP" > hosts

ansible-playbook -vvvv -i hosts ansible/release-playbook.yml --extra-vars="ansible_user=ansible ansible_password=$ANSIBLE_PASS ansible_connection=winrm ansible_winrm_server_cert_validation=ignore ansible_shell_type=powershell ansible_shell_executable=None"
```
