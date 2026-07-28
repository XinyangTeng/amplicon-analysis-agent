const notice = document.querySelector("#auth-notice");

function showNotice(message, type = "error") {
  notice.textContent = message;
  notice.className = `notice ${type}`;
}

function setBusy(button, enabled, label) {
  if (enabled) {
    button.dataset.label = button.textContent;
    button.textContent = label;
    button.disabled = true;
  } else {
    button.textContent = button.dataset.label || button.textContent;
    button.disabled = false;
  }
}

function returnPath() {
  const value = new URLSearchParams(location.search).get("return") || "/app";
  return value.startsWith("/") && !value.startsWith("//") ? value : "/app";
}

async function submitAuth(event, endpoint) {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button[type=submit]");
  setBusy(button, true, endpoint.endsWith("register") ? "正在注册…" : "正在登录…");
  const form = new FormData(event.currentTarget);
  const payload = Object.fromEntries(form.entries());
  if ("privacy_accepted" in payload) payload.privacy_accepted = true;
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.detail || "请求失败");
    sessionStorage.setItem("ampliconCsrfToken", data.user.csrf_token);
    location.href = returnPath();
  } catch (error) {
    showNotice(error.message);
    setBusy(button, false);
  }
}

document.querySelectorAll("[data-auth-tab]").forEach((button) => {
  button.addEventListener("click", () => {
    const target = button.dataset.authTab;
    document.querySelectorAll("[data-auth-tab]").forEach((item) => {
      item.classList.toggle("active", item === button);
    });
    document.querySelector("#login-form").classList.toggle("hidden", target !== "login");
    document.querySelector("#register-form").classList.toggle("hidden", target !== "register");
    notice.classList.add("hidden");
  });
});

document.querySelector("#login-form").addEventListener("submit", (event) => {
  submitAuth(event, "/api/auth/login");
});
document.querySelector("#register-form").addEventListener("submit", (event) => {
  submitAuth(event, "/api/auth/register");
});

fetch("/api/auth/me").then((response) => {
  if (response.ok) location.href = returnPath();
}).catch(() => {});
