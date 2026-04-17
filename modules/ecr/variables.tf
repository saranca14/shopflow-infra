variable "project_name" {
  description = "Project name prefix for ECR repos"
  type        = string
}

variable "service_names" {
  description = "List of service names for ECR repositories"
  type        = list(string)
  default = [
    "frontend",
    "product-service",
    "cart-service",
    "order-service",
    "user-service",
    "payment-service",
  ]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
