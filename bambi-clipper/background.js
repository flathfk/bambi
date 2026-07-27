// 밤새비서 클리퍼 — 툴바 아이콘 클릭 = 즉시 저장 (팝업 없음)
const DEFAULT_API = "http://34.64.53.250";

async function getCfg() {
  const { bc_api, bc_tok } = await chrome.storage.local.get(["bc_api", "bc_tok"]);
  return { api: (bc_api || DEFAULT_API).replace(/\/$/, ""), tok: bc_tok || null };
}

// 아이콘 위 배지로 상태 표시 (팝업이 없으니 이걸로 피드백)
function badge(text, color, clearMs) {
  chrome.action.setBadgeText({ text });
  if (color) chrome.action.setBadgeBackgroundColor({ color });
  if (clearMs) setTimeout(() => chrome.action.setBadgeText({ text: "" }), clearMs);
}

// 페이지 안에서 실행되어 본문 추출 (article/main 우선, 없으면 body)
function extract() {
  const pick = document.querySelector("article") || document.querySelector("main") || document.body;
  const text = (pick?.innerText || "").replace(/\n{3,}/g, "\n\n").trim().slice(0, 20000);
  return { url: location.href, title: document.title, content: text };
}

async function saveTab(tab) {
  const { api, tok } = await getCfg();
  if (!tok) {                       // 로그인 안 됨 → 설정 페이지 열기
    badge("!", "#6B7684", 3000);
    chrome.runtime.openOptionsPage();
    return;
  }
  badge("…", "#6B7684");
  try {
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id }, func: extract,
    });
    // bookmarks 계약: {url, title, content} — url은 본문에 섞지 않고 필드로 분리
    const body = {
      url: result.url,
      title: (result.title || result.url).slice(0, 500),
      content: result.content,
    };
    const r = await fetch(api + "/api/bookmarks", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + tok },
      body: JSON.stringify(body),
    });
    if (r.status === 401) {         // 세션 만료 → 토큰 지우고 재로그인 유도
      await chrome.storage.local.remove("bc_tok");
      badge("!", "#D4342C", 3000);
      chrome.runtime.openOptionsPage();
      return;
    }
    if (!r.ok) throw new Error("save " + r.status);
    const j = await r.json().catch(() => ({}));
    if (j.success === false) throw new Error(j?.error?.message || "실패");
    badge("✓", "#12805C", 2000);
  } catch (e) {
    badge("!", "#D4342C", 3000);
    console.error("[밤새비서 클리퍼]", e);
  }
}

chrome.action.onClicked.addListener((tab) => { if (tab?.id) saveTab(tab); });
