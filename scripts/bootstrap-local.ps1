<#
  Windows-native local bootstrap (no WSL needed).

    1. makes sure Docker Desktop's engine is running (starts it if needed)
    2. uses k3d / kubectl / terraform from PATH, or downloads them into .tools\
    3. Terraform layer 1 -> k3d cluster (3 servers + 3 agents)
    4. Terraform layer 2 -> namespaces, secrets, Argo CD, root GitOps app
    5. waits for Argo CD to sync kube-prometheus-stack, MongoDB and the API
    6. runs the CRUD test (scripts\test-api.ps1)

  Run from the repo root:   .\bootstrap-local.bat      (or)
                            powershell -ExecutionPolicy Bypass -File scripts\bootstrap-local.ps1
#>
# "Continue": in Windows PowerShell 5.1, stderr from native tools (docker, kubectl)
# would otherwise be turned into terminating errors. Exit codes are checked explicitly.
$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"   # makes Invoke-WebRequest much faster
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root  = Split-Path -Parent $PSScriptRoot
$Tools = Join-Path $Root ".tools"
New-Item -ItemType Directory -Force -Path $Tools | Out-Null
$env:PATH = "$Tools;$env:PATH"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# ------------------------------------------------------------------ 1. Docker
Step "[1/6] Docker engine"
if (-not (Have "docker")) {
  $dockerBin = "C:\Program Files\Docker\Docker\resources\bin"
  if (Test-Path "$dockerBin\docker.exe") { $env:PATH = "$dockerBin;$env:PATH" }
  else { Fail "Docker Desktop is not installed. Install it from https://www.docker.com/products/docker-desktop/ and run this again." }
}

function DockerUp { docker info *> $null; return ($LASTEXITCODE -eq 0) }
if (-not (DockerUp)) {
  $dd = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  if (Test-Path $dd) { Write-Host "Starting Docker Desktop ..."; Start-Process $dd }
  $deadline = (Get-Date).AddMinutes(4)
  while (-not (DockerUp)) {
    if ((Get-Date) -gt $deadline) {
      Fail ("Docker's engine did not start. Open Docker Desktop and look at its message.`n" +
            "  - If it says WSL is missing/outdated: open PowerShell *as Administrator*, run 'wsl --install' (or 'wsl --update'), reboot.`n" +
            "  - Make sure it is using Linux containers (tray icon > 'Switch to Linux containers').")
    }
    Write-Host "  waiting for Docker engine ..."; Start-Sleep 5
  }
}
docker version --format "  Docker engine {{.Server.Version}} is running"

# ------------------------------------------------------------------ 2. tools
Step "[2/6] Tools (k3d, kubectl, terraform)"
if (-not (Have "k3d")) {
  Write-Host "  downloading k3d v5.9.0 ..."
  Invoke-WebRequest -ErrorAction Stop "https://github.com/k3d-io/k3d/releases/download/v5.9.0/k3d-windows-amd64.exe" -OutFile "$Tools\k3d.exe"
}
if (-not (Have "kubectl")) {
  $kv = (Invoke-WebRequest -ErrorAction Stop "https://dl.k8s.io/release/stable.txt" -UseBasicParsing).Content.Trim()
  Write-Host "  downloading kubectl $kv ..."
  Invoke-WebRequest -ErrorAction Stop "https://dl.k8s.io/release/$kv/bin/windows/amd64/kubectl.exe" -OutFile "$Tools\kubectl.exe"
}
if (-not (Have "terraform")) {
  $tv = "1.15.8"
  Write-Host "  downloading terraform $tv ..."
  Invoke-WebRequest -ErrorAction Stop "https://releases.hashicorp.com/terraform/$tv/terraform_${tv}_windows_amd64.zip" -OutFile "$Tools\terraform.zip"
  Expand-Archive "$Tools\terraform.zip" -DestinationPath $Tools -Force
  Remove-Item "$Tools\terraform.zip"
}
Write-Host ("  k3d:       " + ((k3d version | Select-Object -First 1)))
Write-Host ("  kubectl:   " + ((kubectl version --client 2>$null | Select-Object -First 1)))
Write-Host ("  terraform: " + ((terraform version | Select-Object -First 1)))

function Tf($dir, [string[]]$tfArgs) {
  & terraform "-chdir=$dir" @tfArgs
  if ($LASTEXITCODE -ne 0) { Fail "terraform $($tfArgs -join ' ') failed in $dir" }
}

# ------------------------------------------------------------------ 3. cluster
Step "[3/6] k3d cluster via Terraform (first run pulls k3s images: a few minutes)"
$L1 = Join-Path $Root "terraform\environments\local\1-cluster"
Tf $L1 @("init", "-input=false")
Tf $L1 @("apply", "-auto-approve", "-input=false")
kubectl config use-context k3d-articles | Out-Null
kubectl get nodes -L topology.kubernetes.io/zone

# ------------------------------------------------------------------ 4. platform
Step "[4/6] Platform: namespaces, secrets, Argo CD, root app"
$L2 = Join-Path $Root "terraform\environments\local\2-platform"
Tf $L2 @("init", "-input=false")
Tf $L2 @("apply", "-auto-approve", "-input=false")

# ------------------------------------------------------------------ 5. GitOps sync
Step "[5/6] Waiting for Argo CD to deploy everything (first run: ~5-15 min)"
foreach ($app in @("kube-prometheus-stack", "mongodb", "articles-api")) {
  Write-Host "  - $app"
  $deadline = (Get-Date).AddMinutes(20)
  while ($true) {
    $health = kubectl -n argocd get application $app -o "jsonpath={.status.health.status}" 2>$null
    $sync   = kubectl -n argocd get application $app -o "jsonpath={.status.sync.status}" 2>$null
    if ($health -eq "Healthy") { Write-Host "    Synced=$sync Healthy"; break }
    if ((Get-Date) -gt $deadline) {
      kubectl -n argocd get applications
      kubectl -n articles get pods -o wide
      Fail "$app did not become Healthy in 20 minutes (see the pod list above)."
    }
    Start-Sleep 10
  }
}
kubectl -n articles rollout status statefulset/mongodb --timeout=600s
kubectl -n articles rollout status deployment/articles-api --timeout=300s
kubectl -n argocd get applications
kubectl -n articles get pods -o wide

# ------------------------------------------------------------------ 6. test
Step "[6/6] API test against http://localhost:8080"
& (Join-Path $PSScriptRoot "test-api.ps1") -BaseUrl "http://localhost:8080"

Write-Host "`nUseful next steps:" -ForegroundColor Green
Write-Host "  Argo CD : kubectl -n argocd port-forward svc/argocd-server 8081:80   -> http://localhost:8081"
Write-Host "            password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'  (base64)"
Write-Host "  Grafana : kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 -> http://localhost:3000"
Write-Host "            password: terraform -chdir=terraform\environments\local\2-platform output -raw grafana_admin_password  (user: admin)"
Write-Host "  Tear down: terraform -chdir=terraform\environments\local\1-cluster destroy -auto-approve"
