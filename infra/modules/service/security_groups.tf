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
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tasks" {
  name        = "${var.name_prefix}-tasks"
  description = "ECS tasks. Ingress allowed only from the ALB security group."
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "tasks_egress_vpce" {
  type                     = "egress"
  description              = "HTTPS to Interface VPC Endpoints (ECR API, ECR DKR, CloudWatch Logs)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = var.vpc_endpoint_security_group_id
  security_group_id        = aws_security_group.tasks.id
}

resource "aws_security_group_rule" "tasks_egress_s3" {
  type              = "egress"
  description       = "HTTPS to S3 Gateway VPC Endpoint (ECR layer pulls)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [var.s3_prefix_list_id]
  security_group_id = aws_security_group.tasks.id
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
