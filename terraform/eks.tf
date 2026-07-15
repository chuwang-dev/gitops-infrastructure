# ==========================================
# 1. IAM ROLE FOR THE KUBERNETES CONTROL PLANE
# ==========================================
resource "aws_iam_role" "eks_cluster" {
  name = "gitops-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the core EKS policy to the cluster IAM role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ==========================================
# 2. THE EKS CLUSTER CONTROL PLANE
# ==========================================
resource "aws_eks_cluster" "main" {
  name     = "gitops-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.30" 

  vpc_config {
    # Places the cluster control plane across both public subnets we created
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id
    ]
  }

  # Ensure IAM Role permissions are created before the EKS Cluster (FIXED REFERENCE)
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_policy_nodes,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}

# ==========================================
# 3. IAM ROLE FOR THE WORKER NODES (EC2)
# ==========================================
resource "aws_iam_role" "eks_nodes" {
  name = "gitops-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Mandatory policy 1 for worker nodes to talk to EKS
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_nodes" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

# Mandatory policy 2 for managing container networking (CNI)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

# Mandatory policy 3 to pull application images from AWS ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# ==========================================
# 4. THE EKS NODE GROUP (UPDATED FOR FREE TIER)
# ==========================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gitops-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  # CHANGED: Swapped t3.medium out for a free-tier eligible instance type
  instance_types = ["t3.micro"] 

  # CHANGED: Increased the minimum and desired count to compensate for smaller instances
  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy_nodes,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]
}
