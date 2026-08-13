#!/bin/bash
# 설정을 바꾼 전후로 **응답이 실제로 어떻게 달라지는지** 기록한다. (타깃 VM 에서 실행)
#
# 크기 비교로는 부족하다 — 바이트 수가 같아도 다른 카드일 수 있다(2026-08-12 지적).
# 그래서 본문 sha256 과 **반환된 카드 publicId 목록**을 남긴다. 목록이 있어야
# 나중에 두 실행을 겹쳐 "몇 장이 바뀌었나"(overlap@20)를 셀 수 있다.
#
# ⚠️ 인증 경로는 동점 카드의 자리를 5분마다 바꾼다
#    (FeedService.ROTATION_SLOT_SECONDS = 300). 따라서 변경 전/후 비교는
#    **같은 슬롯 번호 안에서** 해야 한다. 슬롯이 넘어간 뒤 찍은 두 결과의 차이는
#    설정 변경 때문인지 순환 때문인지 구분할 수 없다.
#    → 이미지를 미리 빌드해두고 슬롯 안에서 전환하는 식으로 운용할 것.
#    게스트는 rankForViewer 가 즉시 반환해(FeedService.java:227) 정렬을 안 하므로
#    슬롯과 무관하다. 게스트 비교는 아무 때나 해도 된다.
#
# 사용: bash verify-response.sh [라벨]
#   예: bash verify-response.sh pool60
set -uo pipefail

LABEL=${1:-noname}
BASE=${BASE:-http://localhost}
EMAIL=${EMAIL:-loadtest@bambi.test}
PASSWORD=${PASSWORD:-loadtest1234}

SLOT=$(( $(date +%s) / 300 ))
echo "=== 라벨=${LABEL}  시각=$(date +%H:%M:%S)  5분슬롯=${SLOT} ==="

dump() {   # $1=이름  $2=응답본문
    local name="$1" body="$2"
    local n hash
    n=$(printf '%s' "$body" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]))' 2>/dev/null || echo "파싱실패")
    hash=$(printf '%s' "$body" | sha256sum | cut -c1-16)
    echo "[${name}]"
    echo "  건수   = ${n}"
    echo "  크기   = $(printf '%s' "$body" | wc -c) bytes"
    echo "  sha256 = ${hash}…"
    echo "  publicId 목록 (순서대로):"
    printf '%s' "$body" \
        | python3 -c 'import sys,json
for i,c in enumerate(json.load(sys.stdin)["data"],1): print(f"    {i:2d}. {c[\"publicId\"]}")' \
        2>/dev/null || echo "    (파싱 실패)"
}

guest=$(curl -s "${BASE}/api/feed/public")
dump "게스트" "$guest"

TOKEN=$(curl -s -X POST "${BASE}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["accessToken"])' 2>/dev/null)

if [ -z "${TOKEN}" ]; then
    echo "[인증] ❌ 로그인 실패 — 인증 응답은 기록하지 못했습니다."
    exit 1
fi

auth=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${BASE}/api/feed/public")
dump "인증" "$auth"
