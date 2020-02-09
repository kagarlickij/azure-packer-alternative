| Build status  | License |
| ------------- | ------------- |
| [![Build Status](https://dev.azure.com/kagarlickij/azure-vm-packer-ansible/_apis/build/status/azure-vm-packer-ansible-ci?branchName=master)](https://dev.azure.com/kagarlickij/azure-vm-packer-ansible/_build/latest?definitionId=17&branchName=master)  | [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)  |

# Task
## Packer (temporary) virtual machine:
1. Must be placed in pre-defined Azure VNet's Subnet (instead of default temporary VNet and Subnet created by Packer)
2. Must have Private IP only (instead of defaults with both Private ans Public IPs)
3. Must be set by Ansible (for demo purposes Ansible creates `C:\build_config.txt`) using variables from:
  * `var1` from Azure DevOps Variable group `ansible-build-common` as regular variable
  * `var2` from Azure DevOps Variable group `ansible-build-common` as secret variable
  * `var3` from Azure DevOps Variable group `ansible-build-vm*` as regular variable
  * `var4` from Azure DevOps Variable group `ansible-build-vm*` as secret variable

## Production (resulting) virtual machine:
1. Must be placed in pre-defined Azure VNet's Subnet
2. Must have Private IP only
3. Must be set by Ansible (for demo purposes Ansible creates `C:\deploy_config.txt`) using variables from:
  * `var1` from Azure DevOps Variable group `ansible-deploy-common` as regular variable
  * `var2` from Azure DevOps Variable group `ansible-deploy-common` as secret variable
  * `var3` from Azure DevOps Variable group `ansible-deploy-vm*` as regular variable
  * `var4` from Azure DevOps Variable group `ansible-deploy-vm*` as secret variable
  * `var5` **for VM2 and VM3 only:** IP address of VM1 from Azure DevOps pipeline
  * `var6` **for VM3 only:** IP address of VM2 from Azure DevOps pipeline

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

# Ansible provisioner
Ansible provisioner for Packer has a number of issues:
1. [Packer's Ansible connection plugin fails for Windows](https://stackoverflow.com/questions/59599834/packers-ansible-connection-plugin-fails-for-windows)
2. [Packer's {{ .WinRMPassword }} var is empty for azure-arm builder](https://stackoverflow.com/questions/59624603/packers-winrmpassword-var-is-empty-for-azure-arm-builder)

Because of those two issues:
1. Ansible is executed as "shell-local" provisioner
2. Another "shell-local" provisioner creates user for Ansible

# Deploy approval
Environment in ADOS Pipelines will be created automatically by Pipeline  
[To Set Deploy approval open `Approvals and checks` params of Environment and add Approval](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass)  
[Deploy notifications don't work in ADOS yet](https://stackoverflow.com/questions/59702813/azure-devops-doesnt-send-deployment-approval/)  

# Azure DevOps pipeline
## Production vs Pull request verification
Pipeline supports Pull requests verification (on Pull request to `master` branch) and VM image build and "production" deploy (on commit to `master` branch)  
Pull request verification (PRV) builds and deploys image to temporary environment  
If PRV Build & Deploy are successful, code snapshot is marked as valid for merging and tmp environment is deleted  
If PRV Build & Deploy failed code snapshot is marked as invalid and tmp environment is not deleted for manual investigation  
## Agent and network
Azure DevOps agent must have access to the virtual network that is used for VM image build  
Azure DevOps agents are executed in Docker [kagarlickij/packer-ansible-azure-docker-runtime:3.1.0](https://hub.docker.com/repository/registry-1.docker.io/kagarlickij/packer-ansible-azure-docker-runtime/builds/31d492d9-4d3b-4366-9add-d837c1d757d6) runtime with preinstalled Packer, Ansible, Azure CLI and necessary Python packages  
Azure DevOps agents can be started on VM on system startup: `@reboot /root/ados-agents-start.sh` in `crontab -e`  
`ados-agents-start.sh` script:
```
#!/bin/bash

for run in {1..5}
do
  docker run -d -e VSTS_ACCOUNT='kagarlickij' -e VSTS_POOL='Self-Hosted-Containers' -e VSTS_TOKEN='a***q' kagarlickij/packer-ansible-azure-docker-runtime:3.1.0 > /dev/null 2>&1
done
```

There are a few ways to run builds in parallel, but all of them don't work:  
1. Use multiple `builders` in template.json. It [doesn't work](https://stackoverflow.com/questions/59864732/packer-dedicated-provisioners-for-builders) because each VM must use dedicated provisioner
2. Build the same template on multiple agents (VMs or Docker containers) in [parallel](https://docs.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops) always [fails](https://stackoverflow.com/questions/59864317/packer-azure-arm-fails-when-running-in-parallel )  
## Templates
Pipeline has some repeating steps which are moved to `./templates` to avoid code duplication  
Templates are not plugins so some pieces (e.g network settings) are "hardcoded"  
Template types are Job (for deploy) and Step (for all other) not because of the most suitable kind but because [templates can not be used as dependency for other jobs/stages/etc](https://stackoverflow.com/questions/59937679/azure-devops-template-as-a-dependency-for-a-job?noredirect=1#comment105997940_59937679)  

# Manual execution (CLI on local machine)
Deprecated because of complexity with variables

# Extra
More information available in [Packer](https://www.packer.io/docs/builders/azure-arm.html) and [Microsoft](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer#create-azure-credentials) docks

# Required input (Azure DevOps variable groups)
## azure-connection
| Name | Value | Type | Comment |
|--|--|--|--|
| azureClientId | `********` | Secret | [azure_client_id](https://www.packer.io/docs/builders/azure-arm.html#azure_client_id) The Active Directory service principal associated with builder |
| azureClientSecret | `********` | Secret | [azure_client_secret](https://www.packer.io/docs/builders/azure-arm.html#azure_client_secret) The password or secret for service principal |
| azureSubscription | `Pay-As-You-Go (b31bc8ae-8938-41f1-b0b2-f707d811d596)` | Regular | Subscription Name under which the build will be performed |
| azureSubscriptionId | `b31bc8ae-8938-41f1-b0b2-f707d811d596` | Regular | [azure_subscription_id](https://www.packer.io/docs/builders/azure-arm.html#azure_subscription_id) Subscription Id under which the build will be performed |
| azureTenantId | `cc3dd0a3-a052-458b-bf22-9f1883bf2105` | Regular | [azure_tenant_id](https://www.packer.io/docs/builders/azure-arm.html#azure_tenant_id) The Active Directory tenant identifier with which `azure_client_id` and `azure_subscription_id` are associated |

## azure-packer-resources
| Name | Value | Type | Comment |
|--|--|--|--|
| packerBuildResourceGroupName | `packer-build-rg` | Regular | [packerBuildResourceGroupName](https://www.packer.io/docs/builders/azure-arm.html#build_resource_group_name) Specify an existing resource group to run the build in |
| packerImagesResourceGroupName | `packer-images-rg` | Regular | [packerImagesResourceGroupName](https://www.packer.io/docs/builders/azure-arm.html#packer_images_resource_group_name) Specify the managed image resource group name where the result of the Packer build will be saved |
| packerVnetName | `packer-vnet` | Regular | [packerVnetName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_name) option enables private communication with the VM, no public IP address is used or provisioned |
| packerVnetResourceGroupName | `packer-vnet-rg` | Regular | [packerVnetResourceGroupName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_resource_group_name) option specify the resource group containing the virtual network |
| packerVnetSubnetName | `packer-vnet-subnet1` | Regular | [packerVnetSubnetName](https://www.packer.io/docs/builders/azure-arm.html#packer_vnet_subnet_name) option specify Subnet from `packer_vnet_name` the virtual network |

## azure-prod-network
| Name | Value | Type | Comment |
|--|--|--|--|
| prodVmRegion | `East US` | Regular | Location of the VNet |
| prodVnetName | `prod-vnet` | Regular | Name of the VNet |
| prodVnetResourceGroupName | `prod-vnet-rg` | Regular | Name of resource group that contains VNet |
| prodVnetSubnetName | `prod-vnet-subnet1` | Regular | The name of the subnet |

## azure-prod-common
| Name | Value | Type | Comment |
|--|--|--|--|
| environment_name | `TST` | Regular | env(else DEV PRD..) |
| location | `AW` | Regular | location |
| project_name | `ERE` | Regular | project name |

## azure-prod-vm1
| Name | Value | Type | Comment |
|--|--|--|--|
| prodVm1KvName | `prod-vm1-kv` | Regular | aka `--disk-encryption-keyvault` Name or ID of the key vault containing the key encryption key used to encrypt the disk encryption key |
| prodVm1Name | `prod-vm1` | Regular | aka `--name` The name of the Virtual Machine **AND** [packerImageName](https://www.packer.io/docs/builders/azure-arm.html#packer_image_name) The managed image name where the result of the Packer build will be saved |
| prodVm1ResourceGroupName | `prod-vm1-rg` | Regular | aka `--resource-group` Name of resource group |
| prodVm1Size | `Standard_DS2_v2` | Regular | aka `--size` The VM size to be created. See https://azure.microsoft.com/pricing/details/virtual-machines/ for size info |
| prodVm1ServiceName | `ETL` | Regular | service name |
| prodVm1InstanceNumber | `01` | Regular | instance number |

## azure-prod-vm2
| Name | Value | Type | Comment |
|--|--|--|--|
| prodVm2KvName | `prod-vm2-kv` | Regular | aka `--disk-encryption-keyvault` Name or ID of the key vault containing the key encryption key used to encrypt the disk encryption key |
| prodVm2Name | `prod-vm2` | Regular | aka `--name` The name of the Virtual Machine **AND** [packerImageName](https://www.packer.io/docs/builders/azure-arm.html#packer_image_name) The managed image name where the result of the Packer build will be saved |
| prodVm2ResourceGroupName | `prod-vm2-rg` | Regular | aka `--resource-group` Name of resource group |
| prodVm2Size | `Standard_DS2_v2` | Regular | aka `--size` The VM size to be created. See https://azure.microsoft.com/pricing/details/virtual-machines/ for size info |
| prodVm2ServiceName | `INT` | Regular | service name |
| prodVm2InstanceNumber | `01` | Regular | instance number |

## azure-prod-vm3
| Name | Value | Type | Comment |
|--|--|--|--|
| prodVm3KvName | `prod-vm3-kv` | Regular | aka `--disk-encryption-keyvault` Name or ID of the key vault containing the key encryption key used to encrypt the disk encryption key |
| prodVm3Name | `prod-vm3` | Regular | aka `--name` The name of the Virtual Machine **AND** [packerImageName](https://www.packer.io/docs/builders/azure-arm.html#packer_image_name) The managed image name where the result of the Packer build will be saved |
| prodVm3ResourceGroupName | `prod-vm3-rg` | Regular | aka `--resource-group` Name of resource group |
| prodVm3Size | `Standard_DS2_v2` | Regular | aka `--size` The VM size to be created. See https://azure.microsoft.com/pricing/details/virtual-machines/ for size info |
| prodVm3ServiceName | `WEB` | Regular | service name |
| prodVm3InstanceNumber | `01` | Regular | instance number |

## azure-tags
| Name | Value | Type | Comment |
|--|--|--|--|
| environment | `sbx` | Regular | [Tags](https://www.packer.io/docs/builders/azure-arm.html#azure_tags) are applied to every resource deployed, i.e. Resource Group, VM, NIC, etc. |
| project | `ere` | Regular | [Tags](https://www.packer.io/docs/builders/azure-arm.html#azure_tags) are applied to every resource deployed, i.e. Resource Group, VM, NIC, etc. |

## ansible-build-common
| Name | Value | Type | Comment |
|--|--|--|--|
| var1 | `sample-value-of-ansible-build-common-var1` | Regular | Just a sandbox example |
| var2 | `********` | Secret | Just a sandbox example |

## ansible-build-vm1
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-build-vm1-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-build-vm2
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-build-vm2-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-build-vm3
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-build-vm3-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-deploy-common
| Name | Value | Type | Comment |
|--|--|--|--|
| var1 | `sample-value-of-ansible-deploy-common-var1` | Regular | Just a sandbox example |
| var2 | `********` | Secret | Just a sandbox example |

## ansible-deploy-vm1
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-deploy-vm1-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-deploy-vm2
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-deploy-vm2-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-deploy-vm3
| Name | Value | Type | Comment |
|--|--|--|--|
| var3 | `sample-value-of-ansible-deploy-vm3-var3` | Regular | Just a sandbox example |
| var4 | `********` | Secret | Just a sandbox example |

## ansible-windows-creds
| Name | Value | Type | Comment |
|--|--|--|--|
| ansibleUser | `ansible` | Regular | Windows user created for Ansible |
| ansibleUserPass | `********` | Secret | Windows user password created for Ansible |

# Known issues
When Packer builds Windows on Azure it falls often enough because of [WinRM timeout](https://stackoverflow.com/questions/59990155/packer-vs-vm-on-azure-timeout-waiting-for-winrm)  
As a solution, Packer is replaced with Azure CLI that can create VM, setup WinRM, execute Ansible, create image from VM  
