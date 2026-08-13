// 회원가입 — **고정 VU 계단 측정용**.
//
// 왜 따로 재나: 가입은 bcrypt 해싱이 들어가 CPU 특성이 읽기와 완전히 다르다.
// README 3항이 "로그인은 별도. bcrypt 가 무거워 피드에 섞으면 피드를 못 본다" 고
// 적어둔 그 경로인데, 정작 별도 측정을 안 했었다(2026-08-13).
//
// 데모 시나리오 "30~40명 동시 가입" 이 정확히 이 경로다.
//
// 실행: run-step.sh 경유. VU·duration 은 CLI 가 정한다.

import http from "k6/http";
import { check } from "k6";
import { Trend, Counter } from "k6/metrics";

const signupDuration = new Trend("signup_duration", true);
const created = new Counter("signup_created");

export const options = {
  thresholds: { http_req_failed: ["rate<0.05"] },
};

const BASE = __ENV.BASE || "http://localhost:8080";
// 런마다 다른 접두사를 줘서 재실행 시 409(중복 이메일)로 오염되지 않게 한다.
const RUN = __ENV.RUN_TAG || `${Date.now()}`;

export default function () {
  // VU·반복마다 고유 이메일. 같은 이메일이면 409 가 나서 bcrypt 를 안 타 측정이 무의미해진다.
  const email = `lt-${RUN}-${__VU}-${__ITER}@loadtest.local`;
  const res = http.post(
    `${BASE}/api/auth/signup`,
    JSON.stringify({ email, password: "loadtest1234", displayName: `부하${__VU}` }),
    { headers: { "Content-Type": "application/json" }, tags: { scenario: "signup" } },
  );
  signupDuration.add(res.timings.duration);
  if (res.status === 201) created.add(1);
  check(res, {
    "status 201": (r) => r.status === 201,
  });
}
