// 자료 저장(POST /api/bookmarks) — **고정 VU 계단 측정용**.
//
// 읽기와 다른 점: 쓰기 트랜잭션 + AFTER_COMMIT 이벤트로 agent 중계가 붙는다.
// 타깃 스택에는 agent 가 없어 중계는 실패하지만, 리스너가 예외를 삼키므로
// **저장 응답 자체는 정상**이다(BookmarkClippingRelayListener 의 설계 그대로).
// 즉 이 측정은 "쓰기 경로 + 이벤트 발행" 까지의 비용을 본다.
//
// 토큰은 setup 에서 한 번만 받는다 — VU 마다 로그인하면 bcrypt 가 저장을 가린다.

import http from "k6/http";
import { check, fail } from "k6";
import { Trend } from "k6/metrics";

const saveDuration = new Trend("save_duration", true);

export const options = {
  thresholds: { http_req_failed: ["rate<0.05"] },
};

const BASE = __ENV.BASE || "http://localhost:8080";
const EMAIL = __ENV.EMAIL || "loadtest@bambi.test";
const PASSWORD = __ENV.PASSWORD || "loadtest1234";
const RUN = __ENV.RUN_TAG || `${Date.now()}`;

export function setup() {
  const res = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: { "Content-Type": "application/json" } },
  );
  if (res.status !== 200) fail(`로그인 실패: ${res.status}`);
  return { token: res.json("data.accessToken") };
}

export default function (data) {
  // URL 을 매번 다르게 준다 — 같은 URL 이면 dedup 경로(UPDATE)만 타서 INSERT 비용이 안 잡힌다.
  const url = `https://loadtest.local/${RUN}/${__VU}/${__ITER}`;
  const res = http.post(
    `${BASE}/api/bookmarks`,
    JSON.stringify({ url, title: `부하 저장 ${__VU}-${__ITER}`, content: "부하 테스트 본문" }),
    {
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${data.token}` },
      tags: { scenario: "save" },
    },
  );
  saveDuration.add(res.timings.duration);
  check(res, {
    "status 201": (r) => r.status === 201,
  });
}
