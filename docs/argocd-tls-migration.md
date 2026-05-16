# ArgoCD TLS 마이그레이션 — 옵션 2 → 옵션 1

옵션 2(NLB passthrough + self-signed)에서 옵션 1(ALB Ingress + ACM + Route53)로 전환하는 절차.

## 전제

- Route53에 hosted zone이 등록된 실 도메인 보유 (예: `synapse.example.com`)
- AWS Certificate Manager에서 인증서 발급 가능 (DNS 검증)
- EKS에 AWS Load Balancer Controller 설치 가능 (IRSA 필요)

## 단계

### 1. AWS Load Balancer Controller 설치

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=synapse-dev \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"=<IRSA_ROLE_ARN>
```

### 2. ACM 인증서 발급 (Terraform)

`infra/aws/dev/acm.tf` 신규:
```hcl
resource "aws_acm_certificate" "argocd" {
  domain_name       = "argocd.${var.domain}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "argocd_validation" {
  for_each = {
    for dvo in aws_acm_certificate.argocd.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "argocd" {
  certificate_arn         = aws_acm_certificate.argocd.arn
  validation_record_fqdns = [for r in aws_route53_record.argocd_validation : r.fqdn]
}
```

### 3. ArgoCD values 변경 (LoadBalancer → Ingress)

`infra/aws/dev/argocd.tf`의 `server` 블록 수정:
```hcl
server = {
  ...
  service = { type = "ClusterIP" }
  ingress = {
    enabled = true
    ingressClassName = "alb"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.argocd.arn
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
    hosts = ["argocd.${var.domain}"]
  }
  extraArgs = ["--insecure"]  # ALB에서 TLS 종료, ArgoCD는 HTTP
}
```

### 4. Route53 A 레코드 (ALB DNS alias)

```hcl
resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "argocd.${var.domain}"
  type    = "A"
  alias {
    name                   = data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb.argocd.zone_id
    evaluate_target_health = true
  }
}
```

### 5. 적용 + 검증

```bash
terraform apply
# ALB 프로비저닝 ~5분
curl -I https://argocd.<도메인>
# Expected: HTTP 200, 인증서 valid
```

### 6. PM 문서 갱신

- HISTORY: "ALB+ACM 마이그레이션 완료, FR-GO-102 완전 충족" 기록
- PRD W1 FR-GO-102: 충족 표시로 변경

## 롤백

문제 발생 시 5단계 직전 commit으로 `git revert` + `terraform apply`. NLB 옵션 2 상태로 복귀.
