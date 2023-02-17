resource "aws_iam_openid_connect_provider" "eks_oidc" {
  url = var.oidc_url
  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = []
}