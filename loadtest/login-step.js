// 로그인 — **고정 VU 계단 측정용**.
//
// 가입과 마찬가지로 bcrypt 검증이 들어간다. 가입과 나눠 재는 이유는
// 가입은 INSERT 가 함께 붙어 쓰기 부하가 섞이기 때문이다 — 로그인은 순수 해시 검증 + SELECT.
//
// 계정 하나를 전 VU 가 공유한다. 사용자 수가 늘어도 bcrypt 비용은 같으므로 병목 특성은 그대로다.

import http from "k6/http";
import { check } from "k6";
import { Trend } from "k6/metrics";

const loginDuration = new Trend("login_duration", true);

export const options = {
  thresholds: { http_req_failed: ["rate<0.05"] },
};

const BASE = __ENV.BASE || "http://localhost:8080";
const EMAIL = __ENV.EMAIL || "loadtest@bambi.test";
const PASSWORD = __ENV.PASSWORD || "loadtest1234";

export default function () {
  const res = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: { "Content-Type": "application/json" }, tags: { scenario: "login" } },
  );
  loginDuration.add(res.timings.duration);
  check(res, {
    "status 200": (r) => r.status === 200,
    "토큰 있음": (r) => (r.json("data.accessToken") ?? "").length > 0,
  });
}
