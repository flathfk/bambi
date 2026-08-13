#!/bin/bash
# 부하 테스트 타깃 VM 부트스트랩 — Docker 설치 → 스택 기동 → 시드 → 준비 확인.
#
# 이 스크립트는 **처음부터 끝까지 한 번에** 돌도록 만들었다. 중간에 실패하면 그 자리에서
# 멈추고 이유를 출력한다(set -e). 재실행해도 안전하다(이미 설치된 건 건너뛴다).
#
# 사용 (VM 안에서):
#   cd ~/loadtest && bash bootstrap.sh
#
# GHCR 패키지가 private 이면 아래 두 값을 환경변수로 준다.
#   GHCR_USER=... GHCR_PAT=... bash bootstrap.sh
set -euo pipefail

echo "── 1. Docker 설치 확인 ──"
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker 설치 중..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" || true
else
    echo "이미 설치됨: $(docker --version)"
fi

# usermod 는 재로그인이 필요해서 이번 실행에는 sudo 로 간다.
DC="sudo docker compose"

echo "── 2. 소스 받기 (public 레포, 인증 불필요) ──"
# GHCR 패키지는 private 이라 임시 VM 에서 pull 이 안 된다. PAT 를 VM 에 두지 않으려고
# public 레포를 clone 해 직접 빌드한다. 측정 대상 커밋을 정확히 남길 수 있는 이점도 있다.
if ! command -v git >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y git; fi
if [ -d bambi-service-api/.git ]; then
    git -C bambi-service-api fetch --depth 1 origin main && git -C bambi-service-api reset --hard origin/main
else
    git clone --depth 1 https://github.com/hk-toss-final-project/bambi-service-api.git
fi
MEASURED_SHA=$(git -C bambi-service-api rev-parse --short HEAD)
echo "측정 대상 커밋: $MEASURED_SHA"

echo "── 3. 스택 기동 (nginx · backend · postgres) ──"
$DC -f docker-compose.target.yml up -d --build

echo "── 4. 백엔드 준비 대기 (Gradle 빌드 + Flyway, 최대 600초) ──"
ready=0
for i in $(seq 1 120); do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health || echo 000)
    if [ "$code" = "200" ]; then ready=1; break; fi
    echo "  대기 $i/120 (http=$code)"
    sleep 5
done
if [ "$ready" != "1" ]; then
    echo "❌ 백엔드가 준비되지 않았습니다. 로그를 확인하세요:"
    $DC -f docker-compose.target.yml logs --tail=50 backend
    exit 1
fi
echo "✅ /api/health 200"

echo "── 5. 시드 데이터 ──"
$DC -f docker-compose.target.yml exec -T postgres psql -U bambi -d bambi < seed.sql

echo "── 6. 측정용 계정 생성 ──"
signup=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost/api/auth/signup \
    -H 'Content-Type: application/json' \
    -d '{"email":"loadtest@bambi.test","password":"loadtest1234","displayName":"부하"}')
# 409 = 이미 있음(재실행). 둘 다 정상으로 본다.
if [ "$signup" = "201" ] || [ "$signup" = "409" ]; then
    echo "✅ 계정 준비됨 (http=$signup)"
else
    echo "⚠️  가입 응답 http=$signup — 인증 시나리오는 못 돌 수 있습니다."
fi

echo "── 7. 확인 ──"
echo -n "공개 피드 카드 수: "
curl -s http://localhost/api/feed/public | head -c 200; echo
$DC -f docker-compose.target.yml ps

cat <<'EOF'

✅ 타깃 준비 완료.

이제 k6 VM 에서 다음을 실행하세요 (TARGET_IP 는 이 VM 의 내부 IP):
  k6 run -e BASE=http://TARGET_IP feed-guest.js
  k6 run -e BASE=http://TARGET_IP -e EMAIL=loadtest@bambi.test -e PASSWORD=loadtest1234 feed-auth.js

부하 중 이 VM 에서 관찰:
  sudo docker stats --no-stream
  sudo docker compose -f docker-compose.target.yml exec -T postgres \
    psql -U bambi -d bambi -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"
EOF
