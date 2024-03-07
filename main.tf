resource "aws_vpc" "dg_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    name = "dev"
  }
}

resource "aws_subnet" "dg_public_subnet" {
  vpc_id                  = aws_vpc.dg_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    name = "dev-pubic"
  }
}

resource "aws_internet_gateway" "dg_internet_gateway" {
  vpc_id = aws_vpc.dg_vpc.id

  tags = {
    name = "dev_igw"
  }
}

resource "aws_route_table" "dg_public_rt" {
  vpc_id = aws_vpc.dg_vpc.id

  tags = {
    name = "dev_public_rt"
  }
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.dg_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.dg_internet_gateway.id
}

resource "aws_route_table_association" "dg_public_assoc" {
  subnet_id      = aws_subnet.dg_public_subnet.id
  route_table_id = aws_route_table.dg_public_rt.id
}

locals {
  ports_in = [
    443,
    80,
    22
  ]
  ports_out = [
    0
  ]
}

resource "aws_security_group" "dg_allow_web" {
  name        = "allow_web"
  description = "Allow web inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.dg_vpc.id
  dynamic "ingress" {
    for_each = toset(local.ports_in)
    content {
      description = "HTTPS from VPC"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "egress" {
    for_each = toset(local.ports_out)
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "dev_allow_web"
  }
}

resource "aws_network_interface" "dg_net_interface" {
  subnet_id       = aws_subnet.dg_public_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.dg_allow_web.id]

}

resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.dg_net_interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.dg_internet_gateway]
  instance                  = aws_instance.web.id
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.dg_net_interface.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2 
                sudo bash -c 'echo my very first web server > /var/www/html/index.html'
                EOF

  tags = {
    Name = "dev_server"
  }
}