#!/bin/bash
# 고정 VU 한 계단을 **워밍업과 측정을 분리해서** 잰다. (k6 VM 에서 실행)
#
# 왜 분리하나: --summary-trend-stats 를 붙여도 워밍업 구간 표본이 요약에서
# 자동으로 빠지지 않는다. JIT·커넥션 풀이 데워지는 동안의 느린 응답이 섞이면
# 그 숫자를 "정상상태 p95·p99" 라고 부를 수 없다(2026-08-12 지적).
# 그래서 k6 를 **두 번** 돌리고 첫 번째(워밍업) 출력은 버린다.
# 서버 쪽 워밍업 효과는 프로세스가 달라도 그대로 남으므로 이 방식으로 충분하다.
#
# 측정 중에는 생성기 자신의 CPU 도 함께 표본화한다(observe-k6.sh).
# 생성기가 먼저 포화하면 그 계단의 숫자는 타깃의 한계가 아니다.
#
# 사용: bash run-step.sh <guest|auth> <VU> [측정시간] [워밍업시간] [표본수]
#   예: bash run-step.sh guest 120
#       bash run-step.sh auth 200 2m 30s 20
set -uo pipefail

SCENARIO=${1:?"guest 또는 auth"}
VUS=${2:?"VU 수"}
DUR=${3:-2m}
WARM=${4:-30s}
SAMPLES=${5:-20}

BASE=${BASE:-http://10.178.0.4}
TREND="avg,min,med,p(90),p(95),p(99),max"

case "$SCENARIO" in
    guest)  SCRIPT=feed-guest-step.js; EXTRA=() ;;
    auth)   SCRIPT=feed-auth-step.js
            EXTRA=(-e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234) ;;
    # ── 쓰기·인증 경로 (2026-08-13 추가) ──
    # 가입은 매번 새 이메일이 필요하다. RUN_TAG 로 런을 구분해 재실행 시 409 로 오염되지 않게 한다.
    signup) SCRIPT=signup-step.js; EXTRA=(-e RUN_TAG="$(date +%s)") ;;
    login)  SCRIPT=login-step.js
            EXTRA=(-e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234) ;;
    save)   SCRIPT=save-step.js
            EXTRA=(-e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234 -e RUN_TAG="$(date +%s)") ;;
    *) echo "❌ 첫 인자는 guest·auth·signup·login·save 중 하나"; exit 1 ;;
esac

TAG="${SCENARIO}_vu${VUS}"
OUT="step_${TAG}.txt"
GEN="step_${TAG}_generator.txt"

echo "── ① 워밍업 ${WARM} @ ${VUS} VU (결과 버림) ──"
k6 run --vus "$VUS" --duration "$WARM" -e BASE="$BASE" "${EXTRA[@]}" "$SCRIPT" >/dev/null 2>&1
echo "   워밍업 종료(rc=$?)"

echo "── ② 측정 ${DUR} @ ${VUS} VU ──"
(setsid nohup bash observe-k6.sh "$SAMPLES" 6 > "$GEN" 2>&1 </dev/null &)
k6 run --vus "$VUS" --duration "$DUR" --summary-trend-stats "$TREND" \
       -e BASE="$BASE" "${EXTRA[@]}" "$SCRIPT" > "$OUT" 2>&1
rc=$?

echo "완료(rc=${rc}) → ${OUT} / ${GEN}"
sed -n '/TOTAL RESULTS/,$p' "$OUT" | head -22
