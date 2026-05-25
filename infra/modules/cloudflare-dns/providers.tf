provider "cloudflare" {
  api_token = local.secrets.cloudflare_api_token
}
