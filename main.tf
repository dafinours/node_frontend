# ~~~~~~~~~~~~~~~~~~~~~ Getting the ECS Cluster ~~~~~~~~~~~~~~~~~~~~~~~

data "aws_ecs_cluster" "cluster" {
    cluster_name = var.cluster_name
  
}

# ~~~~~~~~~~~~~~~~~~~~~ Getting network configuration ~~~~~~~~~~~~~~~~~~~~~~~

data "aws_vpc" "project_vpc" {
    filter {
      name = "tag:Project"
      values = ["${var.project_name}"]
    }
}

data "aws_subnets" "public_subnets" {
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.project_vpc.id]
    }
    tags = {
      Tier = "Public"
    }
}
data "aws_security_group" "frontend_sg" {
    vpc_id = data.aws_vpc.project_vpc.id
    name = "${var.frontend_app_name}-sg"
  
}

# ~~~~~~~~~~~~~~~~~~~~~ Getting LoadBalancer ~~~~~~~~~~~~~~~~~~~~~~~

data "aws_alb" "backend_lb" {
    name = var.backend_app_name 
}

data "aws_alb" "frontend_lb" {
    name = "${var.frontend_app_name}-lb" 
}

# ~~~~~~~~~~~~~~~~ Getting target Group for the backend~~~~~~~~~~~~~~
data "aws_alb_target_group" "frontend_tg" {
    name = "${var.frontend_app_name}-target-group"
}

# ~~~~~~~~~~~~~~~~ Getting ecr repository~~~~~~~~~~~~~~
data "aws_ecr_repository" "repo" {
    name = "${var.frontend_app_name}-repo"
}
data "aws_iam_role" "execution_role" {
  name = "${var.project_name}-ecs-execution-role"
}

# ~~~~~~~~~~~~ Creating ECS Task Definition for the services~~~~~~~~~
resource "aws_ecs_task_definition" "frontend_task_definition" {
    family = var.frontend_app_name
    network_mode = "awsvpc"
    execution_role_arn = data.aws_iam_role.execution_role.arn
    requires_compatibilities = ["FARGATE"]
    cpu = var.cpu
    memory = var.memory
    container_definitions = <<TASK_DEFINITION
    [
        {
            "name": "${var.frontend_app_name}",
            "image": "${data.aws_ecr_repository.repo.repository_url}:${var.image_tag}",
            "essential": true,
            "cpu": ${var.cpu},
            "memory": ${var.memory},
            "portMappings": [
                {
                    "containerPort": ${var.frontend_port},
                    "hostPort": ${var.frontend_port}
                }
            ],
            "environment": [
                {
                    "name": "REACT_APP_API_URL",
                    "value": "http://${data.aws_alb.backend_lb.dns_name}:${var.backend_port}/"
                }
            ]
        }
    ]
    TASK_DEFINITION
    runtime_platform {
      operating_system_family = "LINUX"
      cpu_architecture = "X86_64"
    }
}

resource "aws_ecs_service" "frontend_svc" {
    name = var.frontend_app_name
    cluster = data.aws_ecs_cluster.cluster.id
    launch_type = "FARGATE"
    task_definition = aws_ecs_task_definition.frontend_task_definition.arn
    desired_count = 4

    network_configuration {
      security_groups = [ data.aws_subnets.public_subnets.id ]
      subnets = ["subnet-02edbaa1ce675d546", "subnet-06993722a55f99adf"]
    }

    load_balancer {
      target_group_arn = data.aws_alb_target_group.frontend_tg.arn
      container_name = var.frontend_app_name
      container_port = 8080
    }
  
}
