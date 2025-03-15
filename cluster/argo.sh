#!/bin/sh

export ARGOCD_SERVER=$(kubectl get svc argocd-server -n control-plane-system --output=jsonpath='{.status.loadBalancer.ingress[0].hostname}')

export ARGOCD_PASSWORD=$(kubectl -n control-plane-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASSWORD --insecure

echo $ARGOCD_SERVER
echo $ARGOCD_PASSWORD
