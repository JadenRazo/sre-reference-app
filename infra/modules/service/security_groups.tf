resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Public ingress to the ALB on port 80."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Application traffic to ECS tasks only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }
}

resource "aws_security_group" "tasks" {
  name        = "${var.name_prefix}-tasks"
  description = "ECS tasks. Ingress allowed only from the ALB security group."
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS for ECR image pulls and CloudWatch log delivery"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over UDP to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS over TCP to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

# Split into a standalone rule resource to avoid the alb_sg <-> tasks_sg
# circular dependency that arises if both reference each other inline.
resource "aws_security_group_rule" "tasks_from_alb" {
  type                     = "ingress"
  description              = "Container port from the ALB only"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.tasks.id
}
