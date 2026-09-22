data "aws_availability_zones" "available" {
  state = "available"
}

# Auto-detects the latest Ubuntu 24.04 LTS AMI for whatever region is set,
# via Canonical's own officially documented SSM parameter - this resolves
# directly to a real AMI ID and never depends on guessing an AMI name
# pattern (which changed between Ubuntu releases, e.g. hvm-ssd -> hvm-ssd-gp3
# starting with 24.04). Override with var.ami_id if a specific pinned AMI is
# needed instead.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.ubuntu_ami.value
}

resource "aws_vpc" "coolify" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "coolify-prod-vpc" }
}

resource "aws_internet_gateway" "coolify" {
  vpc_id = aws_vpc.coolify.id
  tags   = { Name = "coolify-prod-igw" }
}

# --- Public subnets: EC2 #1 (control plane) + EC2 #2/#3 (runtime), each with an Elastic IP ---
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.coolify.id
  cidr_block               = var.public_subnet_cidrs[count.index]
  availability_zone        = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch  = true
  tags = { Name = "coolify-public-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.coolify.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coolify.id
  }
  tags = { Name = "coolify-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private subnets: RDS + ElastiCache only, no public IPs, no NAT needed (no outbound internet required) ---
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.coolify.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "coolify-private-${count.index + 1}" }
}
