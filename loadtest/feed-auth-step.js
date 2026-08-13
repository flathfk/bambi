// 공개 피드 — 인증, **고정 VU 계단 측정용**.
//
// feed-auth.js 와 요청·setup 은 같다. 부하 모양만 다르다(고정 VU).
// 배경은 feed-guest-step.js 상단 주석 참고.
//
// 토큰은 feed-auth.js 와 마찬가지로 setup 에서 한 번만 받는다. VU 마다 로그인하면
// bcrypt 가 병목이 되어 피드를 못 본다.
//
// 실행 (직접 쓰지 말고 run-step.sh 를 쓸 것):
//   k6 run --vus 60 --duration 2m \
//          --summary-trend-stats "avg,min,med,p(90),p(95),p(99),max" \
//          -e BASE=http://10.178.0.4 \
//          -e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234 feed-auth-step.js

import http from "k6/http";
import { check, fail } from "k6";
import { Trend } from "k6/metrics";

const feedDuration = new Trend("feed_auth_duration", true);

export const options = {
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const BASE = __ENV.BASE || "http://localhost:8080";
const EMAIL = __ENV.EMAIL;
const PASSWORD = __ENV.PASSWORD;

export function setup() {
  if (!EMAIL || !PASSWORD) {
    fail("EMAIL·PASSWORD 환경변수가 필요합니다.");
  }
  const res = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: { "Content-Type": "application/json" } },
  );
  if (res.status !== 200) {
    fail(`로그인 실패 status=${res.status} body=${res.body}`);
  }
  const token = res.json("data.accessToken");
  if (!token) fail("응답에 data.accessToken 이 없습니다.");
  return { token };
}

export default function (data) {
  const res = http.get(`${BASE}/api/feed/public`, {
    headers: { Authorization: `Bearer ${data.token}` },
    tags: { scenario: "auth" },
  });
  feedDuration.add(res.timings.duration);
  check(res, {
    "status 200": (r) => r.status === 200,
    "본문 있음": (r) => r.body && r.body.length > 2,
  });
}
