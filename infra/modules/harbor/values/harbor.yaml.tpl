# cluster-internal Service; TLS terminates at Traefik via the module's Ingress.
expose:
  type: clusterIP
  tls:
    enabled: false

externalURL: ${external_url}

existingSecretAdminPassword: ${admin_secret_name}
existingSecretAdminPasswordKey: HARBOR_ADMIN_PASSWORD

persistence:
  enabled: true
  resourcePolicy: keep
  persistentVolumeClaim:
    registry:
      storageClass: ${storage_class}
      size: ${pvc_sizes.registry}
    jobservice:
      jobLog:
        storageClass: ${storage_class}
        size: ${pvc_sizes.jobservice}
    database:
      storageClass: ${storage_class}
      size: ${pvc_sizes.database}
    redis:
      storageClass: ${storage_class}
      size: ${pvc_sizes.redis}
    trivy:
      storageClass: ${storage_class}
      size: ${pvc_sizes.trivy}

trivy:
  enabled: true
