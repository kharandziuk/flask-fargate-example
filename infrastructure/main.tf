terraform {
  required_providers {
    aws = {
      source  = "-/aws"
      version = "< 3.0"
    }
  }
}

variable "aws_region" {
  default = "eu-central-1"
  type    = string
}

provider "aws" {
  region = var.aws_region
}

locals {
  container_name = "example"
  cidr_block     = "10.255.0.0/16"
}


data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_ecr_repository" "backend" {
  name = "test-service"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "default" {
  name               = "ecs-task-execution-for-ecs-fargate"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "default" {
  name   = aws_iam_role.default.name
  policy = data.aws_iam_policy.ecs_task_execution.policy
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.name
  policy_arn = aws_iam_policy.default.arn
}

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_ecs_cluster" "example" {
  name = "default"
}

resource "aws_default_subnet" "defaults" {
  count             = length(data.aws_availability_zones.available.names)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

module "alb" {
  source                     = "git::https://github.com/tmknom/terraform-aws-alb.git?ref=tags/2.1.0"
  name                       = "ecs-fargate"
  vpc_id                     = aws_default_vpc.default.id
  subnets                    = aws_default_subnet.defaults.*.id
  access_logs_bucket         = module.s3_lb_log.s3_bucket_id
  enable_https_listener      = false
  enable_http_listener       = true
  enable_deletion_protection = false

  providers = {
    aws = aws
  }
}

module "s3_lb_log" {
  source                = "git::https://github.com/tmknom/terraform-aws-s3-lb-log.git?ref=tags/2.0.0"
  name                  = "s3-lb-log-ecs-fargate-${data.aws_caller_identity.current.account_id}"
  logging_target_bucket = module.s3_access_log.s3_bucket_id
  force_destroy         = true
  providers = {
    aws = aws
  }
}

module "s3_access_log" {
  source        = "git::https://github.com/tmknom/terraform-aws-s3-access-log.git?ref=tags/2.0.0"
  name          = "s3-access-log-ecs-fargate-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  providers = {
    aws = aws
  }
}



module "ecs_fargate" {
  source           = "git::https://github.com/tmknom/terraform-aws-ecs-fargate.git?ref=tags/2.0.0"
  name             = "test-api"
  container_name   = local.container_name
  container_port   = 80
  cluster          = aws_ecs_cluster.example.arn
  subnets          = aws_default_subnet.defaults.*.id
  target_group_arn = module.alb.alb_target_group_arn
  vpc_id           = aws_default_vpc.default.id

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${data.aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      log_group = aws_cloudwatch_log_group.api_backend_log_group.name
      logConfiguration = {
        logDriver : "awslogs",
        options : {
          "awslogs-group"         = aws_cloudwatch_log_group.api_backend_log_group.name
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "ecs"
        }
      },

      portMappings = [
        {
          protocol      = "tcp"
          containerPort = 80
        }
      ]
    }
  ])

  desired_count                      = 2
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  deployment_controller_type         = "ECS"
  assign_public_ip                   = true
  health_check_grace_period_seconds  = 10
  platform_version                   = "LATEST"
  source_cidr_blocks                 = ["0.0.0.0/0"]
  cpu                                = 256
  memory                             = 512
  requires_compatibilities           = ["FARGATE"]
  iam_path                           = "/service_role/"
  description                        = "This is example"
  enabled                            = true

  create_ecs_task_execution_role = false
  ecs_task_execution_role_arn    = aws_iam_role.default.arn

  tags = {
    Environment = "prod"
  }
  providers = {
    aws = aws
  }
}

output "dns" {
  value = "http://${module.alb.alb_dns_name}"
}


output "service_name" {
  value = module.ecs_fargate.ecs_service_name
}

output "cluster_name" {
  value = aws_ecs_cluster.example.name
}


# Set up cloudwatch group and log stream and retain logs for 30 days
resource "aws_cloudwatch_log_group" "api_backend_log_group" {
  name              = "/ecs/api-backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_stream" "api_backend_log_stream" {
  name           = "api-backend-log-stream"
  log_group_name = aws_cloudwatch_log_group.api_backend_log_group.name
}
