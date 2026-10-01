# 1. Generate an RSA Private Key locally
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Register Public Key with AWS
resource "aws_key_pair" "bastion" {
  key_name   = "${var.environment}-bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh
}

# 3. Save Private Key locally for SSH access
resource "local_file" "private_key" {
  content         = tls_private_key.bastion_key.private_key_pem
  filename        = "${path.module}/bastion-key.pem"
  file_permission = "0600"
}

# 4. Security Group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  name        = "${var.environment}-bastion-sg"
  description = "Allow inbound SSH traffic to Bastion Host"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-bastion-sg"
  }
}
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}
# 5. Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 6. EC2 Bastion Instance
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = module.network.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true

  tags = {
    Name        = "${var.environment}-bastion-host"
    Environment = var.environment
  }
} # ------------------------------------------------------------------------------# STEP 20: EC2 Bastion Host Deployment# ------------------------------------------------------------------------------resource "aws_instance" "bastion" {  ami                         = data.aws_ami.amazon_linux_2023.id  instance_type               = "t3.micro"  subnet_id                   = module.network.public_subnet_ids[0]  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]  key_name                    = aws_key_pair.bastion.key_name  associate_public_ip_address = true  tags = {    Name        = "${var.environment}-bastion-host"    Environment = var.environment  }}
# ------------------------------------------------------------------------------
# STEP 21: Time Provider (Wait 45s for SSH Daemon to start)
# ------------------------------------------------------------------------------
# EC2 reports "Running" instantly, but SSH takes ~30-40s to boot up.
resource "time_sleep" "wait_45_seconds" {
  depends_on      = [aws_instance.bastion]
  create_duration = "45s"
}

# ------------------------------------------------------------------------------
# STEPS 22, 23 & 24: Null Resource for Provisioners
# ------------------------------------------------------------------------------
resource "null_resource" "bastion_provisioner" {
  # STEP 22: Depend explicitly on time_sleep so SSH is guaranteed to be ready
  depends_on = [time_sleep.wait_45_seconds]

  # Re-run provisioners if the instance ID changes
  triggers = {
    instance_id = aws_instance.bastion.id
  }

  # Connection settings for remote-exec
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.bastion_key.private_key_pem
    host        = aws_instance.bastion.public_ip
  }

  # STEP 23: remote-exec provisioner (SSHs into Bastion and installs packages)
  provisioner "remote-exec" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y jq git htop",
      "echo 'Bastion host initialized successfully' > ~/setup.log"
    ]
  }

  # STEP 24: local-exec provisioner (Writes Bastion IP to a local config file)
  provisioner "local-exec" {
    command = "echo 'BASTION_IP=${aws_instance.bastion.public_ip}' > ${path.module}/bastion_info.env"
  }
}