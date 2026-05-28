global:
  storageClass: ${storage_class}

clickhouse:
  persistence:
    size: ${pvc_sizes.clickhouse}
  zookeeper:
    persistence:
      size: ${pvc_sizes.zookeeper}

# We own the Ingress (see ingress.tf) so the chart-managed ones stay off.
signoz:
  persistence:
    size: ${pvc_sizes.signoz}
  ingress:
    enabled: false

otelCollector:
  ingress:
    enabled: false
