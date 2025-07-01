provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ------------------- USE DEFAULT VPC -------------------

data "aws_vpc" "default" {
  default = true
}

# ✅ Fixed: Correct way to get subnet IDs in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get first two subnets (adjust if fewer exist in your default VPC)
data "aws_subnet" "subnet1" {
  id = data.aws_subnets.default.ids[0]
}

data "aws_subnet" "subnet2" {
  id = data.aws_subnets.default.ids[1]
}

# ------------------- SECURITY GROUP -------------------

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------- IAM + LAMBDA -------------------

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = { Service = "lambda.amazonaws.com" },
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "node_lambda" {
  function_name = "nodejs-lambda-${random_id.suffix.hex}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  filename      = "${path.module}/lambda.zip"
  timeout       = 30
  memory_size   = 128

  source_code_hash = fileexists("${path.module}/lambda.zip") ? filebase64sha256("${path.module}/lambda.zip") : null

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# ------------------- ALB + Lambda Integration -------------------

resource "aws_lb" "app_lb" {
  name               = "lambda-alb-${random_id.suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  subnets            = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "lambda-target-${random_id.suffix.hex}"
  target_type = "lambda"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}

resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.node_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn
}

resource "aws_lb_target_group_attachment" "lambda_attach" {
  target_group_arn = aws_lb_target_group.lambda_tg.arn
  target_id        = aws_lambda_function.node_lambda.arn

  depends_on = [
    aws_lambda_permission.alb_invoke
  ]
}
