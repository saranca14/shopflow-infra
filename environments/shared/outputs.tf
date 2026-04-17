output "vpc_id" {
  value = aws_vpc.shared.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "platform_subnet_ids" {
  value = aws_subnet.platform[*].id
}

output "observability_subnet_ids" {
  value = aws_subnet.observability[*].id
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "aws_region" {
  value = var.aws_region
}
