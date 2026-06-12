# infra/aws/ecr — ECR 레포 standalone 스택

서비스 7종 + `synapse/elasticsearch` ECR 레포의 IaC 정본 (#182).

## 왜 dev 스택과 분리?

`infra/aws/dev`는 라이브 윈도우마다 `bring-up.sh --destroy`로 전체 파괴된다.
ECR을 그 스택에 넣으면 **teardown마다 레포·이미지가 삭제**되어 다음 bring-up이
ImagePullBackOff로 시작한다(#182 근본 원인 2 재발). 별도 state(`ecr/terraform.tfstate`)로
윈도우 수명주기와 무관하게 유지한다. `prevent_destroy`로 이중 보호.

## 기존(수동 생성) 레포 흡수 — 최초 1회

```bash
cd infra/aws/ecr
terraform init
for r in elasticsearch engagement-svc frontend gateway knowledge-svc learning-ai learning-card platform-svc; do
  terraform import "aws_ecr_repository.this[\"synapse/$r\"]" "synapse/$r"
done
terraform plan   # 변경 0건(또는 tags 추가만)이어야 정상
terraform apply
```
