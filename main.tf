resource "aws_vpc" "primary_vpc" {
  cidr_block       = var.primary_vpc_cidr_block
  provider =aws.primary
  enable_dns_support =true
  enable_dns_hostnames=true

  tags = {
    Name = "Primary VPC- ${var.primary_region}"
  }
}


#secondary vpc

resource "aws_vpc" "secondary_vpc" {
  cidr_block       = var.secondary_vpc_cidr_block
  provider =aws.secondary
  enable_dns_support =true
  enable_dns_hostnames=true

  tags = {
    Name = "Secondary VPC- ${var.secondary_region}"
  }
}

resource "aws_subnet" "primary_subnet" {
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = var.primary_subnet_cidr_block
  availability_zone = data.aws_availability_zones.primary.names[0]
  provider =aws.primary
  map_public_ip_on_launch = true

  tags = {
    Name = "Primary Subnet- ${var.primary_region}"
    Environment = var.environment
  }
}

resource "aws_subnet" "secondary_subnet" {
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = var.secondary_subnet_cidr_block
  availability_zone = data.aws_availability_zones.secondary.names[0]
  provider =aws.secondary
  map_public_ip_on_launch = true

  tags = {
    Name = "Secondary Subnet- ${var.secondary_region}"
    Environment = var.environment
  }
}


# internet Gateway for primary vpc

resource "aws_internet_gateway" "primary_igw" {
  vpc_id = aws_vpc.primary_vpc.id
  provider =aws.primary

  tags = {
    Name = "Primary IGW- ${var.primary_region}"
    Environment = var.environment
  }
}

# internet Gateway for secondary vpc

resource "aws_internet_gateway" "secondary_igw" {
  vpc_id = aws_vpc.secondary_vpc.id
  provider =aws.secondary

  tags = {
    Name = "Secondary IGW- ${var.secondary_region}"
    Environment = var.environment
  }
}


# Route table for Primary VPC
resource "aws_route_table" "primary_rt" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }

  tags = {
    Name        = "Primary-Route-Table"
    Environment = var.environment
  }
}

# Route table for Secondary VPC
resource "aws_route_table" "secondary_rt" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }

  tags = {
    Name        = "Secondary-Route-Table"
    Environment = var.environment
  }
}


#route table association for primary vpc

resource "aws_route_table_association" "primary_rta"{
    provider = aws.primary
    subnet_id=aws_subnet.primary_subnet.id
    route_table_id=aws_route_table.primary_rt.id
}

#route table association for secondary vpc

resource "aws_route_table_association" "secondary_rta"{
    provider = aws.secondary
    subnet_id=aws_subnet.secondary_subnet.id
    route_table_id=aws_route_table.secondary_rt.id
}


#vpc-peer connection

resource"aws_vpc_peering_connection" "primary_to_secondary"{
    provider=aws.primary
    vpc_id=aws_vpc.primary_vpc.id
    peer_vpc_id=aws_vpc.secondary_vpc.id
    auto_accept=false
    peer_region=var.secondary_region

    tags={
        Name="Primary-to-Secondary-Peering"
        Environment=var.environment
        Side="Requester"
    }
}

resource "aws_vpc_peering_connection_accepter" "secondary_accepter"{
    provider=aws.secondary
    vpc_peering_connection_id=aws_vpc_peering_connection.primary_to_secondary.id
    auto_accept=true

    tags={
        Name="Secondary-to-Primary-Peering"
        Environment=var.environment
        Side="Accepter"
    }
}

resource "aws_route" "primary_to_secondary_route" {
  provider = aws.primary
  route_table_id         = aws_route_table.primary_rt.id
  destination_cidr_block = var.secondary_vpc_cidr_block
 
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  depends_on=[aws_vpc_peering_connection_accepter.secondary_accepter]
}

resource "aws_route" "secondary_to_primary_route" {
  provider = aws.secondary
  route_table_id         = aws_route_table.secondary_rt.id
  destination_cidr_block = var.primary_vpc_cidr_block
 
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  depends_on=[aws_vpc_peering_connection_accepter.secondary_accepter]
}


# Security Group for Primary VPC EC2 instance
resource "aws_security_group" "primary_sg" {
  provider    = aws.primary
  name        = "primary-vpc-sg"
  description = "Security group for Primary VPC instance"
  vpc_id      = aws_vpc.primary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Secondary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_cidr_block]
  }

  ingress {
    description = "All traffic from Secondary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Primary-VPC-SG"
    Environment = var.environment
  }
}

# Security Group for Secondary VPC EC2 instance
resource "aws_security_group" "secondary_sg" {
  provider    = aws.secondary
  name        = "secondary-vpc-sg"
  description = "Security group for Secondary VPC instance"
  vpc_id      = aws_vpc.secondary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Primary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_cidr_block]
  }

  ingress {
    description = "All traffic from Primary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Secondary-VPC-SG"
    Environment = var.environment
  }
}

# EC2 Instance in Primary VPC
resource "aws_instance" "primary_instance" {
  provider               = aws.primary
  ami                    = data.aws_ami.primary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.primary_subnet.id
  vpc_security_group_ids = [aws_security_group.primary_sg.id]
  key_name               = var.primary_key_name

  user_data = local.primary_user_data

  tags = {
    Name        = "Primary-VPC-Instance"
    Environment = var.environment
    Region      = var.primary_region
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}

# EC2 Instance in Secondary VPC
resource "aws_instance" "secondary_instance" {
  provider               = aws.secondary
  ami                    = data.aws_ami.secondary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.secondary_subnet.id
  vpc_security_group_ids = [aws_security_group.secondary_sg.id]
  key_name               = var.secondary_key_name

  user_data = local.secondary_user_data

  tags = {
    Name        = "Secondary-VPC-Instance"
    Environment = var.environment
    Region      = var.secondary_region
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]

}