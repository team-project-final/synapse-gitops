# Final Release Hardening Phase D

> Scope: GitOps and release hardening for the final refactor completion plan.
> Source plan: `documents/docs/project-management/FINAL_REFACTOR_COMPLETION_PLAN.md` Phase D.

## Local Contract Check

Run this before opening a release-hardening PR:

```powershell
.\scripts\verify-phase-d-release-hardening.ps1
```

The script verifies:

- frontend/platform/engagement/knowledge/learning-card/learning-ai overlays pin images to the Synapse ECR repositories.
- dev Image Updater targets use semver-compatible tags.
- dev ApplicationSet keeps git write-back, kustomization write-back target, semver allow-tags, and per-service `image-updater-<svc>` branches.
- prod platform/engagement/knowledge/learning-card/learning-ai HPA/PDB manifests are wired into overlays.
- prod PDBs use `minAvailable: 2`, matching the W5 Step 12 runbook expectation.
- Terraform cost tags cover dev stack defaults and standalone ECR repositories.

If `kustomize` or `kubectl` is installed, include rendered overlay validation. The script uses `kustomize build` first and falls back to `kubectl kustomize`:

```powershell
.\scripts\verify-phase-d-release-hardening.ps1 -RunKustomize
```

## CI/Tool Check

The existing manifest CI remains the authoritative PR gate:

```bash
yamllint -c .yamllint apps/ argocd/ infra/
for o in apps/*/overlays/*/kustomization.yaml; do
  kustomize build "$(dirname "$o")" > /dev/null
done
for o in apps/*/overlays/*/kustomization.yaml; do
  kustomize build "$(dirname "$o")" | kubeconform -strict -ignore-missing-schemas -summary -output text
done
```

## Live Verification Checklist

These require AWS/EKS/ArgoCD access and are not satisfied by local checks alone:

- `argocd app list -l environment=dev`, `staging`, and `prod` show expected apps as Synced + Healthy.
- A semver ECR tag push creates/updates an `image-updater-<svc>` branch, opens the image-updater PR, and syncs dev after merge.
- `kubectl get hpa -n synapse-prod` shows concrete TARGETS, not `<unknown>`.
- `kubectl get pdb -n synapse-prod` shows all five service PDBs and allowed disruptions are sensible with current replicas.
- Cost Explorer/Resource Groups Tagging API shows no Synapse resources missing `Project=synapse`.

## Boundaries

- Product app design work remains in `synapse-frontend` and `documents/DESIGN.md`.
- Local Kubernetes/developer guide design work remains in this GitOps repo and `synapse-gitops/DESIGN.md`.
- Prod image promotion remains explicit PR-based; prod ApplicationSet intentionally has no Image Updater annotations.
