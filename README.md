# tf-gcp-infra 

## Install gcloud CLI
### Make sure to install python3 (3.8 to 3.12)
### Download the GCloud CLI binary for your OS
### Extract the binary to any location and run the script -> ./google-cloud-sdk/install.sh
### Initialize the GCLOUD CLI -> ./google-cloud-sdk/bin/gcloud init
### sign in to your GCP console from the browser pop up
### make sure to enable GCP API Services and "Google Compute Engine Service"


##  Terraform commands
### "terraform init" from the module directory
### "terraform validate" to check if tf is working   
### "terraform plan -var-file="../../dev.auto.tfvars" to generate plan from tfvars file
### terraform apply -var-file="../../dev.auto.tfvars" to apply the generate the infrastrucutre
### terraform apply -var-file="../../dev.auto.tfvars" to destroy the infra
