# knowledge-svc 검색 — Elasticsearch 정합 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development 또는 superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** knowledge-svc 검색을 실제 동작하게 만든다 — 앱(Spring Data Elasticsearch, ES9 client)은 유지하고, 인프라(AWS·local-k8s)를 OpenSearch→**Elasticsearch**로 교체하며, env 변수명을 앱이 읽는 `ELASTICSEARCH_URIS`로 통일한다.

**배경(2026-06-04 조사, 메모리 `knowledge-search-opensearch-es-mismatch`):** 앱은 `spring-boot-starter-data-elasticsearch`(Boot 4.0 → ES Java client 9.x) + `spring.elasticsearch.uris:${ELASTICSEARCH_URIS:http://localhost:9200}`. 그러나 인프라는 OpenSearch(AWS 2.13/local 2.11)를 띄우고 env는 `OPENSEARCH_URL`로 주입 → **(1) env명 불일치로 앱이 localhost 폴백 (2) ES9 client product check가 OpenSearch 거부**. 양쪽 다 풀어야 검색 동작.

**결정(확정):**
- **D-1 env 통일 = `ELASTICSEARCH_URIS`** (앱 변수에 맞춤; 인프라/오버레이/local-k8s의 `OPENSEARCH_URL`을 전량 rename).
- **D-2 엔진 = Elasticsearch** (앱 유지, 인프라 교체).

**⚠️ 착수 전 확정 필요 (D-3 AWS ES 호스팅):** AWS 매니지드 Elasticsearch는 ES 7.10 이후 신규 도메인 불가(OpenSearch로 포크). ES 8/9는 **self-host만 가능**. 기본값(이 플랜): **EKS 인클러스터 ES StatefulSet**(local-k8s와 동형, 매니지드 불가 회피, 비용 최소). 대안: ECK 오퍼레이터(운영 정석, 오버헤드) / EC2 self-managed / Elastic Cloud(SaaS, 과금). dev는 인클러스터 권장, prod-grade는 ECK 재검토.

**Tech Stack:** Elasticsearch 9.2.x(`docker.elastic.co/elasticsearch/elasticsearch`), analysis-nori 플러그인(한국어), Kustomize overlays, EKS StatefulSet, Terraform(`infra/aws/dev`), `kubectl kustomize`/`python -m yamllint`.

**환경:** `C:/workspace/team-project-final/synapse-gitops`. 클러스터 부재 시 렌더/lint/`terraform validate`만(라이브는 EKS 윈도). 앱 변경은 `synapse-knowledge-svc`.

**버전 타겟:** ES **9.2.x** 서버(앱 client major 9.2.1 정합 — 메모리 kafka-service-audit/테스트 정렬 이력). testcontainers elasticsearch 1.21.3 이미 정렬됨.

---

## File Structure

**FS-A — local-k8s ES 교체** (gitops, 클러스터 불필요)
- Modify: `local-k8s/infra/opensearch.yaml` → `local-k8s/infra/elasticsearch.yaml`(rename, ES 이미지/env/Service)
- Modify: `local-k8s/infra/kustomization.yaml`(리소스 경로), `local-k8s/apps/knowledge-svc/kustomization.yaml`(env명)

**FS-B — env 변수명 통일** (gitops overlays)
- Modify: `apps/knowledge-svc/overlays/{dev,staging,prod}/kustomization.yaml`(`OPENSEARCH_URL`→`ELASTICSEARCH_URIS`)
- Modify: `apps/knowledge-svc/overlays/prod/netpol.yaml`(포트/대상 정합)

**FS-C — AWS ES 호스팅** (D-3 기본값: 인클러스터 StatefulSet)
- Delete: `infra/aws/dev/opensearch.tf`(매니지드 OpenSearch 제거)
- **선행(GAP-1)**: `data "aws_caller_identity" "current"`가 `opensearch.tf:1`에만 선언되고 `velero.tf:6`이 소비 → 삭제 전 `main.tf`로 이동 필수(아니면 terraform validate 실패).
- Modify: `infra/aws/dev/vpc.tf`(GAP-2 — `aws_security_group.opensearch`는 `vpc.tf:226-250`에 있음, `security_groups.tf` 파일 없음), `infra/aws/dev/variables.tf`(`var.opensearch_instance_type` 제거), `infra/aws/dev/outputs.tf`(GAP-3 — `opensearch_endpoint`/`opensearch_dashboard_endpoint`/`sg_opensearch_id` 3개 output 삭제)
- Create: `apps/elasticsearch/`(base StatefulSet+Service+PVC) + `overlays/dev`(local-k8s 패턴 EKS 이식), `argocd/applicationset.yaml` 등록

**FS-D — nori 분석기** (ES 한국어)
- Create: `apps/elasticsearch/Dockerfile` 또는 initContainer로 `elasticsearch-plugin install analysis-nori`(또는 nori 포함 커스텀 이미지)

**FS-E — 검증/테스트 재활성**
- Modify(app): `synapse-knowledge-svc` — CI 비활성된 `SearchElasticsearchIntegrationTest` 재활성

---

## FS-A: local-k8s Elasticsearch 교체 (먼저 — 클러스터 불필요)

브랜치: `feat/knowledge-search-elasticsearch`

### Task A1: local-k8s ES manifest 작성

**Files:** Create `local-k8s/infra/elasticsearch.yaml`, Delete `local-k8s/infra/opensearch.yaml`

- [ ] **Step 1: ES Deployment+Service 작성** (opensearch.yaml를 ES로 치환)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: elasticsearch, labels: { app: elasticsearch } }
spec:
  replicas: 1
  selector: { matchLabels: { app: elasticsearch } }
  template:
    metadata: { labels: { app: elasticsearch } }
    spec:
      containers:
        - name: elasticsearch
          # nori 포함 커스텀(FS-D). 임시: 공식 + initContainer 플러그인 설치
          image: docker.elastic.co/elasticsearch/elasticsearch:9.2.1
          env:
            - { name: discovery.type, value: single-node }
            - { name: xpack.security.enabled, value: "false" }
            - { name: ES_JAVA_OPTS, value: "-Xms256m -Xmx256m" }
            - { name: bootstrap.memory_lock, value: "false" }
          ports: [ { containerPort: 9200 } ]
          readinessProbe:
            httpGet: { path: /_cluster/health, port: 9200 }
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            tcpSocket: { port: 9200 }
            initialDelaySeconds: 60
            periodSeconds: 20
            failureThreshold: 5
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { cpu: 1000m, memory: 1Gi }
---
apiVersion: v1
kind: Service
metadata: { name: elasticsearch }
spec:
  selector: { app: elasticsearch }
  ports: [ { port: 9200, targetPort: 9200 } ]
```
- [ ] **Step 2: 옛 opensearch.yaml 삭제** `git rm local-k8s/infra/opensearch.yaml`.
- [ ] **Step 3: kustomization 갱신** `local-k8s/infra/kustomization.yaml`에서 `opensearch.yaml`→`elasticsearch.yaml`.
- [ ] **Step 4: 렌더** `kubectl kustomize local-k8s/infra >/dev/null && echo OK` (또는 local-k8s 루트 kustomization 경로).

### Task A2: local-k8s knowledge-svc env 정합

**Files:** Modify `local-k8s/apps/knowledge-svc/kustomization.yaml`

- [ ] **Step 1: env 교체** — `OPENSEARCH_URL: http://opensearch:9200` → `ELASTICSEARCH_URIS: http://elasticsearch:9200`.
- [ ] **Step 2: 렌더 + 커밋** `kubectl kustomize local-k8s/apps/knowledge-svc >/dev/null && echo OK`; commit `feat(local-k8s): OpenSearch→Elasticsearch 9.2.1 교체 + knowledge ELASTICSEARCH_URIS 정합`.

## FS-D: nori 한국어 분석기 (검색 정확도 벤치마크가 nori 의존)

**Files:** Create `apps/elasticsearch/Dockerfile` (또는 initContainer)

- [ ] **Step 1: nori 포함 이미지** — 검색 벤치마크(`search-benchmark-notes.json`의 `nori`/한국어)가 의존. 공식 ES 이미지엔 nori 미포함 → 빌드:
```dockerfile
FROM docker.elastic.co/elasticsearch/elasticsearch:9.2.1
RUN bin/elasticsearch-plugin install --batch analysis-nori
```
ECR/레지스트리에 push 후 local-k8s·EKS 매니페스트 이미지를 이걸로 교체. (initContainer로 emptyDir에 설치하는 대안도 가능하나 재시작마다 재설치 → 커스텀 이미지 권장.)
- [ ] **Step 2: local-k8s·EKS ES 이미지 참조를 nori 이미지로 변경 + 렌더.**

## FS-B: env 변수명 통일 (gitops overlays — 클러스터 불필요)

### Task B1: dev/staging/prod 오버레이 env rename

**Files:** Modify `apps/knowledge-svc/overlays/{dev,staging,prod}/kustomization.yaml`

- [ ] **Step 1: 각 오버레이의 `OPENSEARCH_URL` patch를 `ELASTICSEARCH_URIS`로 변경.** 값은 FS-C 호스팅 결정 따라:
  - 인클러스터 ES(D-3 기본): `http://elasticsearch.synapse-dev.svc:9200`(ns별 staging/prod 동형, http 또는 TLS).
  - (옛 AWS OpenSearch 엔드포인트 `https://vpc-...es.amazonaws.com`는 제거.)
- [ ] **Step 2: 렌더 확인** — `kubectl kustomize apps/knowledge-svc/overlays/dev | grep -i ELASTICSEARCH_URIS` 로 값 확인, `OPENSEARCH_URL` 잔존 0 확인.

### Task B2: prod netpol 포트/대상 정합

**Files:** Modify `apps/knowledge-svc/overlays/prod/netpol.yaml`

- [ ] **Step 1: OpenSearch egress(VPC ipBlock 443) → ES 경로로 변경.** 인클러스터 ES면 동일 ns podSelector(`app: elasticsearch`):9200 egress 허용(기존 intra-ns 규칙으로 커버되는지 확인, 아니면 추가). 주석 `OpenSearch(443)`도 `Elasticsearch(9200)`로 갱신.
- [ ] **Step 2: 렌더 + lint + 커밋** `feat(knowledge): OPENSEARCH_URL→ELASTICSEARCH_URIS 통일 + netpol ES 포트 정합 (D-1)`.

## FS-C: AWS ES 호스팅 (D-3 — 기본값: EKS 인클러스터 StatefulSet)

> ⚠️ D-3 미확정 시 이 FS 보류. 인클러스터 StatefulSet 기준으로 기술.

### Task C1: ES Application(gitops) 신설

**Files:** Create `apps/elasticsearch/base/{statefulset,service,kustomization}.yaml` + `overlays/dev/kustomization.yaml`

- [ ] **Step 1: ES StatefulSet 작성** — local-k8s Deployment를 EKS용 StatefulSet으로(PVC gp3 volumeClaimTemplate, nori 이미지, `xpack.security.enabled`는 dev=false, prod=true+ESO 시크릿 후속). Service `elasticsearch:9200`.
- [ ] **Step 2: overlays/dev** — namespace synapse-dev, 리소스 요청/스토리지 사이징.
- [ ] **Step 3: `argocd/applicationset.yaml`에 `- service: elasticsearch` 추가**(image-updater는 커스텀 nori 이미지라 ECR semver 정책 검토).
- [ ] **Step 4: 렌더 회귀** — `for d in apps/*/overlays/*; do kubectl kustomize "$d">/dev/null && echo OK $d; done`.

### Task C2: 매니지드 OpenSearch 제거 (terraform)

**Files:** Delete `infra/aws/dev/opensearch.tf`; Modify `infra/aws/dev/{security_groups,variables}.tf`

- [ ] **Step 1: `opensearch.tf` 삭제** + `aws_security_group.opensearch`·`var.opensearch_instance_type` 등 참조 제거. netpol 등 다른 코드가 OpenSearch SG/엔드포인트 참조하는지 grep 후 정리.
- [ ] **Step 2: `terraform fmt && terraform validate`** → Success. (apply/plan은 EKS 윈도; state에서 도메인 destroy는 라이브.)
- [ ] **Step 3: 커밋** `feat(infra): 매니지드 OpenSearch 제거 — ES 인클러스터로 전환 (D-2/D-3)`.

## FS-E: 검증

### Task E1: 통합 테스트 재활성 (app 레포)

**Files:** Modify `synapse-knowledge-svc` — `SearchElasticsearchIntegrationTest`

- [ ] **Step 1: CI 비활성 해제** — testcontainers elasticsearch 1.21.3가 ES 서버를 띄우므로(OpenSearch 비호환 이슈 해소), `@Disabled`/CI skip 제거. 로컬/CI green 확인. 커밋 + dev PR.

### Task E2: EKS 윈도 E2E (이월)

- [ ] **Step 1:** EKS dev에서 knowledge-svc 파드가 `elasticsearch:9200` 연결(`spring.elasticsearch.uris` 정상), 노트 색인 + BM25/nori 검색 200, 검색 정확도 벤치마크 통과. ES9 client product check 통과(ES 서버라 OK).

---

## 의존성 / 권장 순서

```
FS-A (local-k8s ES)         ── 클러스터 불필요, 즉시. local 개발자 검색 즉시 정상화 ◀ 1순위
FS-B (env 통일)             ── 클러스터 불필요. FS-C 호스팅 값에 의존(인클러스터 svc 주소) ◀ 2순위
FS-D (nori 이미지)          ── 빌드+push 필요. FS-A/C 이미지 참조 선행
FS-C (AWS ES 호스팅)        ── D-3 확정 후. terraform validate로 머지, 라이브는 EKS 윈도
FS-E (테스트/E2E)           ── 위 머지 후. E2E는 EKS 윈도
```

- **D-1(env)은 단독으로도 가치**: `OPENSEARCH_URL`→`ELASTICSEARCH_URIS` rename만으로 "앱이 받는 변수명" 정합(현재는 무조건 localhost 폴백). 단 엔진이 OpenSearch인 채 rename만 하면 갭2(ES client 거부)는 남음 → FS-A/C(엔진 교체)와 함께해야 실제 동작.
- local-k8s(FS-A)는 매니지드 의존 없어 가장 먼저 정상화 가능 → 로컬 검증으로 엔진 교체 타당성 선확인 후 AWS(FS-C) 진행 권장.

## Self-Review

**Spec 커버리지:** D-1 env 통일 → FS-B ✓. D-2 엔진 ES → FS-A(local)+FS-C(AWS) ✓. nori 한국어 → FS-D ✓. 테스트 재활성 → FS-E ✓. D-3(AWS 호스팅)은 상단 + FS-C에 결정 플래그.
**미해결:** D-3 AWS ES 호스팅(인클러스터/ECK/EC2/SaaS) — 기본값 인클러스터로 작성, 확정 필요. prod ES 보안(xpack security + ESO 시크릿)은 dev 이후 후속.
**일관성:** env명 `ELASTICSEARCH_URIS`(앱 `spring.elasticsearch.uris` 정합), Service `elasticsearch:9200`, ES 9.2.1(client major 정합), nori 플러그인 명시.

---

## 완전성 보완 — cross-repo 전수 검토 (2026-06-04)

> 전 레포 스캔 + gitops/shared 정밀 검토로 도출. 위 FS에 누락됐던 항목을 등급별로 정리. **GAP-1~3은 terraform validate 차단**이라 FS-C 선행 필수.

### gitops — CRITICAL (terraform validate 차단)
- **GAP-1** `data "aws_caller_identity" "current"`: `opensearch.tf:1`에만 선언·`velero.tf:6`이 소비(velero.tf에 "재정의 금지" 주석 존재) → opensearch.tf 삭제 전 `main.tf`로 이동.
- **GAP-2** `aws_security_group.opensearch`: `vpc.tf:226-250`에 위치(플랜이 적었던 `security_groups.tf`는 **존재하지 않음**) → vpc.tf에서 삭제.
- **GAP-3** `outputs.tf:74-82,112-115`: `opensearch_endpoint`·`opensearch_dashboard_endpoint`·`sg_opensearch_id` 3개 output이 삭제될 리소스 참조 → 삭제.

### gitops — HIGH (기능)
- **GAP-4/5** learning-ai도 `OPENSEARCH_URL` 주입(앱은 pgvector라 무시하나 dead/오류 값): `apps/learning-ai/overlays/{dev,staging,prod}/kustomization.yaml`, `local-k8s/apps/learning-ai/kustomization.yaml:22` → 키 제거(또는 learning-ai 실제 키로 정리). FS-A/FS-B 범위에 추가.
- **GAP-15** `docker-compose.yml`은 **이미 Elasticsearch 8.13.0**(`SPRING_ELASTICSEARCH_URIS`) 사용 — local-k8s(minikube)와 AWS terraform만 OpenSearch. 단 docker-compose의 learning-ai는 `ELASTICSEARCH_URL`(≠URIS) → learning-ai env명 단일화 필요(앱 실제 키 확인).

### gitops — MEDIUM/LOW (주석·문서·런북·모니터링)
- **GAP-9** prod netpol 5종 "OpenSearch(443)" 주석 + VPC ipBlock:443 egress: knowledge(FS-B 커버) 외 `apps/{learning-ai,learning-card,platform-svc,engagement-svc}/overlays/prod/netpol.yaml` → 주석 Elasticsearch(9200)로, 인클러스터 ES면 ipBlock:443 규칙 정리.
- **GAP-6/7/8** 런북 OpenSearch 절차 obsolete: `w2-session-bootstrap-runbook.md:43,156-158`(service-linked role + SG ingress 명령), `step3-terraform-apply.md`, `troubleshooting-infra.md`, `w2-terraform-apply-quickstart.md`, `step4-dev-overlay.md:20`(OPENSEARCH_URL), `networkpolicy-validation.md`, `step1-aws-account-setup.md:29`(비용표).
- **GAP-11/12/13** 가이드/핸드오프: `docs/synapse-developer-guide.md`(8곳), `docs/local-k8s-guide.html`·`docs/local-msa-setup.html`, `argocd/README.md:58`, `HANDOFF_W3/W4`, `scripts/minikube-up.sh:9` 주석 + `site/assets/` 재빌드.
- **GAP-14** ES 클러스터 헬스 모니터링 부재: 인클러스터 ES StatefulSet용 PrometheusRule(yellow/red status)·ServiceMonitor 신설 검토.

### synapse-shared — 추가/수정/보완 (별도 레포 PR)
- **ADD** `docs/designs/D-003_SEARCH_ENGINE_DECISION.md` 신설 — ES 결정 단일 출처 ADR(D-001/D-002 패턴). **최고 레버리지**.
- **FIX** `.env.example`: `OPENSEARCH_URL=http://opensearch:9200` → `ELASTICSEARCH_URIS=http://elasticsearch:9200`(로컬 온보딩 계약).
- **FIX** `docker-compose.yml`: `opensearchproject/opensearch:2.11.0` 서비스 → `docker.elastic.co/elasticsearch/elasticsearch`(ES_JAVA_OPTS·volume·knowledge depends_on·container명).
- **FIX** `docs/guides/EVENT_FLOW_MATRIX.md:30,96,99`: consumer `opensearch` → `knowledge-svc (ES indexer)`/`Elasticsearch`(opensearch는 Kafka consumer가 아니었음 — 개념 오류 정정).
- **FIX** E2E/스크립트: `docs/guides/E2E_SCENARIOS_W3.md`(S4), `scripts/kafka-e2e-test.sh:199`, `docs/reports/SLA_VERIFICATION_W4.md:44`.
- **FIX** 테크스택/PM: `KICKOFF.md:45`(OpenSearch 8→Elasticsearch), PRD_W1, HANDOFF_HUB/SHARED, team-lead WORKFLOW/TASK.
- **SUPPLEMENT** `docs/guides/EVENT_CONTRACT_STANDARD.md`: note-updated-v1 consumer = knowledge-svc ES indexer 명시. (Avro 스키마는 엔진 무관 — 변경 불요.)

### 권장 순서 보완
FS-A(local-k8s) → FS-B(env, learning-ai 포함) → shared `.env.example`+docker-compose(로컬 정합) → FS-C(terraform, GAP-1~3 선행) → 문서·런북 sweep + shared 나머지 + D-003 ADR → FS-E/E2E.
