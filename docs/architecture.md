# Architecture Reference

> [CLAUDE.md](../CLAUDE.md)의 상세 레퍼런스. 필요할 때만 읽습니다.
> 매 작업의 판단 기준(불변식·규칙)은 CLAUDE.md에 있습니다.

---

## 1. Product Direction

이 서비스는 단순 뉴스 요약 서비스가 아닙니다.

1. 사용자가 관심사를 모두 등록하지 않아도, 저장한 북마크/글에서 관심사를 추론한다.
2. 외부 웹 전체를 무제한 검색하지 않고, 통제된 RSS/API/수집 데이터와 사용자 저장물을 우선 사용한다.
3. 정보가 부족한 경우에만 제한적으로 Web Search fallback을 검토한다.
4. 모든 AI 결과는 출처 기반으로 제공한다.
5. 사용자에게 보여지는 최종 데이터는 Service Layer가 관리한다.
6. Agent Layer는 AI 분석/검색/생성 역할을 담당한다.

---

## 2. Tech Stack

- **Frontend:** Next.js, React, TypeScript
- **Backend:** Spring Boot, Java, Spring Security, JPA, JWT
- **AI Agent:** FastAPI, Python, LLM API (추후 LangGraph/RAG 확장)
- **Database:** PostgreSQL, pgvector
- **Cache/Lock/Rate Limit:** Redis
- **Messaging:** Kafka (KRaft) — Job Queue + Event Bus
- **Ops/Infra:** GCP Compute Engine, Docker / Docker Compose, Nginx, Blue-Green 무중단 배포, GitHub Actions

---

## 3. Layer Responsibilities

### Client Layer — `bambi-service-web`, `bambi-admin-web`
사용자/관리자 화면, API 호출, Loading/Error/Empty State 처리. **Agent 직접 호출 금지.**

### Service Layer — `bambi-service-api` (+ `service` schema, Redis, Kafka)
인증/인가, 사용자 관리, 북마크 저장, 관심사 관리, 카드/피드 관리, 관리자 기능, AI 요청/응답 로그, **Agent Gateway**, 사용자 노출 최종 데이터 관리.
→ **source of truth.**

### Agent Layer — `bambi-agent-api` (+ `agent` schema, pgvector, LLM)
북마크 요약, 관심사 추출, 카드 생성, 임베딩 생성, RAG 검색, 출처 기반 답변, generation/retrieval log 관리.
→ 서비스 원본 데이터를 소유하지 않는다. **`service` DB를 직접 수정하지 않는다.**

### External vs Internal
```text
외부 노출:  User → Nginx → Next.js / Spring Boot
내부 전용:  FastAPI Agent / PostgreSQL / Redis / Kafka
```
Spring Boot가 내부 네트워크에서 FastAPI Agent를 호출.

---

## 4. Database (2 DB 물리 분리)

> **2026-07-13 변경:** 기존 "1 PostgreSQL + service/agent schema 분리"에서 **`service-db` / `agent-db` 물리 분리(2 DB)**로 전환. 이유 = 워크로드 분리(트랜잭션 vs pgvector/임베딩), LLM팀의 독립 DB 소유, Agent↔Service 경계를 인프라로 강제.

- **`service-db`** (PostgreSQL, Spring 소유) — 원본·최종 사용자 노출 데이터. 아래 `service schema` 목록을 이 DB의 테이블로 읽는다.
- **`agent-db`** (PostgreSQL + pgvector, Agent/LLM팀 소유) — AI 파생물·임베딩·RAG. **상세 설계 정본은 bambi-agent-api `docs/agent-db-design.md`(송우 소유).** 아래 `agent schema` 목록은 요약일 뿐이다.
- **AI 로그 경계:** "우리가 agent에 뭘 요청/응답받았나"(관리자 화면용) = `service-db`(소라, Gateway가 기록). agent 내부 운영 로그(토큰·비용 등) = `agent-db`(송우). *→ 송우 확인 예정.*
- MVP(단일 VM)는 compose에 postgres 컨테이너 2개. Agent 실연동은 P1이고, P0는 Service 쪽 Mock으로 관통.

```text
PostgreSQL
├── service schema   # 원본 + 최종 사용자 노출 데이터
└── agent schema     # AI 처리용 파생 데이터
```

**service schema**
```text
service.users
service.roles
service.bookmarks
service.interests
service.bookmark_interests
service.collected_items
service.cards
service.feed_items
service.likes
service.admin_logs
service.ai_request_logs
service.ai_response_logs
```

**agent schema**
```text
agent.wiki_documents
agent.wiki_chunks
agent.embeddings
agent.prompt_templates
agent.retrieval_logs
agent.generation_logs
```

규칙:
- 원본 북마크, 수집 원천 데이터, 최종 카드, 피드 상태 → `service`
- chunk, embedding, RAG log, generation log → `agent`
- Agent는 `service` DB를 직접 수정하지 않는다.
- 최종 사용자 노출 데이터는 반드시 Service API가 저장/관리한다.

---

## 5. Data Flow

> **MVP 원칙:** 아래 흐름은 우선 **Service API → Agent API 동기 REST**로 관통.
> Kafka 기반 비동기(아래 `(P1)` 단계)는 P1에서 활성화.

### 5.1 Bookmark Save
1. 사용자가 URL/본문 저장
2. Next.js → Spring Boot API 호출
3. Spring Boot가 `service.bookmarks`에 저장, 상태 `PROCESSING`
4. (P1) Kafka `process.bookmark.requested` 발행
5. Worker/Service API가 FastAPI Agent 호출 → 요약/관심사 추출
6. 결과를 Spring Boot가 service DB에 저장, 상태 `DONE`/`FAILED`
7. 사용자가 카드/요약 확인

### 5.2 Card Generation
1. 사용자/시스템이 카드 생성 요청
2. Spring Boot가 사용자 관심사·저장 자료 조회
3. (P1) Kafka `generate.card.requested` 발행
4. Agent가 관련 자료 기반 카드 생성 → 반환
5. Spring Boot가 `service.cards` / `service.feed_items`에 저장
6. 사용자 피드에 표시

### 5.3 RSS/API Collection
```text
RSS/API 수집 → service.collected_items 저장 → 관심사 매칭 → 카드 재료로 사용
```
Web Search fallback (P1/P2): 자료 부족 시 사용자가 "더 찾아줘" 요청 → 제한적 Search API 호출 → Redis Rate Limit 적용.

---

## 6. Kafka (P1)

초기 Topic — 핵심 E2E 먼저, topic 남발 금지.
```text
process.bookmark.requested   # 북마크 분석 작업 요청
bookmark.processed           # 북마크 분석 완료 이벤트
generate.card.requested      # 카드 생성 작업 요청
card.generated               # 카드 생성 완료 이벤트
```

---

## 7. Redis

**Rate Limit** (비용성 작업 제한)
```text
rate:websearch:{userId}:{yyyy-MM-dd}
rate:qa:{userId}:{yyyy-MM-dd}
rate:card_regenerate:{userId}:{yyyy-MM-dd}
```
**Lock** (중복 작업 방지)
```text
lock:generate_card:{userId}
lock:process_bookmark:{bookmarkId}
```
**Cache** — 피드, 관심사, 자주 조회되는 데이터.

---

## 8. Deployment

```text
GCP Compute Engine 1대 + Docker Compose + Nginx + Blue-Green backend
```
Container 구성 (기능 단위 과분리 금지):
```text
nginx / frontend-service-web / frontend-admin-web
backend-blue / backend-green / agent-api
postgres / redis / kafka
```
Spring Boot 내부 패키지: `auth user bookmark interest card feed admin agentgateway`
FastAPI 내부 모듈: `bookmark_analysis interest_inference card_generation embedding rag`

---

## 9. Blue-Green Deployment

`backend-blue` / `backend-green` 로 운영.

배포 흐름:
1. 현재 active color 확인
2. inactive color에 새 버전 실행
3. `GET /api/health` 확인
4. 정상이면 Nginx upstream 전환
5. 실패 시 기존 버전 유지

필수 API: `GET /api/health`, `GET /api/version`
```json
{ "version": "1.0.0", "color": "blue", "commit": "abc123" }
```

---

## 10. CI/CD (GitHub Actions)

PR 생성 시 자동 검사: Frontend build/lint · Backend test/build · Agent test · Docker build · Secret scan.
CI 파일: `.github/workflows/ci.yml`

서브모듈 checkout:
```yaml
with:
  submodules: recursive
```
Private submodule은 별도 GitHub token 필요할 수 있음.

Branch protection 권장 (`main`, `develop`): Require PR before merging · Require status checks · Require conversation resolution.

---

## 11. Explanation for Reviewers

> Next.js로 사용자 화면을 만들고, Spring Boot를 서비스의 중심 API 서버로 사용했습니다.
> AI 기능은 Python 생태계를 활용하기 위해 FastAPI Agent 서버로 분리했습니다.
> 데이터는 PostgreSQL에 저장하고, pgvector로 저장 자료 기반 검색과 RAG 확장이 가능하게 했습니다.
> Redis는 Rate Limit과 Lock, Kafka는 AI 작업 비동기 처리를 위해 사용했습니다.
> 배포는 GCP Compute Engine 위 Docker Compose로 구성하고, Nginx와 GitHub Actions로 Blue-Green 무중단 배포를 구현했습니다.
