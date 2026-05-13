resource "aws_lb" "app" {
  # checkov:skip=CKV2_AWS_20: ALB has an http_redirect listener (port 80 → 443) when cert_arn is set; when cert_arn is null the app is HTTP-only by design and there is no TLS cert to redirect to.
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = var.name_prefix
    enabled = true
  }
}

resource "aws_lb_target_group" "app" {
  # checkov:skip=CKV_AWS_378: ALB terminates TLS and speaks plain HTTP to Fargate tasks on the private network; encrypting ALB-to-backend traffic on a private subnet adds overhead with no meaningful threat reduction.
  name        = "${var.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # 30s deregistration so chaos failovers (Phase 6 FIS run) cycle through
  # quickly instead of holding draining tasks for the 300s default. This
  # tuning is the documented learning in docs/chaos-experiments.md.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.cert_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "http_forward" {
  # checkov:skip=CKV2_AWS_20: http_forward listener has no TLS redirect because cert_arn is null in HTTP-only deployments — there is no cert to redirect to.
  count = var.cert_arn == null ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.cert_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
