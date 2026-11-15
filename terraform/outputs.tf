output "instance_id" {
  value = aws_instance.app.id
}
output "public_ip" {
  value = aws_instance.app.public_ip
}
output "ecr_repository" {
  value = aws_ecr_repository.app.name
}
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}
output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}
