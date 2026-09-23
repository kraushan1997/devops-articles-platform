<#
  Exercise all five Articles endpoints (Windows PowerShell 5.1+ / PowerShell 7).
    scripts\test-api.ps1                               # k3d: http://localhost:8080
    scripts\test-api.ps1 -BaseUrl http://<alb-host>    # EKS
  Output is formatted for screenshots (assignment section 9).
#>
param([string]$BaseUrl = "http://localhost:8080")
$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

function Call([string]$Method, [string]$Path, $Body = $null) {
  $shown = if ($Body) { " -d '$($Body | ConvertTo-Json -Compress)'" } else { "" }
  Write-Host "`$ curl -X $Method $BaseUrl$Path$shown" -ForegroundColor Yellow
  $params = @{ Uri = "$BaseUrl$Path"; Method = $Method; UseBasicParsing = $true }
  # PowerShell 7: return 4xx/5xx responses instead of throwing (5.1 is handled in catch)
  if ($PSVersionTable.PSVersion.Major -ge 7) { $params.SkipHttpErrorCheck = $true }
  if ($Body) { $params.Body = ($Body | ConvertTo-Json -Compress); $params.ContentType = "application/json" }
  try {
    $r = Invoke-WebRequest @params
    $code = [int]$r.StatusCode; $content = $r.Content
  } catch {
    $resp = $_.Exception.Response
    if (-not $resp) { throw }
    $code = [int]$resp.StatusCode
    $content = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
  }
  Write-Host "HTTP $code"
  if ($content) { try { $content | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Write-Host } catch { Write-Host $content } }
  return @{ Code = $code; Body = $content }
}

Step "0. Health"
Call GET "/readyz" | Out-Null

Step "1. CREATE  POST /articles"
$r = Call POST "/articles" @{ title = "Hello Kubernetes"; content = "Running on a 3-member MongoDB replica set"; author = "raushan"; tags = @("k8s", "mongodb") }
if ($r.Code -ne 201) { throw "create failed" }
$id = ($r.Body | ConvertFrom-Json).id

Step "2. LIST    GET /articles"
Call GET "/articles" | Out-Null

Step "3. READ    GET /articles/$id"
Call GET "/articles/$id" | Out-Null

Step "4. UPDATE  PUT /articles/$id"
$r = Call PUT "/articles/$id" @{ title = "Hello Kubernetes (updated)"; tags = @("k8s", "mongodb", "helm") }
if ($r.Code -ne 200) { throw "update failed" }

Step "5. DELETE  DELETE /articles/$id"
$r = Call DELETE "/articles/$id"
if ($r.Code -ne 204) { throw "delete failed" }

Step "6. READ after delete (expect 404)"
$r = Call GET "/articles/$id"
if ($r.Code -eq 404) { Write-Host "`nAll CRUD operations passed." -ForegroundColor Green }
