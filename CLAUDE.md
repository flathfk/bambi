# CLAUDE.md

**밤새비서** — 사용자가 저장한 웹 콘텐츠에서 관심사를 추론하고, RSS/API로 수집한 정보와 매칭하여 **출처 기반 카드 브리핑**을 제공하는 개인 리서치 비서.

> **이름 정리:** 서비스명 **밤새비서** · 코드명 **Bambi**(레포 접두사 `bambi-`) · 배포/팀명 **AlphaCatcher**(GCP `alphacatcher-prod`, Notion `Team Alpha`). 셋은 같은 프로젝트다.

> 이 파일은 매 작업의 판단 기준(불변식·규칙)만 담습니다.
> 상세 설계·플로우·계약은 아래 레퍼런스를 필요할 때 읽으세요.
> - [docs/architecture.md](docs/architecture.md) — 레이어 상세, DB 스키마, 데이터 플로우, Kafka/Redis, 배포/Blue-Green/CI
> - [docs/agent-contract.md](docs/agent-contract.md) — Agent API 계약(Mock 우선)

---

## Repository Structure (Git submodules)

| Directory | Role |
|---|---|
| `bambi-service-web` | 사용자 Next.js 웹 |
| `bambi-admin-web` | 관리자 Next.js 웹 |
| `bambi-service-api` | Spring Boot 서비스 API (Service Layer) |
| `bambi-agent-api` | FastAPI AI Agent API (Agent Layer) |
| `bambi-build` | Docker Compose, Nginx, deploy/rollback scripts, infra docs |

하위 디렉토리는 각각 별도 GitHub 레포를 참조하는 **Git submodule**입니다.
클론/갱신 시 `--recurse-submodules` 또는 `git submodule update --init --recursive` 사용.

---

## Build / Run / Test

> 스캐폴딩(gradlew wrapper · Next.js · FastAPI)이 올라오면 실제 커맨드로 확정한다. 현재는 목표 커맨드.

- **전체 스택:** `cd bambi-build && docker compose up -d` (postgres / redis / kafka / backend / frontend / agent)
- **service-api (Spring Boot):** `./gradlew build` · `./gradlew test` · `./gradlew bootRun`
- **service-web / admin-web (Next.js):** `npm install` · `npm run dev` · `npm run build` · `npm run lint`
- **agent-api (FastAPI):** `pip install -r requirements.txt` · `uvicorn app.main:app --reload` · `pytest`
- **헬스 체크:** `curl http://localhost/api/health` — **DB 무관하게 200**이어야 한다(빈 껍데기 먼저 관통).
- 작업 전 루트에서 `git submodule update --init --recursive`.

---

## Architecture Invariants (반드시 지킬 것)

- **`Frontend → Service API → Agent API`. 프론트는 Agent API를 절대 직접 호출하지 않는다.**
- 외부 노출은 **Nginx / Next.js / Spring Boot** 뿐. FastAPI Agent·PostgreSQL·Redis·Kafka는 **내부 전용**.
- **Service Layer = source of truth.** 인증/인가, 원본 데이터, 최종 카드·피드, AI 로그를 관리하고 **Agent Gateway** 역할을 한다.
- **Agent Layer는 AI 파생물(요약·관심사·임베딩·RAG·생성로그)만** 다룬다. **`service` DB를 직접 수정하지 않는다.** 사용자 노출 데이터는 반드시 Service API가 저장한다.
- DB는 **PostgreSQL 1개, `service` / `agent` schema로 분리.** 원본·최종 데이터 = `service`, AI 파생 데이터 = `agent`.
- MVP는 Service→Agent **동기 REST 호출**로 먼저 관통한다. Kafka 비동기는 **P1**.

---

## Development Principles

- **작게라도 실제로 도는 E2E를 먼저.** Mock으로 관통한 뒤 실제 구현으로 교체.
- MVP 우선, 과한 추상화 금지. 기능 수보다 핵심 흐름의 안정 동작이 중요.
- **첫 목표 E2E:** 가입 → 로그인 → 빈 피드 → URL/본문 저장 → Mock Agent 처리 → 관심사/요약 저장 → 즉시 카드 1장 → 카드 피드 → 관리자 AI 로그/사용자 목록 확인. **이게 배포 서버에서 돌면 1차 MVP 성공.**

---

## Coding Rules

**공통**
- API Key / Secret / `.env` 커밋 금지. `.env.example`만 커밋.
- 프론트는 Agent API 직접 호출 금지.

**Backend (Spring Boot)**
- 공통 응답 포맷 / 공통 예외 처리 사용. Controller / Service / Repository / DTO 분리.
- Entity를 API 응답으로 직접 노출 금지. 권한 검증 명확히.
- 관리자 API는 **ADMIN 권한 필수**. Agent 요청/응답은 로그로 남긴다.

**Frontend (Next.js)**
- Loading / Error / Empty State 필수. API 호출은 공통 client 사용.
- 인증 페이지는 Protected Route 처리. 사용자/관리자 화면 명확히 분리.

**Agent (FastAPI)**
- 정해진 JSON schema 준수. **출처 없는 답변 금지, 근거 부족 시 모른다고 응답.**
- LLM API Key는 환경변수로만. **Mock API 먼저 제공, Contract Test 유지.**

**Database**
- `service` / `agent` schema 책임 분리. 삭제/비공개/권한 정책은 **Service Layer 기준**.
- pgvector는 RAG/유사도 검색이 필요할 때만.

---

## 공통 규약 (P0 합의안)

> 회의록 [공통 규약 & 기술 결정 (P0)] 기준. 팀 확정 전 잠정값이며, 확정 시 이 표를 갱신한다.

- **공통 응답 포맷:** `{ success, data, error }`. 성공은 `error: null`, 실패는 `data: null` + `error: { code, message }`.
- **에러 코드:** HTTP status + 내부 code (`VALIDATION_ERROR` / `AUTH_INVALID_TOKEN` / `FORBIDDEN` / `NOT_FOUND` / `DUPLICATE_RESOURCE` / `INTERNAL_ERROR`).
- **JWT:** P0는 localStorage access token으로 단순 구현. 보안 고도화 시 httpOnly cookie + refresh token 전환.
- **DB 마이그레이션:** Flyway 사용, 배포는 `ddl-auto=validate`. 급하면 Day 1만 `update`, Day 3 전 Flyway 전환.
- **관리자 계정:** seed 방식. 서버 시작 시 `ADMIN_EMAIL` / `ADMIN_PASSWORD` 환경변수가 있으면 생성.
- **즉시 카드 1장:** P0는 저장 API 안에서 동기 Mock Agent 호출 → 관심사/요약/카드/로그까지 즉시 저장. Kafka 비동기는 P1.
- **reference CRUD 템플릿:** `Note` 엔티티로 Controller/Service/Repository/DTO/공통응답/예외/권한 1세트 제공(팀원 복붙 시작점).
- **API 경로:** `/api/...` 접두사 (예: `/api/auth/login`, `/api/bookmarks`). 관리자 API는 `/api/admin/...`.
- **DB 네이밍:** 테이블·컬럼 `snake_case`, schema 접두사(`service.` / `agent.`) 명시.
- **Git:** `main`(배포) · `develop`(통합) · `feature/*`. PR로만 머지. 서브모듈은 하위 레포 먼저 push → build 레포 포인터 갱신.

---

## What Not To Do (MVP 제외)

Kubernetes/GKE · Cloud SQL · GPU 서버 · 마이크로서비스 과분리 · 프론트에서 LLM 직접 호출 · Agent의 `service` DB 직접 수정 · 무제한 Web Search / 전체 웹 크롤링 · 결제 · 팔로우/댓글/DM 고도화 · OCR/PDF 고도화.

---

## Priorities

- **P0** — 인증/권한(USER·ADMIN), URL/본문 저장, 북마크 목록·상세, Mock Agent, 관심사/요약 저장, 즉시 카드 1장, 카드 피드, 관리자(사용자 목록·AI 로그), Empty/Error/404, GCP 배포
- **P1** — Kafka 비동기, Redis(Rate Limit/Lock), 실제 LLM 연동, RSS/API 수집, 공개 카드·피드, 좋아요, 검색/Q&A Lite, pgvector, Markdown Export, 실패 재시도
- **P2** — 소셜 로그인, 결제, 팔로우, 댓글, OCR, 모바일 앱, 추천 고도화, 전체 크롤링, Obsidian 연동

---

## Team Role

| Name | Responsibility |
|---|---|
| 우석 | 팀장·**통합 오너**, **LLM팀 협의 창구**(요구사항·계약 협상), 인증 세로 슬라이스 **오너**(뼈대 판단·리뷰, 구현은 위임/AI), 공통 구조·GCP/Docker/Nginx·CI **감독**. *직접 타이핑보다 판단·리뷰·통합 중심 (Redis/Kafka·Blue-Green·자동배포는 P1)* |
| 소라 | Agent Gateway, agent-api FastAPI scaffold·연동, **LLM팀 기술 구현·연동**, Contract Test, AI 로그 |
| 영현 | 클립/북마크, 관심사, 카드/피드 도메인, 중복 처리 |
| 여진 | Next.js 사용자/관리자 UI, Empty State, Error UI |
