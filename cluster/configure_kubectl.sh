#!/bin/sh

#aws eks --region $(terraform output -raw region) update-kubeconfig \
#    --name $(terraform output -raw cluster_name)

$(terraform output -raw configure_kubectl)