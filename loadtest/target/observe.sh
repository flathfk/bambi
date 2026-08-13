#!/bin/bash
# 부하가 도는 **중에** 자원·DB 상태를 표본 수집한다.
#
# 단일 지표로 병목을 단정하지 않는다. 세 가지를 같은 시각에 본다.
#   ① docker stats  — 앱과 DB 중 어디가 CPU 를 먹는가
#   ② pg_stat_activity — 커넥션이 active 에 몰리는가, 무엇을 기다리는가
#   ③ 응답 크기      — 네트워크·직렬화가 원인인지 가른다
#
# 사용: bash observe.sh [표본수] [간격초]
set -uo pipefail

SAMPLES=${1:-10}
INTERVAL=${2:-6}
DC="sudo docker compose -f docker-compose.target.yml"

echo "=== 표본 ${SAMPLES}회 / ${INTERVAL}초 간격 ==="
for i in $(seq 1 "$SAMPLES"); do
    echo "── 표본 $i ($(date +%H:%M:%S)) ──"

    echo "[CPU/MEM]"
    sudo docker stats --no-stream --format '  {{.Name}}  cpu={{.CPUPerc}}  mem={{.MemUsage}}' \
        | grep -E 'backend|postgres|nginx'

    # ⚠️ 2>/dev/null 을 붙이지 않는다. 예전 버전은 에러를 삼켜서
    #    "표본은 30개인데 DB 섹션만 전부 비어 있는" 파일을 만들었다(2026-08-12).
    #    출력이 비면 그건 부하가 없다는 뜻이어야지, 쿼리가 깨졌다는 뜻이면 안 된다.
    echo "[DB 상태 분포]"
    $DC exec -T postgres psql -U bambi -d bambi -tA -c \
        "SELECT '  ' || coalesce(state,'null') || ' = ' || count(*) FROM pg_stat_activity
         WHERE datname='bambi' GROUP BY state ORDER BY count(*) DESC;"

    echo "[DB 대기 이벤트 (active)]"
    $DC exec -T postgres psql -U bambi -d bambi -tA -c \
        "SELECT '  ' || coalesce(wait_event_type,'-') || '/' || coalesce(wait_event,'-') || ' = ' || count(*)
         FROM pg_stat_activity WHERE datname='bambi' AND state='active'
         GROUP BY wait_event_type, wait_event ORDER BY count(*) DESC LIMIT 5;"

    # DB 쪽에서 백엔드가 실제로 쥔 커넥션 수. 이 값이 풀 최대치
    # (DB_POOL_MAX_SIZE 미지정 = Hikari 기본 10)에 붙어 있으면 풀이 꽉 찼다는 뜻이다.
    echo "[백엔드 커넥션 수 / 풀 최대 ${DB_POOL_MAX_SIZE:-10}]"
    $DC exec -T postgres psql -U bambi -d bambi -tA -c \
        "SELECT '  backend = ' || count(*) FROM pg_stat_activity
         WHERE datname='bambi' AND application_name <> 'psql';"

    # 풀이 꽉 찬 것과 **요청이 커넥션을 기다린 것**은 다른 사실이다.
    # 위 커넥션 수만으로는 대기 여부를 말할 수 없다 — 그걸 말하려면 pending 이 필요하다.
    #   pending = 지금 커넥션을 기다리는 스레드 수
    #   acquire = 커넥션을 얻기까지 걸린 시간(누적 합/횟수)
    # 관리 포트(9090)는 컨테이너 안에서만 열려 있다. 그래서 docker exec 로 들어가 읽는다.
    # (actuator 의존성이 없으면 조용히 건너뛴다 — Phase 1 이전 실행분과 호환)
    # 파싱은 셸로만 한다. 예전 버전은 python f-string 안에 escape 한 따옴표를 써서
    # SyntaxError 가 났고, 그 결과 "actuator 미탑재" 라고 **오진**했다(2026-08-12).
    # actuator 는 멀쩡했다. 파서를 단순하게 유지하는 편이 안전하다.
    echo "[Hikari 대기]"
    for m in hikaricp.connections.pending hikaricp.connections.acquire; do
        v=$($DC exec -T backend sh -c \
            "curl -s --max-time 2 http://localhost:9090/actuator/metrics/${m}" 2>/dev/null \
            | tr '{' '\n' \
            | sed -n 's/.*"statistic":"\([A-Z_]*\)","value":\([0-9.E-]*\).*/\1=\2/p' \
            | tr '\n' ' ')
        echo "  ${m} = ${v:-읽기실패}"
    done

    sleep "$INTERVAL"
done

echo "=== 응답 크기 (부하와 무관하게 1회) ==="
size=$(curl -s http://localhost/api/feed/public | wc -c)
count=$(curl -s http://localhost/api/feed/public | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]))')
echo "  게스트 피드: ${size} bytes / ${count} 건"
