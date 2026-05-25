locals {
  kubeconfig   = yamldecode(var.kubeconfig)
  cluster_conf = local.kubeconfig.clusters[0].cluster
  user_conf    = local.kubeconfig.users[0].user
}

provider "kubernetes" {
  host                   = local.cluster_conf.server
  cluster_ca_certificate = base64decode(local.cluster_conf["certificate-authority-data"])
  client_certificate     = base64decode(local.user_conf["client-certificate-data"])
  client_key             = base64decode(local.user_conf["client-key-data"])
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_conf.server
    cluster_ca_certificate = base64decode(local.cluster_conf["certificate-authority-data"])
    client_certificate     = base64decode(local.user_conf["client-certificate-data"])
    client_key             = base64decode(local.user_conf["client-key-data"])
  }
}
