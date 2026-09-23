/**
 * k3d-cluster
 * -----------
 * Provisions a multi-node, HA k3s-in-Docker cluster with Terraform.
 *
 * Why terraform_data + the k3d CLI instead of a community k3d provider:
 * the community providers lag behind k3d releases and have had breaking schema
 * changes. The k3d *config file* (k3d.io/v1alpha5) is the stable, declarative
 * interface, so Terraform renders it (local_file) and drives the lifecycle:
 *   - create on apply, delete on destroy
 *   - any change to the rendered config replaces the cluster (triggers_replace)
 */

locals {
  config_path = "${path.root}/.k3d/${var.cluster_name}.yaml"

  # one agent per simulated availability zone -> lets topologySpreadConstraints
  # and anti-affinity behave the way they will on a multi-AZ cloud cluster
  zones = [for i in range(var.agents) : "zone-${substr("abcdefghij", i % 10, 1)}"]

  k3d_config = {
    apiVersion = "k3d.io/v1alpha5"
    kind       = "Simple"
    metadata   = { name = var.cluster_name }
    servers    = var.servers
    agents     = var.agents
    image      = var.k3s_image
    kubeAPI    = { hostIP = "127.0.0.1", hostPort = tostring(var.api_port) }
    ports = [
      # host:8080 -> k3d load balancer -> Traefik ingress (port 80) on the nodes
      { port = "${var.http_port}:80", nodeFilters = ["loadbalancer"] },
      { port = "${var.https_port}:443", nodeFilters = ["loadbalancer"] },
    ]
    options = {
      k3d = { wait = true, timeout = "300s" }
      k3s = {
        extraArgs = concat(
          # keep application pods off the control-plane nodes
          [{ arg = "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule", nodeFilters = ["server:*"] }],
          # encrypt Secrets at rest in etcd
          [{ arg = "--secrets-encryption", nodeFilters = ["server:*"] }],
        )
        nodeLabels = [
          for i, z in local.zones : {
            label       = "topology.kubernetes.io/zone=${z}"
            nodeFilters = ["agent:${i}"]
          }
        ]
      }
      kubeconfig = { updateDefaultKubeconfig = true, switchCurrentContext = true }
    }
  }
}

resource "local_file" "k3d_config" {
  filename        = local.config_path
  content         = yamlencode(local.k3d_config)
  file_permission = "0644"
}

resource "terraform_data" "cluster" {
  triggers_replace = {
    name   = var.cluster_name
    config = sha256(local_file.k3d_config.content)
  }

  input = {
    name        = var.cluster_name
    config_path = local_file.k3d_config.filename
  }

  provisioner "local-exec" {
    command = "k3d cluster create --config ${self.input.config_path}"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "k3d cluster delete ${self.input.name}"
    on_failure = continue
  }
}
