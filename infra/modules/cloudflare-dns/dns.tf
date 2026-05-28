locals {
  additional_records = {
    for subdomain in var.additional_ingress_subdomains : "${subdomain}.${var.cloudflare_domain}" => var.agents_public_ipv4
  }

  records = merge(local.additional_records, var.records)

  # Flatten map(host -> [ip,...]) to one resource instance per (host, ip);
  # multiple IPs for the same host gives DNS round-robin.
  record_pair_list = flatten([
    for host, ips in local.records : [
      for ip in ips : {
        key     = "${host}/${ip}"
        name    = host
        content = ip
      }
    ]
  ])

  record_pairs = {
    for pair in local.record_pair_list : pair.key => {
      name    = pair.name
      content = pair.content
    }
  }
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
