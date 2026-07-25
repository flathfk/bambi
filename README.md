# Bambi

## 사용법

### 저장소 클론 및 서브모듈 초기화

```bash
# 클론할 때 서브모듈까지 한 번에 받으려면:
git clone --recurse-submodules https://github.com/hk-toss-final-project/bambi.git

# 이미 클론한 뒤 서브모듈을 받아야 하면:
git submodule update --init --recursive
```

### 상위 저장소에 기록된 서브모듈 버전으로 갱신

```bash
# pull 할 때 서브모듈까지 같이 갱신하려면:
git pull --recurse-submodules
git submodule update --init --recursive
```

### 모든 서브모듈의 `main`을 최신화하고 상위 저장소에 반영

먼저 서브모듈 내부에 커밋되지 않은 변경 사항이 없는지 확인합니다.

```bash
git submodule foreach --recursive 'git status --short --branch'
```

모든 서브모듈을 `main` 브랜치로 전환하고 원격의 최신 커밋을 가져옵니다.

```bash
git submodule foreach --recursive \
  'git switch main && git pull --ff-only origin main'
```

변경된 서브모듈 커밋을 확인한 뒤, 상위 저장소의 서브모듈 포인터를 커밋하고
푸시합니다.

```bash
git diff --submodule=log

git add \
  bambi-admin-web \
  bambi-agent-api \
  bambi-build \
  bambi-service-api \
  bambi-service-web

git commit -m "chore: update submodule revisions"
git push origin main
```

`--ff-only`는 로컬과 원격 이력이 갈라진 경우 자동으로 병합 커밋을 만들지 않고
작업을 중단합니다. 위 과정은 서브모듈 내부에 새 커밋을 만드는 것이 아니라, 상위
저장소가 가리키는 서브모듈 커밋 포인터만 갱신합니다.

서브모듈 내부에 직접 만든 커밋까지 함께 푸시해야 한다면, 각 서브모듈의 커밋을
먼저 푸시하거나 다음 명령을 사용할 수 있습니다.

```bash
git push --recurse-submodules=on-demand origin main
```
