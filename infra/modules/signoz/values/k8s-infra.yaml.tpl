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
  hostMetrics:
    enabled: true
  logsCollection:
    enabled: true
    blacklist:
      enabled: true
      namespaces: 
        - kube-system
  kubeletMetrics:
    enabled: true
  kubernetesAttributes:
    enabled: true
  clusterMetrics:
    enabled: true
  k8sEvents:
    enabled: true
  prometheus:
    enabled: true
    # Match the de-facto kube-prometheus convention so workloads annotated
    # with prometheus.io/{scrape,path,port,scheme} get scraped without
    # rewriting them for SigNoz.
    annotationsPrefix: prometheus.io
    includeContainerName: true