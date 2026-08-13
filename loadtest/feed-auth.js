// 공개 피드 — **인증(로그인) 경로** 부하 시나리오.
//
// 게스트 경로에서 생략되던 것이 전부 살아난다.
//   · 내가 좋아요한 카드 IN 쿼리
//   · 내가 스크랩한 카드 IN 쿼리
//   · 추천 매칭 — 뷰어 관심사 + taxonomy 조회, 좋아요·스크랩 카드의 topic 수집,
//     미연결 관심사 이름 → topic_key 변환
//   · 랭킹 — 매칭 점수가 실제로 정렬을 바꾼다
//
// 이 시나리오와 feed-guest.js 의 차이가 곧 **개인화 비용**이다.
//
// 사전 준비: 측정용 계정 1개가 필요하다. seed.sql 은 로그인 가능한 계정을 만들지 않으므로
// (해시가 가짜다) 아래처럼 실제 가입 API 로 만든 뒤 이메일·비밀번호를 넘긴다.
//   curl -X POST http://localhost:8080/api/auth/signup \
//     -H 'Content-Type: application/json' \
//     -d '{"email":"loadtest@bambi.test","password":"loadtest1234","displayName":"부하"}'
//
// 실행:
//   k6 run -e BASE=http://localhost:8080 \
//          -e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234 feed-auth.js

import http from "k6/http";
import { check, fail } from "k6";
import { Trend } from "k6/metrics";

const feedDuration = new Trend("feed_auth_duration", true);

export const options = {
  stages: [
    { duration: "30s", target: 20 },
    { duration: "1m", target: 60 },
    { duration: "1m", target: 120 },
    { duration: "1m", target: 200 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const BASE = __ENV.BASE || "http://localhost:8080";
const EMAIL = __ENV.EMAIL;
const PASSWORD = __ENV.PASSWORD;

// 토큰은 **setup 에서 한 번만** 받는다. VU 마다 로그인하면 로그인(bcrypt)이 병목이 되어
// 피드 성능을 못 본다 — 로그인 자체를 재려면 별도 시나리오로 분리해야 한다.
export function setup() {
  if (!EMAIL || !PASSWORD) {
    fail("EMAIL·PASSWORD 환경변수가 필요합니다. 파일 상단 주석 참고.");
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
