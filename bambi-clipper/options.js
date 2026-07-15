// 밤새비서 클리퍼 설정 — 로그인 / API 주소 (chrome.storage.local 사용)
const $ = (id) => document.getElementById(id);
const DEFAULT_API = "https://our-faster-psychiatry-officer.trycloudflare.com";
const msg = (t, k) => { const m = $("msg"); m.textContent = t; m.className = k || ""; };

async function load() {
  const { bc_api, bc_tok } = await chrome.storage.local.get(["bc_api", "bc_tok"]);
  $("api").value = bc_api || DEFAULT_API;
  const inned = !!bc_tok;
  $("inState").hidden = !inned;
  $("loginForm").hidden = inned;
  $("logoutBtn").hidden = !inned;
}

async function login() {
  const api = ($("api").value.trim() || DEFAULT_API).replace(/\/$/, "");
  await chrome.storage.local.set({ bc_api: api });
  const email = $("email").value.trim(), password = $("pw").value;
  if (!email || !password) return msg("이메일·비밀번호를 입력해주세요.", "bad");
  msg("로그인 중…");
  try {
    const r = await fetch(api + "/api/auth/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const j = await r.json();
    if (!r.ok || j.success === false) throw new Error(j?.error?.message || "로그인 실패");
    await chrome.storage.local.set({ bc_tok: j.data.accessToken });
    msg("✅ 로그인됨! 이제 아이콘만 누르면 저장돼요.", "ok");
    load();
  } catch (e) { msg("❌ " + e.message, "bad"); }
}

async function logout() { await chrome.storage.local.remove("bc_tok"); msg(""); load(); }

$("api").addEventListener("change", async () => {
  await chrome.storage.local.set({ bc_api: ($("api").value.trim() || DEFAULT_API).replace(/\/$/, "") });
});
$("loginBtn").addEventListener("click", login);
$("logoutBtn").addEventListener("click", logout);
load();
