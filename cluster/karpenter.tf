# # Karpenter default EC2NodeClass and NodePool

resource "kubectl_manifest" "karpenter_default_ec2_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "${local.node_iam_role_name}"
  amiFamily: Bottlerocket
  amiSelectorTerms: 
  # - alias: al2@latest
  - alias: bottlerocket@latest
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${local.name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${local.name}
  tags:
    IntentLabel: apps
    KarpenterNodePoolName: default
    NodeType: default
    type: algo-trading-apps
    karpenter.sh/discovery: ${local.name}
    project: control-plane-project
YAML
  depends_on = [
    module.eks.cluster,
    module.eks_blueprints_addons.karpenter,
  ]
}

resource "kubectl_manifest" "karpenter_default_node_pool" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default 
spec:  
  template:
    metadata:
      labels:
        type: algo-trading-apps
        vpc.amazonaws.com/has-trunk-attached: "false"
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"] # on-demand or spot
        - key: "node.kubernetes.io/instance-type"
          operator: In
          # values: ["t3a.small"]
          values: ["t4g.large"]
      nodeClassRef:
        name: default
        group: karpenter.k8s.aws
        kind: EC2NodeClass
      # kubelet:
      #   containerRuntime: containerd
      #   systemReserved:
      #     cpu: 100m
      #     memory: 320Mi
  limits:
    cpu: 20
    memory: 40Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 2m
    
YAML
  depends_on = [
    module.eks.cluster,
    module.eks_blueprints_addons.karpenter,
    kubectl_manifest.karpenter_default_ec2_node_class,
  ]
}