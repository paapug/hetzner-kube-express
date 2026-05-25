locals {
  # Flatten map(host -> [ip,...]) into a stable map keyed by "host/ip" so each
  # (host, ip) pair becomes its own resource instance. Multiple IPs for the
  # same host yields DNS round-robin.
  record_pairs = merge([
    for host, ips in var.records : {
      for ip in ips : "${host}/${ip}" => {
        name    = host
        content = ip
      }
    }
  ]...)
}

resource "cloudflare_dns_record" "a" {
  for_each = local.record_pairs

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = "A"
  ttl     = var.ttl
  content = each.value.content
  proxied = var.proxied
  comment = "Managed by terraform: ${each.value.name}"
}
