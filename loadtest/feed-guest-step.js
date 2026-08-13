// 공개 피드 — 게스트, **고정 VU 계단 측정용**.
//
// feed-guest.js 와 요청은 같다. 다른 것은 부하 모양뿐이다.
//   · feed-guest.js       : 20→60→120→200 램프. 전 구간 **통합** 통계가 나온다.
//   · feed-guest-step.js  : VU 를 하나로 고정. "그 VU 에서의 정상상태" 를 잰다.
//
// 램프 통계로는 "몇 VU 부터 처리량이 정체되고 지연이 급증했는지" 를 알 수 없다
// (2026-08-12 지적). 계단을 하나씩 따로 재야 처리량·지연 곡선이 그려진다.
//
// **워밍업은 별도 실행으로 분리한다.** --summary-trend-stats 를 붙여도 워밍업 구간의
// 표본이 요약에서 자동으로 빠지지는 않는다. 그래서 run-step.sh 가 이 스크립트를
// 두 번 돌린다 — 첫 번째(워밍업) 출력은 버리고 두 번째만 기록한다.
//
// 실행 (직접 쓰지 말고 run-step.sh 를 쓸 것):
//   k6 run --vus 60 --duration 2m \
//          --summary-trend-stats "avg,min,med,p(90),p(95),p(99),max" \
//          -e BASE=http://10.178.0.4 feed-guest-step.js

import http from "k6/http";
import { check } from "k6";
import { Trend } from "k6/metrics";

const feedDuration = new Trend("feed_guest_duration", true);

// stages 를 두지 않는다. VU·duration 은 CLI(--vus/--duration)가 정한다 —
// 계단마다 스크립트를 고치지 않으려는 것이다.
export const options = {
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const BASE = __ENV.BASE || "http://localhost:8080";

export default function () {
  const res = http.get(`${BASE}/api/feed/public`, {
    tags: { scenario: "guest" },
  });
  feedDuration.add(res.timings.duration);
  check(res, {
    "status 200": (r) => r.status === 200,
    "본문 있음": (r) => r.body && r.body.length > 2,
  });
}
