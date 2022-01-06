# terraform-aws-agents

This terraform module creates an ECS cluster running Airplane agents.

To get started, you'll need an `api_token` and your `team_id`.

Use this module in your Terraform configuration:

```hcl
module "airplane_agent" {
  source = "airplanedev/airplane-cluster/ecs"
  version = "~> 0.4.0"

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
