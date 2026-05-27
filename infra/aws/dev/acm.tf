# staging-*.<domain> 와일드카드 ACM 인증서 + DNS(Route53) 검증 (A4).
# var.domain_name 이 비어있으면 count=0 → 라이브 hosted zone 확보 전까지 무동작(검증 안전).
# 산출 ARN은 infra/ingress/staging-ingress.yaml 의 alb.ingress.kubernetes.io/certificate-arn 에 치환.

resource "aws_acm_certificate" "staging" {
  count             = var.domain_name == "" ? 0 : 1
  domain_name       = "staging-*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "synapse-staging-wildcard"
    env  = "staging"
  }
}

resource "aws_route53_record" "staging_cert_validation" {
  for_each = var.domain_name == "" ? {} : {
    for dvo in aws_acm_certificate.staging[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "staging" {
  count                   = var.domain_name == "" ? 0 : 1
  certificate_arn         = aws_acm_certificate.staging[0].arn
  validation_record_fqdns = [for r in aws_route53_record.staging_cert_validation : r.fqdn]
}

output "staging_acm_certificate_arn" {
  description = "ACM cert ARN for staging ALB Ingress (empty until domain_name set)"
  value       = var.domain_name == "" ? "" : aws_acm_certificate.staging[0].arn
}
