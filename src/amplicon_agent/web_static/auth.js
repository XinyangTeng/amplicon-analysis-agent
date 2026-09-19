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

const sendCodeButton = document.querySelector("#send-code");

function startCountdown(seconds) {
  sendCodeButton.disabled = true;
  const original = "发送验证码";
  let remaining = seconds;
  sendCodeButton.textContent = `${remaining}s`;
  const timer = setInterval(() => {
    remaining -= 1;
    if (remaining <= 0) {
      clearInterval(timer);
      sendCodeButton.disabled = false;
      sendCodeButton.textContent = original;
    } else {
      sendCodeButton.textContent = `${remaining}s`;
    }
  }, 1000);
}

sendCodeButton.addEventListener("click", async () => {
  const email = document.querySelector("#register-form input[name=email]").value.trim();
  if (!email) {
    showNotice("请先填写邮箱地址");
    return;
  }
  sendCodeButton.disabled = true;
  sendCodeButton.textContent = "发送中…";
  try {
    const response = await fetch("/api/auth/send-code", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.detail || "发送失败");
    showNotice("验证码已发送，请查收邮件", "success");
    startCountdown(60);
  } catch (error) {
    showNotice(error.message);
    sendCodeButton.disabled = false;
    sendCodeButton.textContent = "发送验证码";
  }
});

fetch("/api/auth/me").then((response) => {
  if (response.ok) location.href = returnPath();
}).catch(() => {});
