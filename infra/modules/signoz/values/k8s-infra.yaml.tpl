global:
  cloud: others
  clusterName: ${cluster_name}
  deploymentEnvironment: ${deployment_environment}
otelCollectorEndpoint: ${otel_collector_endpoint}
otelInsecure: true
presets:
  otlphttpExporter:
    enabled: true
  loggingExporter:
    enabled: false
