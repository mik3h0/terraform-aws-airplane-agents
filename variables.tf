// Required variables.
variable "team_id" {
  type        = string
  description = "Airplane team ID - retrieve via `airplane auth info`."
}

// Optional variables.
variable "additional_run_policy_arns" {
  type        = list(string)
  description = "List of additional IAM policies to attach to the default run role"
  default     = []
}

variable "allowed_iam_roles" {
  type        = list(string)
  description = "List of additional allowed IAM roles that tasks are allowed to assume"
  default     = []
}

variable "agent_image" {
  type        = string
  description = "URI for airplane agent image"
  default     = "public.ecr.aws/airplanedev-prod/agentv2:1"
}

variable "api_host" {
  type        = string
  description = "For development purposes."
  default     = "https://api.airplane.dev"
}

variable "api_token" {
  type        = string
  description = "Airplane API key - generate one via `airplane apikeys create`. Either this or API Token Secret must be set"
  sensitive   = true
  default     = ""
}

variable "api_token_secret_arn" {
  type        = string
  description = "ARN of API Token stored in AWS secret. Either this or API Token must be set."
  default     = ""
}

variable "api_token_secret_kms_key_arn" {
  type        = string
  description = "ARN of customer-managed KMS key, if any, used to encrypt API Token Secret."
  default     = ""
}

variable "assign_public_agent_ip" {
  type        = bool
  description = "If enabled, assigns a public IP address to the agent service. If disabled, the subnet used by the agent must be configured with a NAT gateway to enable internet access."
  default     = true
}

variable "cluster_arn" {
  type        = string
  description = "Your ECS cluster ARN. Leave blank to create a new cluster."
  default     = ""
}

variable "cpu_architecture" {
  type        = string
  description = "CPU architecture for agent and tasks. Note: ARM support is experimental- contact support for more details."
  default     = "X86_64"
}

variable "agent_labels" {
  type        = map(string)
  description = "Map of label key/values to attach to agents. Labels can be used to constrain where tasks execute."
  default     = { ecs : "true" }
}

variable "agent_cpu" {
  type        = number
  description = "CPU per agent, in vCPU units"
  default     = 256
}

variable "agent_mem" {
  type        = number
  description = "Memory per agent, in megabytes"
  default     = 512
}

variable "agent_storage_domain" {
  type        = string
  description = "For development purposes."
  default     = "d.airplane.sh"
}

variable "agent_storage_jwt_public_key" {
  type        = string
  description = "For development purposes."
  default     = "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUF1MGNBdTVmNnFrbWw0MUZxT01hcAo5cmNiZnNwOEJ3MFZVMlRra2pxTDFEOWYrYmF6TEdvcDJSYThWTTcxKzlPamFiNXpnWWZYOTdtWiszUmVUMTNQCkJ5clhRR1BuQ1VoVG9JOEVBdjA2NjJMbG83SzFHYm9TUjF6TjJoMWlNaXAwRFJQSUp0REJNL3QyTUxsSUxxRUMKbTlDdmNkTTg0dXdQc201VDdQV014Z0dYUG9pRnhwR1h5T2w1eCtjOGRaL1lHWU13V3A1eWNnRTVCb1lOK05SaAp0dE94T2NGS0JMbGgvaFNNeWUwaEV5cjlsMVYzVFovQW5xaUxWRlZsYUZ2MmJxbzNacnZUSG5rZHZQaVdkSDMxCmhvWWJJZDRmcHAreWFsNURtZmJqSklPQWFUN2R2UVRqZE9LUzQreW9TdGp2VlY2ZGdxVWtiK1dlcEg3Sk9UWUcKVVNhakRLSkMrQll3K2U5bE5XTldXRU4rc3NvaHBEb3BzaW12MTBKQUI1SFRUU1JBVXFhbzRSRndpVjhiRmFPUQpISFBqUWNBOWlSamluNDN3VDhsVnNNK1hTOFRLZVB6WGF2K3dtWXl1T3dNWTZ6Z0ppU1hZSG5EaDgwTWt0WmlkCkNBQk9BK0I3RWI0dHE1cXlPNzNnNndxTGZIeDVrblYyNjU1N2JZVjdkSUVsSUJiNnVsdnM5L1doV2VnNFhlRVcKdHh3M2gwNC9PWHZ6VlV2c0dVRXdTVmhjbzFyNU1sOWxTMHVrN0U2cG5aRTljSkI2T1VuMHVqSW9KQW91UDhwQwpaTDBNWkRlVys2ZThKV0Fqc043bjFjbUdhRC9jdER2N2E2eHNvbWsyTjVXQzE0U1lLUGVSTndTb05pOE5icENOCjJLZU5zTGlybXlqZEY5c29jVTFqVlQwQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo="
}

variable "debug_logging" {
  type        = bool
  description = "Enable debug logging in the agent and runners"
  default     = false
}

variable "default_task_cpu" {
  type        = string
  description = "Default CPU for tasks, in millicores (e.g. 500m or 1000m)"
  default     = "1000m"
}

variable "default_task_memory" {
  type        = string
  description = "Default memory for tasks (e.g. 500Mi or 2Gi)"
  default     = "1Gi"
}

variable "ecr_cache" {
  type        = bool
  description = "Set up a private ecr cache to improve performance and cost of image fetches"

  default = true
}

variable "env_slug" {
  type        = string
  description = "Slug for environment. Leave blank to let agent execute on all environments."
  default     = ""
}

variable "gcp_project_id" {
  type        = string
  description = "Project for Airplane resources; do not change this."
  default     = "airplane-prod"
}

variable "name_suffix" {
  type        = string
  description = "A custom suffix to add to all generated names; a dash is automatically added, so there is no need to include that if set."
  default     = ""
}

variable "num_agents" {
  type        = number
  description = "Number of agent instances to run"
  default     = 3
}

variable "private_repositories" {
  type        = list(string)
  description = "List of private repositories for Docker image tasks"
  default     = []
}

variable "self_hosted_agent_storage" {
  type        = bool
  description = "Enable self-hosted agent storage feature (alpha, requires support assistance to use)"
  default     = false
}

variable "service_name" {
  type        = string
  description = "Name to assign to ECS service"
  default     = "airplane-agent"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for ECS service. All subnets must be from the same VPC."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "AWS tags to attach to resources"
  default     = {}
}

variable "temporal_host" {
  type        = string
  description = "For development purposes."
  default     = "temporal-api.airplane.dev:443"
}

variable "use_ecr_public_images" {
  type        = bool
  description = "Use ECR-based public images for task runs"
  default     = true
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "List of security group IDs to use. If not set, a new security group is created for the VPC containing the provided subnets."
  default     = []
}

variable "zone_slug" {
  type        = string
  description = "Zone slug for use with self-hosted agent storage"
  default     = "test"
}
