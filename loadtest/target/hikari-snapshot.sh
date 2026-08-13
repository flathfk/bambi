#!/bin/bash
# Hikari 커넥션 획득 지표를 한 번 찍는다. (타깃 VM 에서 실행)
#
# 왜 스냅샷인가: `hikaricp.connections.acquire` 의 COUNT·TOTAL_TIME 은 **앱 기동 이후 누적값**이다.
# 그대로 읽으면 지금까지 돌린 모든 부하가 섞인 평균이 나온다. 한 계단의 값을 알려면
# **측정 전후로 두 번 찍어 차분**을 내야 한다.
#
#   평균 획득 대기 = (TOTAL_TIME 후 - TOTAL_TIME 전) / (COUNT 후 - COUNT 전)
#
# 이 값이 응답시간의 큰 몫을 차지한다면, 요청은 **일하느라 느린 게 아니라 커넥션을 기다리느라**
# 느린 것이다. 풀이 꽉 찼다는 사실(커넥션=10)만으로는 그 구분을 못 한다.
#
# 사용: bash hikari-snapshot.sh          → "COUNT TOTAL_TIME MAX PENDING" 한 줄
set -uo pipefail
DC="sudo docker compose -f docker-compose.target.yml"

read_metric() {   # $1=메트릭 이름 → "STAT=값 …"
    $DC exec -T backend sh -c "curl -s --max-time 3 http://localhost:9090/actuator/metrics/$1" 2>/dev/null \
        | tr '{' '\n' \
        | sed -n 's/.*"statistic":"\([A-Z_]*\)","value":\([0-9.E-]*\).*/\1=\2/p'
}

acq=$(read_metric hikaricp.connections.acquire)
pend=$(read_metric hikaricp.connections.pending)

count=$(echo "$acq"  | sed -n 's/^COUNT=//p')
total=$(echo "$acq"  | sed -n 's/^TOTAL_TIME=//p')
max=$(echo   "$acq"  | sed -n 's/^MAX=//p')
pending=$(echo "$pend" | sed -n 's/^VALUE=//p')

echo "COUNT=${count:-0} TOTAL_TIME=${total:-0} MAX=${max:-0} PENDING=${pending:-0}"
