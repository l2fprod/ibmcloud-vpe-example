# Creating virtual private endpoints with terraform

This sample shows how to provision virtual private endpoint gateways from terraform.

![Architecture](./architecture.png)

## Deploy all resources

1. Copy `terraform.tfvars.template` to `terraform.tfvars`:
   ```
   cp terraform.tfvars.template terraform.tfvars
   ```
1. Edit `terraform.tfvars` to match your environment.
1. Make sure you have Terraform 0.14 installed. Use [`tfswitch`](https://tfswitch.warrensbox.com/) to easily move between Terraform versions.
1. Run terraform:
   ```
   terraform init
   terraform apply
   ```

## Test virtual private endpoints

The script `lookup.sh` iterates over all provisioned virtual server instances and does a `dig` to resolve the IP addresses of Redis, Object Storage and Key Protect.

In the first `apply`, VPE is not yet enabled, only cloud service endpoints are.

1. Run `./lookup.sh` to show how the virtual server instances are resolving endpoints.
   
   Here is an excerpt for the first instance:
   ```
   >>> vpe-example-instance-1 ->  ()
     >>> redis (123456.private.databases.appdomain.cloud)
       123456.private.databases.appdomain.cloud. 33 IN CNAME icd-prod-us-south-db-345003.us-south.serviceendpoint.cloud.ibm.com.
       icd-prod-us-south-db-345003.us-south.serviceendpoint.cloud.ibm.com. 88 IN A 166.9.16.209
       icd-prod-us-south-db-345003.us-south.serviceendpoint.cloud.ibm.com. 88 IN A 166.9.12.208
       icd-prod-us-south-db-345003.us-south.serviceendpoint.cloud.ibm.com. 88 IN A 166.9.15.93
     >>> cos (s3.direct.us-south.cloud-object-storage.appdomain.cloud)
       s3.direct.us-south.cloud-object-storage.appdomain.cloud. 147 IN	A 161.26.0.34
     >>> kms (private.us-south.kms.cloud.ibm.com)
       private.us-south.kms.cloud.ibm.com. 59 IN A	166.9.251.3
       private.us-south.kms.cloud.ibm.com. 59 IN A	166.9.250.227
       private.us-south.kms.cloud.ibm.com. 59 IN A	166.9.250.195
   ```
1. Edit `terraform.tfvars`, add `use_vpe = true` and save.
1. Apply `terraform` again:
   ```
   terraform apply
   ```
1. After a short while, run `./lookup.sh` again to see the VPE Reserved IPs allocated to the services.
 
   Here is an excerpt for the first instance:
   ```
   >>> vpe-example-instance-1
     >>> redis (123456.private.databases.appdomain.cloud)
       123456.private.databases.appdomain.cloud. 900 IN	A 10.20.10.19
     >>> cos (s3.direct.us-south.cloud-object-storage.appdomain.cloud)
       s3.direct.us-south.cloud-object-storage.appdomain.cloud. 900 IN	A 10.20.10.21
     >>> kms (private.us-south.kms.cloud.ibm.com)
       private.us-south.kms.cloud.ibm.com. 900	IN A	10.20.10.20
   ```
   Notice how the hostnames now resolve to private IPs within the VPC.

## Destroy all configuration

To destroy the environment:
   ```
   terraform destroy
   ```
