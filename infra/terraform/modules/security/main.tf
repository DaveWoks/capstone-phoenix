resource "aws_security_group" "k3s" {
  name        = "${var.project_name}-k3s"
  description = "Security group for k3s cluster"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-k3s-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.k3s.id
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.ssh_cidr
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.k3s.id
  description       = "HTTP"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.k3s.id
  description       = "HTTPS"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "k8s_api" {
  security_group_id = aws_security_group.k3s.id
  description       = "Kubernetes API"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
}

resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id = aws_security_group.k3s.id
  description       = "Kubelet API"
  from_port         = 10250
  to_port           = 10250
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
}

resource "aws_vpc_security_group_ingress_rule" "flannel_vxlan" {
  security_group_id = aws_security_group.k3s.id
  description       = "Flannel VXLAN"
  from_port         = 8472
  to_port           = 8472
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.k3s.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "wireguard" {
  security_group_id = aws_security_group.k3s.id
  description       = "Flannel WireGuard"
  from_port         = 51820
  to_port           = 51820
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
}

resource "aws_vpc_security_group_ingress_rule" "k8s_api_admin" {
  security_group_id = aws_security_group.k3s.id
  description       = "Kubernetes API admin access from admin IP"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "102.91.135.234/32"
}

