# resource "aws_efs_file_system" "eks_efs" {
#   creation_token = "eks-efs"
#   encrypted      = true

#   tags = {
#     Name = "EKS-EFS"
#   }
# }

# resource "aws_efs_mount_target" "eks_efs_mount" {
#   count           = length(module.vpc.private_subnets)
#   file_system_id  = aws_efs_file_system.eks_efs.id
#   subnet_id       = module.vpc.private_subnets[count.index]
#   security_groups = [aws_security_group.efs.id]
# }

# resource "aws_security_group" "efs" {
#   name        = "efs-sg"
#   description = "Allow EFS inbound traffic"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     description = "NFS"
#     from_port   = 2049
#     to_port     = 2049
#     protocol    = "tcp"
#     cidr_blocks = [module.vpc.vpc_cidr_block]
#   }
# }
