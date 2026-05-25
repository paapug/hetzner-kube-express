output "records_created" {
  description = "Sorted list of \"<fqdn> -> <ip>\" strings, one per created A record. Useful for downstream units to express an explicit dependency on DNS existing."
  value       = sort([for r in cloudflare_dns_record.a : "${r.name} -> ${r.content}"])
}
