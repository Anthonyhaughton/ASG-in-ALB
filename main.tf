terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Configure the AWS Provider
# provider "aws" {
#  region                   = "us-east-1"
#  shared_credentials_files = ["~/.aws/credentials"]
#  profile                  = "vscode"

# This is commented out for Jenkins. If not usuing Jenkins this is needed.
#}

module "dev-vpc" {
  source      = "./modules/vpc"
  environment = "dev"
  vpc_cidr    = "10.10.0.0/16"
}

terraform {
  backend "s3" {   
   bucket = "loadbalancing-tfstate"
   key    = "loadbalance-state" #name of the S3 object that will store the state file
   region = "us-east-1"
   
   # 3/18/2024: I recently got a new PC so I was setting up terraform/aws and was was stuck with "terraform init" failing. The error 
   # "Error: No valid credential sources found". The solution was in "~/.aws/credentials" I was missing the [default] block
   # with the access and secret key. No idea why it needs to be there twice..
 }
}