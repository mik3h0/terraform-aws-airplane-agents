output "agent_role_arn" {
    value = aws_iam_role.agent_role.arn
    description = "ARN of IAM role used for agent"
}

output "agent_security_group_ids" {
  value = [for sg in module.agent_security_group : sg.security_group_id]
  description = "IDs of created security groups, if any"
}

output "task_execution_role_arn" {
    value = aws_iam_role.default_run_role.arn
    description = "ARN of IAM role used for task runs created by agent"
}
