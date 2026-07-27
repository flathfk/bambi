# 🌙 밤새비서 클리퍼 (Web Clipper)

보고 있는 웹페이지를 **툴바 아이콘 클릭 한 번**에 밤새비서로 저장하는 크롬 확장(Manifest V3).

## 설치 (개발용, 압축 안 함)
1. 크롬 `chrome://extensions`
2. 우측 상단 **개발자 모드** 켜기
3. **압축해제된 확장 프로그램 로드** → 이 `bambi-clipper` 폴더 선택
4. 🌙 아이콘 툴바에 고정

## 쓰는 법
- **처음 1번**: 🌙 아이콘 **우클릭 → 옵션**에서 로그인 (밤새비서 계정)
- **그 다음**: 아무 페이지에서 🌙 **아이콘 클릭** → 배지 `…`→`✓`(초록) 뜨면 저장 완료
- 저장된 자료는 **관심 자료**에 쌓이고, AI가 요약·주제 분류에 활용한다.
  보고서(카드)는 저장 즉시가 아니라 **정기 브리핑/온디맨드 생성**으로 만들어진다 (저장 ≠ 생성, 07-27 확정)

## 동작
- `background.js` — 아이콘 클릭 → 현재 탭 본문 추출(`article`/`main`/`body`) → 백엔드 저장, 배지로 상태 표시
- `options.html/js` — 로그인·API 주소 설정 (`chrome.storage.local` 저장)
- 인증: `POST /api/auth/login` → JWT → 저장 시 `Authorization: Bearer`

## 설정값
- **API 주소**: 옵션 화면 "서버 주소 설정"에서 변경. 기본값 `http://34.64.53.250`(배포 서버).
  HTTPS 터널(trycloudflare) 쓸 땐 여기서 교체 — quick tunnel URL은 서버 재시작마다 바뀐다.
- **저장 엔드포인트**: `POST /api/bookmarks` — `{url, title, content}` (07-27 notes → bookmarks 전환 완료)

## TODO (나중)
- 아이콘 이미지(png) 추가 — 현재는 크롬 기본 아이콘 + 배지
- Readability로 본문 추출 고도화 (광고·메뉴 제거)
- 단축키 저장(`chrome.commands`)
