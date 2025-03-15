#!/bin/sh

kubectl delete ns control-plane-system
terraform init -upgrade
terraform plan -destroy -out terraform.destroy.plan
terraform apply terraform.destroy.plan
