#!/bin/bash
# 부하 **발생기 자신**의 CPU 를 표본화한다. (k6 VM 에서 실행)
#
# 왜 필요한가: 생성기가 먼저 포화하면 타깃이 아니라 k6 VM 이 한계인데,
# 그걸 모르고 재면 "서비스 한계 N VU" 라는 **틀린 결론**이 나온다.
# VU 를 올려도 RPS 가 안 오르는 모양은 타깃 포화·생성기 포화·네트워크 포화가
# 모두 똑같이 만든다. 그래서 생성기를 함께 봐야 구분이 된다(2026-08-12).
#
# 판정: 전체CPU 가 85% 를 넘거나 k6 프로세스가 (코어수 × 90)% 에 붙으면
#       그 측정은 **생성기 한계**이므로 무효로 보고 생성기를 키운다.
#
# 사용: bash observe-k6.sh [표본수] [간격초]
set -uo pipefail

SAMPLES=${1:-20}
INTERVAL=${2:-6}
CORES=$(nproc)

# /proc/stat 델타로 계산한다 — mpstat·vmstat 설치 여부에 기대지 않으려는 것이다.
read_cpu() {
    awk '/^cpu /{idle=$5+$6; total=0; for(f=2;f<=NF;f++) total+=$f; print idle, total}' /proc/stat
}

echo "=== 생성기 VM: ${CORES} vCPU / 표본 ${SAMPLES}회 ${INTERVAL}초 간격 ==="
echo "    (전체CPU 는 전 코어 평균 0~100%. k6프로세스 는 코어당 100% 합산 — ${CORES}코어면 $((CORES*100))% 가 상한)"

for n in $(seq 1 "$SAMPLES"); do
    before=$(read_cpu); idle1=${before% *}; total1=${before#* }
    sleep "$INTERVAL"
    after=$(read_cpu);  idle2=${after% *};  total2=${after#* }

    used=$(awk -v a="$idle1" -v b="$total1" -v c="$idle2" -v d="$total2" \
        'BEGIN{ dt=d-b; if(dt<=0){print "0.0"} else {printf "%.1f", (1-(c-a)/dt)*100} }')
    k6cpu=$(ps -o %cpu= -C k6 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s+0}')

    flag=""
    awk -v u="$used" 'BEGIN{exit !(u>85)}' && flag="  ⚠️ 생성기 포화 의심"
    echo "  $(date +%H:%M:%S)  전체CPU=${used}%  k6프로세스=${k6cpu}%${flag}"
done
