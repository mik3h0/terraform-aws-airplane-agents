# terraform-aws-agents

This terraform module creates an ECS cluster running Airplane agents.

To get started, you'll need an `api_token` and your `team_id`.

Use this module in your Terraform configuration:

```hcl
module "airplane_agent" {
  source = "airplanedev/airplane-agents/aws"
  version = "~> 0.3.0"

  api_token = "YOUR_API_TOKEN"
  team_id = "YOUR_TEAM_ID"

  # Set which subnets agents should live in
  subnet_ids = ["subnet-000", "subnet-111"]

  # Optional: attach labels to agents for task constraints
  agent_labels = {
    vpc = "123"
    env = "test"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.70.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.agent_log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.run_log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.agent_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.agent_task_def](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.default_run_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.agent_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.agent_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.default_run_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.run_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [random_uuid.cluster_name_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [random_uuid.lock_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_team_id"></a> [team\_id](#input\_team\_id) | Airplane team ID - retrieve via `airplane auth info`. | `string` | n/a | yes |
| <a name="input_agent_cpu"></a> [agent\_cpu](#input\_agent\_cpu) | CPU per agent, in vCPU units | `number` | `256` | no |
| <a name="input_agent_labels"></a> [agent\_labels](#input\_agent\_labels) | Map of label key/values to attach to agents. Labels can be used to constrain where tasks execute. | `map(string)` | <pre>{<br>  "ecs": "true"<br>}</pre> | no |
| <a name="input_agent_mem"></a> [agent\_mem](#input\_agent\_mem) | Memory per agent, in megabytes | `number` | `512` | no |
| <a name="input_allowed_iam_roles"></a> [allowed\_iam\_roles](#input\_allowed\_iam\_roles) | List of additional allowed IAM roles that tasks are allowed to assume | `list(string)` | `[]` | no |
| <a name="input_api_host"></a> [api\_host](#input\_api\_host) | For development purposes. | `string` | `"https://api.airplane.dev"` | no |
| <a name="input_api_token"></a> [api\_token](#input\_api\_token) | Airplane API key - generate one via `airplane apikeys create`. Either this or API Token Secret must be set | `string` | `""` | no |
| <a name="input_api_token_secret_arn"></a> [api\_token\_secret\_arn](#input\_api\_token\_secret\_arn) | ARN of API Token stored in AWS secret. Either this or API Token must be set. | `string` | `""` | no |
| <a name="input_api_token_secret_kms_key_arn"></a> [api\_token\_secret\_kms\_key\_arn](#input\_api\_token\_secret\_kms\_key\_arn) | ARN of customer-managed KMS key, if any, used to encrypt API Token Secret. | `string` | `""` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | Your ECS cluster ARN. Leave blank to create a new cluster. | `string` | `""` | no |
| <a name="input_debug_logging"></a> [debug\_logging](#input\_debug\_logging) | Enable debug logging in the agent and runners | `bool` | `false` | no |
| <a name="input_default_task_cpu"></a> [default\_task\_cpu](#input\_default\_task\_cpu) | Default CPU for tasks, in millicores (e.g. 500m or 1000m) | `string` | `"1000m"` | no |
| <a name="input_default_task_memory"></a> [default\_task\_memory](#input\_default\_task\_memory) | Default memory for tasks (e.g. 500Mi or 2Gi) | `string` | `"1Gi"` | no |
| <a name="input_env_slug"></a> [env\_slug](#input\_env\_slug) | Slug for environment. Leave blank to let agent execute on all environments. | `string` | `""` | no |
| <a name="input_num_agents"></a> [num\_agents](#input\_num\_agents) | Number of agent instances to run | `number` | `3` | no |
| <a name="input_private_repositories"></a> [private\_repositories](#input\_private\_repositories) | List of private repositories for Docker image tasks | `list(string)` | `[]` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Name to assign to ECS service | `string` | `"airplane-agent"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for ECS service. All subnets must be from the same VPC. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | AWS tags to attach to resources | `map(string)` | `{}` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | For development purposes. | `string` | `"temporal-api.airplane.dev:443"` | no |
| <a name="input_vpc_security_group_ids"></a> [vpc\_security\_group\_ids](#input\_vpc\_security\_group\_ids) | List of security group IDs to use. If not set, a new security group is created for the VPC containing the provided subnets. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_role_arn"></a> [agent\_role\_arn](#output\_agent\_role\_arn) | ARN of IAM role used for agent |
| <a name="output_agent_security_group_ids"></a> [agent\_security\_group\_ids](#output\_agent\_security\_group\_ids) | IDs of created security groups, if any |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | ARN of IAM role used for task runs created by agent |
<!-- END_TF_DOCS -->
