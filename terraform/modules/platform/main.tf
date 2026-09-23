/**
 * platform
 * --------
 * Cluster-agnostic bootstrap shared by the local (k3d) and AWS (EKS) stacks.
 * Terraform owns only what must exist *before* GitOps can take over:
 *
 *   - namespaces (with Pod Security Admission labels)
 *   - MongoDB credentials: random passwords + replica-set keyfile -> Secret
 *     (generated here so they never appear in git)
 *   - Argo CD itself, and one "root" Application (app-of-apps) pointing at
 *     gitops/apps/<environment>. Everything else (MongoDB, the API,
 *     kube-prometheus-stack) is reconciled by Argo CD from git.
 */

locals {
  namespaces = {
    (var.app_namespace) = merge({
      # the workloads are written to pass the "restricted" Pod Security Standard
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }, var.app_namespace_extra_labels)
    argocd = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
    monitoring = {
      # node-exporter needs hostNetwork/hostPID/hostPath
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces
  metadata {
    name   = each.key
    labels = merge(each.value, { "app.kubernetes.io/part-of" = "articles-platform" })
  }
}

# ------------------------------------------------------------------ MongoDB secret
resource "random_password" "mongo" {
  for_each = toset(["root", "app", "metrics"])
  length   = 32
  special  = false # used inside mongodb:// URIs -> keep URL-safe
}

resource "random_password" "mongo_keyfile" {
  length  = 756
  special = false
}

resource "kubernetes_secret_v1" "mongodb_auth" {
  metadata {
    name      = "mongodb-auth"
    namespace = kubernetes_namespace_v1.this[var.app_namespace].metadata[0].name
    labels    = { "app.kubernetes.io/part-of" = "articles-platform" }
  }
  data = {
    "mongodb-root-password"    = random_password.mongo["root"].result
    "mongodb-app-password"     = random_password.mongo["app"].result
    "mongodb-metrics-password" = random_password.mongo["metrics"].result
    "mongodb-keyfile"          = random_password.mongo_keyfile.result
  }
}

# ------------------------------------------------------------------ Grafana admin
resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.this["monitoring"].metadata[0].name
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  }
}

# ------------------------------------------------------------------ Argo CD
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.this["argocd"].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  wait       = true
  timeout    = 900

  values = [yamlencode({
    configs = {
      params = { "server.insecure" = true } # TLS terminates at ingress / port-forward
    }
    # HA mode on EKS (multiple replicas + redis-ha); single replicas on k3d
    redis-ha   = { enabled = var.argocd_ha }
    controller = { replicas = 1 }
    server = {
      replicas = var.argocd_ha ? 2 : 1
      service  = { type = "ClusterIP" }
      metrics  = { enabled = true, serviceMonitor = { enabled = false } }
    }
    repoServer     = { replicas = var.argocd_ha ? 2 : 1 }
    applicationSet = { replicas = var.argocd_ha ? 2 : 1 }
  })]
}

# Root "app of apps": Argo CD takes over from here.
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root"
  namespace  = kubernetes_namespace_v1.this["argocd"].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "gitops/apps/${var.environment}"
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=false"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, kubernetes_secret_v1.mongodb_auth, kubernetes_secret_v1.grafana_admin]
}
