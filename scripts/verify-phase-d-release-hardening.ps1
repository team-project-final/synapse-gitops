param(
  [switch]$RunKustomize
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ecrPrefix = "963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse"
$phaseDServices = @(
  "frontend",
  "platform-svc",
  "engagement-svc",
  "knowledge-svc",
  "learning-card",
  "learning-ai"
)
$devImageUpdaterServices = @(
  "frontend",
  "gateway",
  "platform-svc",
  "engagement-svc",
  "knowledge-svc",
  "learning-card",
  "learning-ai"
)
$prodAvailabilityServices = @(
  "platform-svc",
  "engagement-svc",
  "knowledge-svc",
  "learning-card",
  "learning-ai"
)

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
  $script:failures.Add($Message) | Out-Null
}

function Add-WarningMessage([string]$Message) {
  $script:warnings.Add($Message) | Out-Null
}

function Read-RepoFile([string]$RelativePath) {
  $path = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    Add-Failure "Missing file: $RelativePath"
    return $null
  }
  return Get-Content -Raw -LiteralPath $path
}

function Get-FirstMatch([string]$Text, [string]$Pattern) {
  if ($null -eq $Text) {
    return $null
  }
  $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if ($match.Success) {
    return $match.Groups[1].Value.Trim()
  }
  return $null
}

function Assert-Contains([string]$Text, [string]$Expected, [string]$Context) {
  if ($null -eq $Text -or -not $Text.Contains($Expected)) {
    Add-Failure "$Context missing expected text: $Expected"
  }
}

Write-Host "== Phase D release hardening checks =="

foreach ($service in $phaseDServices) {
  foreach ($env in @("dev", "staging", "prod")) {
    $relativePath = "apps/$service/overlays/$env/kustomization.yaml"
    $text = Read-RepoFile $relativePath
    if ($null -eq $text) {
      continue
    }

    $newName = Get-FirstMatch $text '^\s*newName:\s*"?([^"\r\n]+)"?'
    $newTag = Get-FirstMatch $text '^\s*newTag:\s*"?([^"\r\n]+)"?'
    $expectedImage = "$ecrPrefix/$service"

    if ($newName -ne $expectedImage) {
      Add-Failure "$relativePath image newName is '$newName', expected '$expectedImage'"
    }
    if ([string]::IsNullOrWhiteSpace($newTag)) {
      Add-Failure "$relativePath missing non-empty newTag"
    }
  }
}

foreach ($service in $devImageUpdaterServices) {
  $relativePath = "apps/$service/overlays/dev/kustomization.yaml"
  $text = Read-RepoFile $relativePath
  $newTag = Get-FirstMatch $text '^\s*newTag:\s*"?([^"\r\n]+)"?'
  if ($newTag -and $newTag -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    Add-Failure "$relativePath dev newTag '$newTag' is not semver, but dev Image Updater uses semver"
  }
}

$devApplicationSet = Read-RepoFile "argocd/applicationset.yaml"
foreach ($service in $devImageUpdaterServices) {
  Assert-Contains $devApplicationSet "- service: $service" "argocd/applicationset.yaml"
}
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/app.update-strategy: semver' "dev ApplicationSet"
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/app.allow-tags: "regexp:^[0-9]+\\.[0-9]+\\.[0-9]+$"' "dev ApplicationSet"
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/write-back-method: git' "dev ApplicationSet"
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/write-back-target: kustomization' "dev ApplicationSet"
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/app.kustomize.image-name: "ghcr.io/team-project-final/synapse-{{service}}"' "dev ApplicationSet"
Assert-Contains $devApplicationSet 'argocd-image-updater.argoproj.io/git-branch: "main:image-updater-{{service}}"' "dev ApplicationSet"

foreach ($service in $prodAvailabilityServices) {
  $pdbPath = "apps/$service/overlays/prod/pdb.yaml"
  $pdb = Read-RepoFile $pdbPath
  $minAvailable = Get-FirstMatch $pdb '^\s*minAvailable:\s*([0-9]+)'
  if ($minAvailable -ne "2") {
    Add-Failure "$pdbPath minAvailable is '$minAvailable', expected '2'"
  }

  $hpaPath = "apps/$service/overlays/prod/hpa.yaml"
  $hpa = Read-RepoFile $hpaPath
  Assert-Contains $hpa "kind: HorizontalPodAutoscaler" $hpaPath
  Assert-Contains $hpa "minReplicas: 3" $hpaPath
  Assert-Contains $hpa "maxReplicas: 6" $hpaPath
  Assert-Contains $hpa "averageUtilization: 70" $hpaPath

  $prodKustomization = Read-RepoFile "apps/$service/overlays/prod/kustomization.yaml"
  Assert-Contains $prodKustomization "- pdb.yaml" "apps/$service/overlays/prod/kustomization.yaml"
  Assert-Contains $prodKustomization "- hpa.yaml" "apps/$service/overlays/prod/kustomization.yaml"
}

$devTerraform = Read-RepoFile "infra/aws/dev/main.tf"
Assert-Contains $devTerraform "default_tags" "infra/aws/dev/main.tf"
Assert-Contains $devTerraform "Project" "infra/aws/dev/main.tf"
Assert-Contains $devTerraform "Environment" "infra/aws/dev/main.tf"
Assert-Contains $devTerraform "ManagedBy" "infra/aws/dev/main.tf"

$ecrTerraform = Read-RepoFile "infra/aws/ecr/main.tf"
Assert-Contains $ecrTerraform 'Environment = "shared"' "infra/aws/ecr/main.tf"
Assert-Contains $ecrTerraform "Service     = each.value" "infra/aws/ecr/main.tf"
Assert-Contains $ecrTerraform "prevent_destroy = true" "infra/aws/ecr/main.tf"

if ($RunKustomize) {
  $kustomize = Get-Command kustomize -ErrorAction SilentlyContinue
  $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
  if ($null -eq $kustomize -and $null -eq $kubectl) {
    Add-WarningMessage "Neither kustomize nor kubectl was found; skipped overlay build."
  } else {
    $overlays = Get-ChildItem -Path (Join-Path $repoRoot "apps") -Recurse -Filter "kustomization.yaml" |
      Where-Object { $_.FullName -match "\\overlays\\" }
    foreach ($overlay in $overlays) {
      $dir = Split-Path -Parent $overlay.FullName
      Push-Location $dir
      try {
        if ($null -ne $kustomize) {
          & $kustomize.Source build "." *> $null
        } else {
          & $kubectl.Source kustomize "." *> $null
        }
        if ($LASTEXITCODE -ne 0) {
          Add-Failure "kustomize build failed: $($overlay.FullName.Substring($repoRoot.Path.Length + 1))"
        }
      } finally {
        Pop-Location
      }
    }
  }
} else {
  Add-WarningMessage "kustomize build not requested. Rerun with -RunKustomize in a tool-ready environment."
}

if ($warnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Warnings:"
  foreach ($warning in $warnings) {
    Write-Host "  - $warning"
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Failures:"
  foreach ($failure in $failures) {
    Write-Host "  - $failure"
  }
  exit 1
}

Write-Host ""
Write-Host "Phase D release hardening checks passed."
