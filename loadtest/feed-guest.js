// 공개 피드 — **비로그인(게스트)** 경로 부하 시나리오.
//
// 게스트는 개인화가 생략된다. FeedService.publicFeed 주석 그대로:
//   ② 내가 좋아요한 카드 — "게스트(viewerId=null)는 조회 없이 전부 false"
//   ③ 내가 스크랩한 카드 — 동일
//   ⑤ 추천 매칭(matchedByCard) — 뷰어 관심사가 없어 빈 매칭
//   랭킹(rankForViewer) — **정렬 자체를 하지 않는다.** `viewerId == null` 이면 즉시
//     반환해서(FeedService.java:227) 리포지토리가 준 **최신순 그대로** 나간다.
//     인기·신선도 점수도, 5분 동점 순환도 게스트에는 적용되지 않는다.
//     (2026-08-12 정정 — 이 주석은 원래 "인기·신선도만으로 정렬"이라고 적혀 있었으나
//      코드와 달랐다. 이 사실은 곧 후보 풀을 넓게 읽는 것이 게스트 출력에
//      아무 영향이 없다는 뜻이기도 하다.)
//
// 그래서 이 시나리오는 **"가장 무거운 경로"가 아니다.** 인증 경로(feed-auth.js)와
// 짝으로 돌려 그 차이를 "개인화 비용"으로 읽는 것이 목적이다.
//
// 실행:
//   k6 run -e BASE=http://localhost:8080 feed-guest.js

import http from "k6/http";
import { check } from "k6";
import { Trend } from "k6/metrics";

const feedDuration = new Trend("feed_guest_duration", true);

export const options = {
  // 계단식으로 올려 **어느 지점에서 꺾이는지**를 본다. 목표는 통과가 아니라 포화점 발견이다.
  stages: [
    { duration: "30s", target: 20 },
    { duration: "1m", target: 60 },
    { duration: "1m", target: 120 },
    { duration: "1m", target: 200 },
    { duration: "30s", target: 0 },
  ],
  // threshold 는 실패시키려는 게 아니라 요약에 선을 긋기 위한 것이다.
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
