# 설계: W5 일정 문서 동기화 + 후속 추적 + Kafka/DB 자동 프로비저닝

> **작성**: 2026-06-10 · **담당**: @VelkaressiaBlutkrone
> **상태**: 승인 완료(브레인스토밍) → 플랜 작성 대기
> **관련**: [HANDOFF_2026-06-09-followups](../HANDOFF_2026-06-09-followups.md) · [TASK_gitops](../../project-management/task/TASK_gitops.md) · [HANDOFF_W5](../HANDOFF_W5.md)

---

## 0. 배경 / 문제

W5 잔여 백로그는 2026-06-09 라이브 윈도우로 전부 완주(OPEN 이슈 0건, #144 포함 close). 그러나 두 가지 부채가 남았다.

1. **일정 문서가 현실과 어긋남(stale)**: 작업은 완료됐으나 PM 추적 문서 4종이 미갱신.
2. **저우선 후속 3건이 추적되지 않음**: 핸드오프 문서에만 기록, 이슈/일정 문서에 미반영.

또한 후속 C(Kafka 토픽·DB 자동 프로비저닝)는 라이브 윈도우 없이 **오프라인 코드 작업이 가능한 유일한 후속**이다.

### 제약 (확정 결정)
- **라이브 윈도우 없음**: 클러스터는 destroy 상태(과금 0). A/B의 라이브 검증은 다음 윈도우로 패키징. (사용자 결정: "오프라인 준비만")
- **후속 C는 실제 코딩까지** 진행. (사용자 결정)
- **후속 A/B/C는 GitHub 이슈로 추적**. (사용자 결정)
- **후속 C 접근법: A(클러스터 내 Job) 기본 + C(토픽 리스트 단일 파일)로 drift 해소**. (사용자 결정)

---

## 1. 범위

### In Scope
- 파트 1: 일정 문서 4종 동기화 + GitHub 이슈 3건 생성
- 파트 2: 후속 C 구현 — `bring-up.sh`에 토픽/DB 프로비저닝 phase 추가 + 토픽 리스트 단일 출처화

### Out of Scope
- 후속 A(learning-card-staging 근본원인) 실제 조사 — 라이브 필요, 이슈+체크리스트만
- 후속 B(SHA vs semver 전략) 실제 적용 — 팀 결정 필요, 이슈+옵션 정리만
- 후속 C의 라이브 실행 검증 — 다음 윈도우 (오프라인은 `--dry-run`/`bash -n`/`kubectl --dry-run=client`까지)
- shared 레포(`deploy-service.yml`, `EVENT_CONTRACT_STANDARD`) 변경 — 크로스레포, 본 작업 범위 밖

---

## 2. 파트 1 — 일정 문서 동기화

### 2.1 대상 문서 4종

| 문서 | 현재 상태 | 변경 |
|------|-----------|------|
| `docs/project-management/workflow/WORKFLOW_gitops_W5.md` | Step 11/12 전 항목 미체크 | 완료 항목 `[x]` 체크, Step 11 Status → Done, Step 12 Status → In Progress(일부), 미완 항목은 사유 주석 |
| `docs/project-management/task/TASK_gitops.md` | Step 11 "In Progress", Step 12 "Not Started" | Step 11 Status → **Done**(team-lead 따라하기는 #155 드릴로 충족 처리), Step 12 Status 현행화, **후속 A/B/C 추적 섹션** 신설, #144 최종 close 반영 |
| `docs/superpowers/HANDOFF_W5.md` | #144를 "⚠️ OPEN"으로 기재 | #144 → **✅ CLOSED**(재수정 `9140e597`로 learning-ai 1/1 Running·ssl_context 0건), §2/§4/§5 정합 |
| `docs/project-management/history/HISTORY_gitops.md` | 2026-06-08(윈도우2)까지만 | **2026-06-09 엔트리 추가**(잔여 5건 완주·#144 close·PR #158~#163) + **2026-06-10 엔트리**(문서 동기화·후속 3건 이슈화·후속 C 구현) |

**원칙(D-041 정책 준수)**: 미체크 박스를 이동/체크할 때 원자리에 HTML 주석으로 사유·날짜를 남긴다(기존 문서 관례). Status 라인은 `[x] Done` 통일 + "X항목 이월/후속" 메모.

### 2.2 GitHub 이슈 3건

각 이슈는 핸드오프 §2의 내용(증상·정적분석·next-action·우선순위)을 본문에 담는다.

| 이슈 | 제목(안) | 라벨/우선순위 | 핵심 next-action |
|------|----------|---------------|------------------|
| 후속 A | `[ops] learning-card-staging Degraded 근본원인 조사 (라이브)` | 낮음 | 라이브 윈도우에서 `kubectl logs deploy/learning-card --previous`. 가설 3종(dev-latest 태그/staging 프로파일/replica 2) |
| 후속 B | `[ops] learning-ai·card semver 재핀 — SHA vs semver 태깅 전략 결정` | 낮음 | 팀과 deploy-service.yml(b) vs IU digest 전략(c) 결정 → 일괄 적용 |
| 후속 C | `[infra] bring-up Kafka 토픽 9종 + DB 5종 자동 프로비저닝` | 낮음~중 | 본 스펙 파트 2로 **구현**, 라이브 검증만 다음 윈도우 |

- 후속 C 이슈는 본 작업으로 코드가 완료되므로, PR 머지 시 "라이브 검증 대기" 상태로 OPEN 유지(다음 윈도우에서 close).
- 생성 후 이슈 번호를 `TASK_gitops.md` 후속 추적 섹션과 `HISTORY` 2026-06-10 엔트리에 역링크.

---

## 3. 파트 2 — 후속 C 구현: Kafka 토픽 + DB 자동 프로비저닝

### 3.1 문제 재정의

`bring-up.sh`는 다음을 자동생성하지 않아 매 윈도우 수동 작업 + 앱 크래시를 유발:
- **MSK 토픽 9종** 미생성 → learning-ai(aiokafka) 컨슈머 `UnknownTopicOrPartitionError` CrashLoop (Spring은 경고만)
- **서비스 DB 5종**(`synapse_platform/engagement/knowledge/learning/ai`) 미생성 → Spring `database does not exist` 크래시

### 3.2 네트워크 제약 (설계 근거)

bring-up은 **SSM 터널 경유 `kubectl`**로 동작한다. MSK(9094)·RDS(5432)는 private subnet에 있어 **bring-up 실행 호스트에서 직접 도달 불가**. 따라서 프로비저닝은 **클러스터 내부 Job/Pod**로 실행해야 네트워크가 정합한다(MSK/RDS는 클러스터 노드에서 도달 가능). → 접근법 A 채택 근거.

기존 `kafka-topics` terraform은 bastion 실행 전제(README §전제)라 bring-up 호스트에서 못 돌린다 → bring-up 통합엔 부적합. (접근법 B 기각 근거.)

### 3.3 토픽 리스트 단일 출처화 (C 하이브리드)

**현재 drift 위험**: 토픽 이름이 3곳에 흩어짐 —
1. `infra/aws/dev/kafka-topics/main.tf` `locals.topics` (9종, terraform 정본)
2. `scripts/kafka-init/create-topics.sh` (5종, 로컬 docker-compose 전용·부분)
3. (신설 시) 클러스터 Job → 4번째 복사본 위험

**해소**: 평문 리스트 파일을 단일 출처로 추출.

```
infra/kafka/topics.txt        # 9줄, 토픽명 1줄당 1개 (주석 # 허용)
```

- **terraform**: `main.tf`의 `locals.topics` 인라인 배열 → `split("\n", file("${path.module}/../../../../kafka/topics.txt"))` + 공백/주석 필터로 대체. (선언 정본 유지, 값만 파일에서.)
- **bring-up Job**: 같은 파일을 `kubectl create configmap`으로 적재 → Job이 ConfigMap에서 읽어 `--if-not-exists` 생성.
- 로컬 `create-topics.sh`(docker-compose, PLAINTEXT 5종)는 **범위 밖**(로컬은 SSL/9종 불필요, 별도 트랙). 단 topics.txt 상단 주석에 "이 파일이 MSK/EKS 정본, 로컬 compose는 별도"를 명시.

> 검증: terraform 변경은 `terraform -chdir=infra/aws/dev/kafka-topics validate`로 파싱 확인(provider init 불필요 범위). 라이브 apply는 다음 윈도우.

### 3.4 bring-up.sh phase 신설

`PHASES` 배열에서 `kafka-config` 다음, `manifests` 앞에 2개 phase 삽입(앱은 `manifests`의 ApplicationSet으로 배포되므로 그 전에 토픽·DB가 있어야 함):

```
... alb-controller kafka-config  kafka-topics  db-init  manifests metrics-server ...
                                 └─ 신설 ─┘
```

#### phase_kafka_topics
- 토픽 리스트 ConfigMap 적재(`infra/kafka/topics.txt` → cm `kafka-topics-list`, ns `synapse-dev`)
- `apache/kafka:3.9.0` 기반 Job:
  - SSL client.properties(`security.protocol=SSL`) 생성
  - 브로커 = `terraform output -raw msk_bootstrap_brokers_tls`(기존 `phase_kafka_config`와 동일 소스)를 env로 주입
  - ConfigMap의 각 토픽에 대해 `kafka-topics.sh --create --if-not-exists --partitions 3 --replication-factor 2 --config min.insync.replicas=2 --config retention.ms=604800000` (terraform 파라미터와 정합)
- 멱등: `--if-not-exists`. Job `backoffLimit` 제한 + `kubectl wait --for=condition=complete`.

#### phase_db_init
- 대상 RDS 2개: dev(`infra/aws/dev` output) + staging 전용 RDS(`synapse-staging-postgres`, #156로 분리됨). 각 endpoint는 terraform output에서 취득.
- `postgres:16` 기반 Job:
  - master 자격: dev는 `TF_VAR_rds_password`(bring-up 호스트가 이미 보유, phase_terraform 전제) 또는 AWS SM. staging RDS 자격원 확인 필요(구현 시 terraform/SM 경로 확정).
  - 멱등 생성: psql `SELECT 'CREATE DATABASE <db>' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='<db>') \gexec` 패턴으로 DB 5종.
- DB 목록: `synapse_platform`, `synapse_engagement`, `synapse_knowledge`, `synapse_learning`, `synapse_ai`.

#### 공통 규약 (기존 bring-up 패턴 준수)
- `--dry-run`: 명령만 출력(`if $DRY_RUN; then echo ...; return; fi`)
- `--from`/`--to`: 새 phase 이름이 `usage()` 도움말 + PHASES 배열에 등재되어 재개/부분실행 동작
- `--destroy`/`--verify` 흐름 불변
- 실패 시 `err` + 적절한 exit, 부분 성공은 `warn`

### 3.5 검증 (오프라인 한정)

라이브 윈도우가 없으므로:
1. `bash -n scripts/bring-up.sh` — 문법
2. `bash scripts/bring-up.sh --dry-run --from kafka-topics --to db-init` — phase 인식·명령 출력 확인
3. Job YAML은 heredoc → `kubectl apply --dry-run=client -f -` 경로로 스키마 확인(가능 범위)
4. `terraform -chdir=infra/aws/dev/kafka-topics validate` — topics.txt 추출 파싱
5. `shellcheck`(가용 시) — 회귀 없음

**실제 토픽/DB 생성 + 앱 Healthy 검증은 다음 라이브 윈도우**(후속 C 이슈에 명시, 그때 close).

---

## 4. 컴포넌트 경계 / 의존

| 단위 | 책임 | 입력 | 출력 |
|------|------|------|------|
| `infra/kafka/topics.txt` | 토픽명 단일 출처 | — | 9줄 토픽 리스트 |
| `kafka-topics/main.tf` | MSK 토픽 선언(terraform) | topics.txt | kafka_topic 리소스 |
| `phase_kafka_topics` | 클러스터 내 토픽 생성 | topics.txt(cm), MSK 브로커 | 토픽 9종(멱등) |
| `phase_db_init` | 클러스터 내 DB 생성 | RDS endpoint·자격 | DB 5종(멱등) |
| 문서 4종 | W5 현실 반영 | 실제 완료 사실 | 정합된 추적 문서 |
| 이슈 3건 | 후속 추적 | 핸드오프 §2 | A/B/C 추적 + 역링크 |

각 단위는 독립 검증 가능(topics.txt는 라인 수, terraform은 validate, phase는 dry-run, 문서는 diff).

---

## 5. 리스크 / 완화

| 리스크 | 완화 |
|--------|------|
| 라이브 미검증으로 Job이 런타임에 실패 | dry-run/문법/스키마 검증으로 최대화 + 후속 C 이슈에 "라이브 검증 대기" 명시. 첫 윈도우에서 `--from kafka-topics`로 단독 재실행 가능 설계 |
| staging RDS 자격원 불명확 | 구현 단계에서 terraform output·SM 경로 확정. 불명 시 dev만 우선, staging은 TODO 주석 + 이슈 코멘트 |
| topics.txt 추출이 terraform 파싱 깨뜨림 | `terraform validate`로 검증, `file()`+`split`+`compact`/정규식 필터로 빈줄·주석 제거 |
| 문서 과도 수정으로 이력 훼손 | D-041 관례(원자리 HTML 주석) 준수, Status만 갱신·본문 보존 |

---

## 6. 작업 순서 (플랜에서 단계화)

1. 파트 1 문서 4종 동기화 (커밋)
2. GitHub 이슈 3건 생성 → 번호 역링크 반영 (커밋)
3. `infra/kafka/topics.txt` 추출 + terraform `main.tf` 전환 (`terraform validate`)
4. `bring-up.sh` `phase_kafka_topics`·`phase_db_init` 추가 + PHASES/usage 등재
5. 오프라인 검증(§3.5) 후 PR

> 파트 1·2는 독립적이므로 별도 커밋(원자적). 이슈 번호 의존은 2→1 역참조뿐.
