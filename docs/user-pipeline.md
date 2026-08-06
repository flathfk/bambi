# 신규 사용자 파이프라인 — 가입부터 첫 보고서까지

> 클리퍼로 자료를 모으는 사용자가 겪는 전 과정을 **코드 기준**으로 적는다(2026-08-06 확인).
> 각 단계에 실제 호출되는 엔드포인트와 실측 소요 시간을 함께 둔다. 막히는 지점은 ⚠️로 표시한다.

---

## 0단계 — 가입과 온보딩 (한 번)

| # | 동작 | 실제 호출 |
|---|---|---|
| 1 | 서비스 웹에서 이메일 가입 | `POST /api/auth/signup` → 201 |
| 2 | 자동 로그인 | `POST /api/auth/login` → JWT(2시간) |
| 3 | **가입 이벤트로 agent에 사용자 생성** | `UserRegisteredEvent` → `PUT /internal/v1/users/{id}/context` |
| 4 | 온보딩에서 관심사 선택(최소 1개) | `POST /api/interests {name, taxonomyVersion, topicId}` |
| 5 | 확정 관심사를 agent에 동기화 | `POST /api/interests/sync` |

3번이 실패하면 이후 agent 호출이 `409 USER_CONTEXT_REQUIRED`로 막힌다. 다만 **가입 자체는 막지 않는다**(AFTER_COMMIT, 실패해도 warn만).

온보딩에서 taxonomy로 고른 관심사는 `categoryId`가 서버에서 채워진다(예: `ai_ml` → `tech`).
**직접 입력한 관심사는 taxonomy 필드가 전부 null**이다.

---

## 1단계 — 클리퍼 설치와 로그인 (한 번)

⚠️ **크롬 웹스토어에 배포돼 있지 않다.** 사용자는 확장 폴더를 받아 `chrome://extensions`에서
개발자 모드로 직접 로드해야 한다. 실사용자에게 요구하기 어려운 단계다.

설치 후 옵션 페이지에서 이메일·비밀번호로 로그인한다.

- `POST /api/auth/login` → 토큰을 `chrome.storage.local`(`bc_tok`)에 저장
- API 주소 기본값은 배포 서버가 **하드코딩**돼 있다(`background.js`의 `DEFAULT_API`)

⚠️ **토큰 수명이 2시간**이다. 만료되면 저장 시 401이 오고, 클리퍼는 토큰을 지운 뒤 옵션 페이지를 연다.
즉 **두 시간마다 다시 로그인**해야 한다(리프레시 토큰이 P1이라 아직 없다).

---

## 2단계 — 클리핑 (매번)

읽고 있는 페이지에서 툴바 아이콘을 **클릭 한 번**. 팝업 없이 바로 저장된다.

1. `chrome.scripting`이 페이지 안에서 본문 추출 — `article` → `main` → `body` 순으로 찾아 `innerText`, **최대 20,000자**
2. `POST /api/bookmarks {url, title, content}` + `Authorization: Bearer`
3. 아이콘 배지로 결과 표시 — 진행 `…` / 성공 `✓` / 실패 `!`

응답의 `card`는 **null**이다(배포는 즉시 카드 비활성 = `AGENT_IMMEDIATE_CARD_ENABLED=false`).
**저장 ≠ 보고서 생성**이라는 제품 정의 그대로다.

---

## 3단계 — service → agent 위키 중계 (자동, 즉시)

북마크 저장 트랜잭션이 커밋되면 `BookmarkClippingRelayListener`가 AFTER_COMMIT으로 중계한다.

| 저장 내용 | 중계 대상 |
|---|---|
| URL + 본문 | `POST /internal/v1/users/{id}/wiki-sources/clippings` → 202 |
| URL만 | `POST /internal/v1/users/{id}/wiki-sources/urls` → 202 |
| ⚠️ 본문만(URL 없음) | **중계 안 됨** — agent 계약이 URL을 필수로 요구한다. 로그만 남기고 건너뛴다 |

중계 실패는 삼킨다. **저장은 이미 커밋됐으므로 사용자 데이터는 남고**, 위키에만 안 들어간다(warn 로그).

---

## 4단계 — 개인 위키 빌드 (자동, ⚠️ 10~30분 지연)

agent가 클리핑을 받으면 위키 빌드 Job을 **대기 상태로** 만들고 실행을 미룬다.

- **조용 시간 10분** (`WIKI_BUILD_QUIET_MINUTES`) — 마지막 수집 후 10분간 새 자료가 없어야 실행한다.
  연속으로 저장하면 계속 뒤로 밀린다(자료를 모아 한 번에 빌드하려는 설계).
- **최대 대기 30분** (`WIKI_BUILD_MAX_WAIT_MINUTES`) — 계속 저장해도 첫 대기 후 30분이면 강제로 실행한다.

`agent-worker-wiki`가 60초 주기로 Job을 가져가 문서를 Entity·Concept·Schema로 분류하고,
그 결과로 **관심 태그(topic·score·confidence)를 추출**한다.

⚠️ **데모에서 가장 답답한 구간이다.** 자료를 저장해도 최소 10분은 지나야 위키·관심사에 반영된다.

---

## 5단계 — 보고서 생성 (두 경로)

**(a) 정기 브리핑** — 매일 **07:00 KST** 스케줄러가 활성 사용자 전원에게 생성 요청
topic은 사용자 대표 관심사(위키 태그 score 최고)다. 관심사가 없는 사용자는 건너뛴다(#45, 2026-08-06 반영 —
같은 날 아침 발화분까지는 배포 전이라 고정 문구 `오늘의 관심사 뉴스`로 나갔다).

**(b) 온디맨드** — 사용자가 "지금 생성"을 누름 → `POST /api/reports/generate`
사용자의 **대표 관심사 1개**(score 최고)를 topic으로 보낸다. 관심사가 0개면 `VALIDATION_ERROR`.

이후 `agent-worker-report`가 60초 주기로 Job을 claim해 처리한다:
**조사(개인 위키 + 실시간 뉴스 수집) → 생성 → 품질 판정 → 검토**. LLM을 10~20회 호출한다.

- 1건당 **1~3분**
- ⚠️ **워커가 1개라 순차 처리** — 2026-08-06 실측: 17명분 발화가 **27분**에 걸쳐 처리, 개별 대기 최대 **8분 41초**

---

## 6단계 — 발행 → 카드 (자동, 15초 이내)

1. agent가 완료 시 `publish_snapshots`에 `status='ready'`로 적재
2. service의 `PublishPollingWorker`가 **15초 주기**로 `claim`(배치 50)
3. `PublishProcessingService`가 `cards`·`reports`에 저장 — `(user_id, external_content_id)` 멱등
4. `ack`로 처리 완료 통보

카드 태그는 agent의 `content_tags`를 쓰고, 없으면 생성 topic으로 폴백한다.

---

## 7단계 — 사용자 노출

- 홈 **[내 보고서]** 탭에 표시 — `GET /api/feed`
- 카드 상세 — `GET /api/cards/{publicId}`, 본문은 `GET /api/reports/{id}`
- ⚠️ **카드 기본값은 PRIVATE**다. 공개 피드에 띄우려면 `PATCH /api/cards/{publicId}/visibility`를 따로 호출해야 한다.

---

## 전체 소요 시간

| 구간 | 시간 |
|---|---|
| 클리핑 → 위키 반영 | **10~30분** (조용 시간 대기) |
| 생성 요청 → 리포트 완료 | 1~3분 + 큐 대기(최대 27분 실측) |
| 리포트 → 카드 노출 | 15초 이내 |
| **가입 후 첫 보고서까지** | **빠르면 12분, 혼잡하면 1시간 이상** |

---

## 막히는 지점 요약

| # | 문제 | 영향 | 담당 |
|---|---|---|---|
| 1 | 클리퍼가 웹스토어 미배포 — 개발자 모드 수동 설치 | 실사용자에게 요구하기 어려움 | 우리 |
| 2 | 토큰 2시간 만료 — 리프레시 없음 | 두 시간마다 재로그인 | 우리(P1) |
| 3 | 본문만 저장(URL 없음)은 위키에 안 들어감 | 메모 형태 저장이 유실됨 | 계약 협의 |
| 4 | 위키 빌드 10~30분 지연 | 데모에서 즉시성 없음 | 설정으로 단축 가능 |
| 5 | 리포트 워커 1개 — 순차 처리 | 사용자 수에 선형으로 지연 | agent(유림·송우) |
| 6 | 스케줄러 topic이 고정 문구 | 정기 브리핑 주제가 부정확 | 소라 |
| 7 | 카드 기본 PRIVATE | 공개 피드에 자동 노출 안 됨 | 제품 결정 |

**데모용 단축 팁:** 4번은 `WIKI_BUILD_QUIET_MINUTES`를 1~2분으로 낮추면 즉시성이 크게 개선된다
(compose에 이미 변수로 노출돼 있고, 주석에도 "데모에서 대기가 길면 낮춘다"고 적혀 있다).
