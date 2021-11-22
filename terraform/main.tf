provider "aws" {
  region = "sa-east-1"
}

resource "aws_s3_bucket" "tfbucket" {
  bucket = "fornewstate-final"
  acl    = "private"

  lifecycle {
    prevent_destroy = true
  }
  versioning {
    enabled = true
  }

  tags = {
    Name = "tf-state-final"
  }
}

resource "aws_dynamodb_table" "forstate" {
  name           = "for_state_lock"
  hash_key       = "LockID"
  read_capacity  = "8"
  write_capacity = "8"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "StateLock"
  }
  depends_on = [aws_s3_bucket.tfbucket]
}

resource "aws_vpc" "k8s" {
  cidr_block = "192.168.0.0/22"
  tags = {
    Name = "vpc-k8s-final"
  }
}

resource "aws_subnet" "k8s" {
  vpc_id            = aws_vpc.k8s.id
  cidr_block        = "192.168.0.0/24"
  availability_zone = "sa-east-1a"
  tags = {
    Name = "subnet-k8s-1a-final"
  }
}

resource "aws_subnet" "k8s_1c" {
  vpc_id            = aws_vpc.k8s.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "sa-east-1c"
  tags = {
    Name = "subnet-k8s-1c-final"
  }
}

resource "aws_subnet" "mysql" {
  vpc_id            = aws_vpc.k8s.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = "sa-east-1c"
  tags = {
    Name = "subnet-mysql-pvt-final"
  }
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
  tags = {
    Name = "igw-k8s-final"
  }
}

resource "aws_nat_gateway" "k8s" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.k8s.id

  tags = {
    Name = "ng-final"
  }

  depends_on = [aws_internet_gateway.k8s]
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_eip" "k8s_dev" {
  instance = aws_instance.k8s_dev.id
  vpc      = true
}

resource "aws_route_table" "k8s" {
  vpc_id = aws_vpc.k8s.id # "vpc-046120c34252bce8f"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id # "igw-08e7b3ed2e558d14a"
  }

  tags = {
    Name = "k8s-final"
  }
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.k8s.id
}

resource "aws_route_table" "mysql" {
  vpc_id = aws_vpc.k8s.id # "vpc-046120c34252bce8f"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s.id
  }

  tags = {
    Name = "mysql-final"
  }
}

resource "aws_route_table_association" "mysql" {
  subnet_id      = aws_subnet.mysql.id
  route_table_id = aws_route_table.mysql.id
}

resource "aws_lb_target_group" "k8s" {
  name     = "tg-lb-k8s-masters-final"
  port     = 30000
  protocol = "HTTP"
  vpc_id   = aws_vpc.k8s.id

  health_check {
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200,301"
    unhealthy_threshold = 2
  }
}

resource "aws_lb" "k8s" {
  name               = "lb-k8s-masters-final"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.k8s_lb.id]
  subnets            = [aws_subnet.k8s.id, aws_subnet.k8s_1c.id]

  enable_deletion_protection = true

  tags = {
    Environment = "lb-k8s-masters-final"
  }
}

resource "aws_lb_target_group_attachment" "k8s" {
  target_group_arn = aws_lb_target_group.k8s.arn
  for_each         = toset([aws_instance.k8s_master[0].id, aws_instance.k8s_master[1].id, aws_instance.k8s_master[2].id])
  target_id        = each.key
  port             = 30001
}

resource "aws_lb_listener" "k8s" {
  load_balancer_arn = aws_lb.k8s.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s.arn
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server*"]
  }
}

resource "aws_instance" "haproxy" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.large"
  key_name                    = "prj_final"
  subnet_id                   = aws_subnet.k8s.id
  associate_public_ip_address = true
  root_block_device {
    encrypted   = true
    volume_size = 20
  }
  tags = {
    Name = "ec2-k8s-haproxy-final"
  }
  vpc_security_group_ids = ["${aws_security_group.haproxy.id}"]
}

resource "aws_instance" "k8s_dev" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.large"
  key_name                    = "prj_final"
  subnet_id                   = aws_subnet.k8s.id
  associate_public_ip_address = true
  root_block_device {
    encrypted   = true
    volume_size = 20
  }
  tags = {
    Name = "ec2-k8s-dev-final"
  }
  vpc_security_group_ids = ["${aws_security_group.k8s_dev.id}"]
}

resource "aws_instance" "k8s_master" {
  count                       = 3
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.large"
  key_name                    = "prj_final"
  subnet_id                   = aws_subnet.k8s.id
  associate_public_ip_address = true
  root_block_device {
    encrypted   = true
    volume_size = 20
  }
  tags = {
    Name = "ec2-k8s-master-final"
  }
  vpc_security_group_ids = ["${aws_security_group.k8s_master.id}"]
}

resource "aws_instance" "k8s_worker" {
  count                       = 3
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.large"
  key_name                    = "prj_final"
  subnet_id                   = aws_subnet.k8s.id
  associate_public_ip_address = true
  root_block_device {
    encrypted   = true
    volume_size = 20
  }
  tags = {
    Name = "ec2-k8s-worker-final"
  }
  vpc_security_group_ids = ["${aws_security_group.k8s_worker.id}"]
}

resource "aws_instance" "mysql" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.large"
  key_name                    = "prj_final"
  subnet_id                   = aws_subnet.mysql.id
  associate_public_ip_address = false
  root_block_device {
    encrypted   = true
    volume_size = 20
  }
  tags = {
    Name = "ec2-mysql-final"
  }
  vpc_security_group_ids = ["${aws_security_group.mysql.id}"]
}

resource "aws_security_group" "haproxy" {
  name        = "sg_k8s_haproxy_final"
  description = "k8s haproxy traffic"
  vpc_id      = aws_vpc.k8s.id # "vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "SSH from DEV"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_dev.id],
      self : null
    },
    {
      description      = "TCP from workers"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_worker.id, aws_security_group.k8s_master.id],
      self : null
    },
    {
      description      = "TCP from self"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : true
    },
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-haproxy-final"
  }
}

resource "aws_security_group" "k8s_lb" {
  name        = "sg_k8s_lb_final"
  description = "k8s lb traffic"
  vpc_id      = aws_vpc.k8s.id # "vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "HTTP"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : null
    },
    {
      description      = "HTTPS"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : null
    }
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-lb-final"
  }
}

resource "aws_security_group" "k8s_dev" {
  name        = "sg_k8s_dev_final"
  description = "k8s master traffic"
  vpc_id      = aws_vpc.k8s.id # "vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : null
    },
    {
      description      = "Jenkins"
      from_port        = 8080
      to_port          = 8080
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : null
    }
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-dev-final"
  }
}

resource "aws_security_group" "k8s_master" {
  name        = "sg_k8s_master_final"
  description = "k8s master traffic"
  vpc_id      = aws_vpc.k8s.id # "vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "SSH from DEV"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_dev.id],
      self : null
    },
    {
      description      = "TCP from ALB"
      from_port        = 30000
      to_port          = 32000
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_lb.id],
      self : null
    },
    {
      description      = "TCP from outside"
      from_port        = 30000
      to_port          = 32000
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : null
    },
    {
      description      = "TCP from workers"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_worker.id, aws_security_group.k8s_dev.id, "sg-0849723a0e630310c"],
      self : null
    },
    {
      description      = "TCP from self"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : true
    },
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-master-final"
  }
}

resource "aws_security_group" "k8s_worker" {
  name        = "sg_k8s_worker_final"
  description = "k8s worker traffic"
  vpc_id      = aws_vpc.k8s.id #"vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "SSH from DEV/Jenkins"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_dev.id],
      self : null
    },
    {
      description      = "TCP from master"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : ["sg-054fc9a44f9ecd3e6", "sg-0849723a0e630310c"]
      self : null
    },

    {
      description      = "TCP from self"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : null
      self : true
    },
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-worker-final"
  }
}

resource "aws_security_group" "mysql" {
  name        = "sg_mysql_final"
  description = "MySQL internal traffic"
  vpc_id      = aws_vpc.k8s.id # "vpc-046120c34252bce8f"
  ingress = [
    {
      description      = "SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_dev.id]
      self : null
    },
    {
      description      = "MySQL"
      from_port        = 3306
      to_port          = 3306
      protocol         = "tcp"
      cidr_blocks      = null
      ipv6_cidr_blocks = null
      prefix_list_ids  = null,
      security_groups : [aws_security_group.k8s_worker.id, aws_security_group.k8s_dev.id, aws_security_group.k8s_master.id]
      self : null
    }
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"],
      prefix_list_ids  = null,
      security_groups : null,
      self : null,
      description : "Egress"
    }
  ]

  tags = {
    Name = "sg-k8s-mysql-final"
  }
}


output "k8s_master" {
  value = [
    for key, item in aws_instance.k8s_master :
    "k8s-master ${key + 1} private=${item.private_ip} - public=${item.public_ip}"
  ]
}

output "k8s_worker" {
  value = [
    for key, item in aws_instance.k8s_worker :
    "k8s-worker ${key + 1} private=${item.private_ip} - public=${item.public_ip}"
  ]
}

output "k8s_dev" {
  value = "k8s-dev private=${aws_instance.k8s_dev.private_ip} - public=${aws_instance.k8s_dev.public_ip}"
}

output "haproxy" {
  value = "haproxy private=${aws_instance.haproxy.private_ip} - public=${aws_instance.haproxy.public_ip}"
}

output "mysql" {
  value = "mysql private=${aws_instance.mysql.private_ip}"
}

output "sg_dev" {
  value = "sg-dev id=${aws_security_group.k8s_dev.id}"
}

output "sg_master" {
  value = "sg-master id=${aws_security_group.k8s_master.id}"
}

output "sg_worker" {
  value = "sg-worker id=${aws_security_group.k8s_worker.id}"
}

output "sg_haproxy" {
  value = "sg-haproxy id=${aws_security_group.haproxy.id}"
}

output "sg_mysql" {
  value = "sg-mysql id=${aws_security_group.mysql.id}"
}