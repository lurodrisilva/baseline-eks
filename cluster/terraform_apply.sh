#!/bin/sh

terraform init -upgrade
terraform plan -out terraform.apply.plan
terraform apply -auto-approve terraform.apply.plan
