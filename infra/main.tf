module "network" {
  source = "./modules/network"

  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr
}

module "service" {
  source = "./modules/service"

  name_prefix        = var.name_prefix
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr_block
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  container_port     = var.container_port
  container_image    = var.container_image
  task_cpu           = var.task_cpu
  task_memory        = var.task_memory
  desired_count      = var.desired_count
}

module "observability" {
  source = "./modules/observability"

  name_prefix             = var.name_prefix
  region                  = var.region
  alarm_email             = var.alarm_email
  slo_target              = var.slo_target
  enable_fis              = var.enable_fis
  alb_arn_suffix          = module.service.alb_arn_suffix
  target_group_arn_suffix = module.service.target_group_arn_suffix
  ecs_cluster_name        = module.service.ecs_cluster_name
  ecs_service_name        = module.service.ecs_service_name
  ecs_cluster_arn         = module.service.ecs_cluster_arn
}

module "cicd" {
  source = "./modules/cicd"

  name_prefix            = var.name_prefix
  github_repo            = var.github_repo
  ecr_repository_arn     = module.service.ecr_repository_arn
  ecs_cluster_arn        = module.service.ecs_cluster_arn
  ecs_service_arn        = module.service.ecs_service_arn
  task_role_arn          = module.service.task_role_arn
  task_execution_arn     = module.service.task_execution_role_arn
  task_definition_family = module.service.task_definition_family
}
