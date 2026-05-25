global:
  storageClass: ${storage_class}

# We own the Ingress (see ingress.tf) so the chart-managed ones stay off.
signoz:
  ingress:
    enabled: false

otelCollector:
  ingress:
    enabled: false
