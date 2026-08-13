# 부하 테스트 — 읽기 경로

> 목적: **어디서 먼저 깨지는지 찾고, 개선 방향을 근거와 함께 정하는 것.**
> "몇 명까지 됩니다"를 증명하는 것이 아니다.

## 무엇을 재고, 무엇을 안 재나

| 대상 | 재나 | 이유 |
|---|---|---|
| `GET /api/feed/public` (게스트) | ✅ | 개인화가 빠진 기준선 |
| `GET /api/feed/public` (인증) | ✅ | 개인화·랭킹이 전부 도는 실제 경로 |
| 로그인 | 별도 | bcrypt 가 무거워 피드에 섞으면 피드를 못 본다 |
| **보고서 생성** | ❌ | **LLM 비용이 실제로 발생한다.** 2026-08-12 크레딧 소진 사건 참고 |
| 위키 빌드 | ❌ | 동일 |

## 측정값의 한계 (먼저 읽을 것)

- **로컬 Docker Desktop 결과는 운영 서버의 최대 처리량이 아니다.** 부하 발생기(k6)와 앱·DB 가 같은 머신의 자원을 나눠 쓴다.
- 쓸 수 있는 것: **개선 전후 상대 비교**, **병목 지점 파악**.
- 쓸 수 없는 것: "운영에서 N RPS 를 처리한다".
- 발표에서 인용할 때 이 한계를 함께 말한다.

## 절차

### 0. 환경

```bash
# Docker Desktop 실행 필요
cd bambi/bambi-build
docker compose -f docker-compose.yml -f ../loadtest/docker-compose.loadtest.yml \
  up -d --build postgres backend
curl http://localhost:8080/api/health          # {"status":"UP"}
```

운영 compose 는 `backend` 를 GHCR 이미지로 받고 host 포트를 열지 않는다(`expose` 만 있음).
override 가 **로컬 빌드 + 8080 공개**를 더한다.

### 1. 시드

```bash
docker compose exec -T postgres psql -U bambi -d bambi < ../loadtest/seed.sql
```

작성자 200명 · 공개 카드 2,000건 · 좋아요 약 2만건. 운영(27명·20건)에서는 병목이 안 보인다.

### 2. 측정 계정

```bash
curl -X POST http://localhost:8080/api/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"email":"loadtest@bambi.test","password":"loadtest1234","displayName":"부하"}'
```

관심사를 몇 개 넣어두면 인증 경로의 매칭 로직이 실제로 일한다.

### 3. 기준값 — **아무것도 고치지 않은 상태에서** 먼저 잰다

```bash
k6 run -e BASE=http://localhost:8080 ../loadtest/feed-guest.js
k6 run -e BASE=http://localhost:8080 \
       -e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234 ../loadtest/feed-auth.js
```

> ⚠️ 커넥션 풀을 올리거나 캐시를 넣고 재면 **무엇이 병목이었는지 영영 모른다.**
> 같은 머신에서는 커넥션을 늘리는 것이 오히려 DB 를 느리게 만들 수도 있다.

### 4. 병목 근거 수집 — 단일 지표로 단정하지 않는다

부하가 도는 **중에** 세 가지를 함께 본다.

```bash
# ① 커넥션 풀 — 대기가 쌓이는가 (active 수만으로는 부족하다)
curl -s localhost:8080/actuator/metrics/hikaricp.connections.pending
curl -s localhost:8080/actuator/metrics/hikaricp.connections.acquire

# ② DB — 상태 분포와 느린 쿼리
docker compose exec -T postgres psql -U bambi -d bambi -c \
  "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"
docker compose exec -T postgres psql -U bambi -d bambi -c \
  "SELECT wait_event_type, wait_event, count(*) FROM pg_stat_activity
   WHERE state='active' GROUP BY 1,2 ORDER BY 3 DESC;"

# ③ 자원 — 앱과 DB 중 어디가 CPU 를 먹는가
docker stats --no-stream
```

판정 기준:

| 관찰 | 해석 |
|---|---|
| pending 이 쌓이고 DB CPU 는 여유 | 커넥션 풀 부족 |
| pending 은 0 인데 쿼리 시간이 길다 | 쿼리·인덱스 문제 |
| DB CPU 포화 | 커넥션을 늘리면 **더 느려진다** |
| 앱 CPU 포화 | 애플리케이션 로직(랭킹·직렬화) |

### 5. 한 번에 하나만 바꾸고 재측정

두 개를 같이 바꾸면 무엇이 효과였는지 모른다.

## 기록 양식

`results/YYYY-MM-DD_<변경내용>.md` 로 남긴다.

```
환경     : 로컬 Docker Desktop / 코드 <커밋 SHA> / 시드 카드 2000건
시나리오 : feed-guest | feed-auth
변경     : (없음 = 기준값)
결과     : p50 / p95 / p99 / RPS / 에러율 / 포화 VU
관찰     : pending, pg_stat_activity, docker stats
해석     : 병목 후보와 근거
```
