#!/bin/bash
# 측정 계정에 관심사를 넣는다.
#
# 왜 필요한가: 인증 경로의 개인화(matchedByCard)는 **뷰어 관심사가 있어야** 실제로 일한다.
# 관심사가 0개면 매칭이 빈 채로 끝나 게스트와 사실상 같은 일을 한다 — 2026-08-12 1차 측정에서
# 인증 경로가 게스트보다 빨랐던 이유가 이것이었다(시나리오 결함).
set -euo pipefail

BASE=${BASE:-http://localhost}
EMAIL=${EMAIL:-loadtest@bambi.test}
PASSWORD=${PASSWORD:-loadtest1234}

TOKEN=$(curl -s -X POST "$BASE/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["accessToken"])')

for name in "경제·금융" "AI·머신러닝" "스타트업·창업" "커리어·이직" "여행" "반도체" "부동산" "웹툰"; do
    curl -s -o /dev/null -X POST "$BASE/api/interests" \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$name\"}"
done

echo -n "등록된 관심사: "
curl -s "$BASE/api/interests" -H "Authorization: Bearer $TOKEN" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin)["data"];print(len(d),"개 —",[i["name"] for i in d])'
