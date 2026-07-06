# Bambi

## 사용법

```bash
# 클론할 때 서브모듈까지 한 번에 받으려면:
git clone --recurse-submodules https://github.com/hk-toss-final-project/bambi.git

# 이미 클론한 뒤 서브모듈을 받아야 하면:
git submodule update --init --recursive

# pull 할 때 서브모듈까지 같이 갱신하려면:
git pull --recurse-submodules
git submodule update --init --recursive

# 서브모듈 커밋 + 부모 커밋 push
git push --recurse-submodules=on-demand origin main
```
