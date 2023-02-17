variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}


#### OIDC Resource
## EKS Cluster OIDC url
variable "oidc_url" {
    type = string
    default = "https://oidc.eks.ap-south-1.amazonaws.com/id/AE96D18328588FD90A4CC6BDB2E34F9A" 
}