const state = {
  uploadId: null,
  inspection: null,
  plan: null,
  functions: [],
  presets: [],
  user: null,
  modelSettings: null,
  pollTimer: null,
  installPrompt: null,
};

const categoryNames = {
  alpha_diversity: "Alpha 多样性",
  beta_diversity: "Beta 多样性与排序",
  composition: "群落组成与可视化",
  differential_abundance: "差异丰度",
  biomarker_ml: "机器学习与生物标志物",
  network: "共现网络",
  community_assembly: "群落组装与来源",
  functional_prediction: "功能预测",
  other: "其他分析",
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

async function request(path, options = {}) {
  const method = String(options.method || "GET").toUpperCase();
  const headers = { ...(options.headers || {}) };
  if (!["GET", "HEAD", "OPTIONS"].includes(method)) {
    const csrf = sessionStorage.getItem("ampliconCsrfToken");
    if (csrf) headers["X-CSRF-Token"] = csrf;
  }
  if (options.body && !(options.body instanceof FormData) && typeof options.body !== "string") {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(options.body);
  }
  const response = await fetch(path, { ...options, headers });
  if (response.status === 401) {
    sessionStorage.removeItem("ampliconCsrfToken");
    location.href = `/login?return=${encodeURIComponent(location.pathname)}`;
    throw new Error("登录已过期");
  }
  if (!response.ok) {
    let message = `${response.status} ${response.statusText}`;
    try {
      const data = await response.json();
      message = typeof data.detail === "string" ? data.detail : JSON.stringify(data.detail);
    } catch (_) {}
    throw new Error(message);
  }
  return response;
}

async function loadMe() {
  const user = await jsonRequest("/api/auth/me");
  state.user = user;
  sessionStorage.setItem("ampliconCsrfToken", user.csrf_token);
  $("#account-button").textContent = user.display_name || "我的账户";
  $("#retention-state").textContent = `数据保留 ${user.retention_days} 天 · 共享模型剩余 ${user.monthly_model_remaining} 次`;
  return user;
}

async function jsonRequest(path, options = {}) {
  return (await request(path, options)).json();
}

function notify(message, type = "info") {
  const box = $("#notice");
  box.textContent = message;
  box.className = `notice ${type}`;
  window.clearTimeout(box._timer);
  box._timer = window.setTimeout(() => box.classList.add("hidden"), 7000);
}

function busy(button, enabled, label = "处理中…") {
  if (!button) return;
  if (enabled) {
    button.dataset.original = button.textContent;
    button.textContent = label;
    button.disabled = true;
  } else {
    button.textContent = button.dataset.original || button.textContent;
    button.disabled = false;
  }
}

function unlock(sectionId, badgeId, text) {
  $(`#${sectionId}`).classList.remove("locked");
  const badge = $(`#${badgeId}`);
  if (badge) {
    badge.textContent = text;
    badge.className = "status-pill success";
  }
}

function activateStep(index) {
  $$(".step").forEach((item, itemIndex) => item.classList.toggle("active", itemIndex === index));
}

function splitGroups(value) {
  return value.split(/[,，;；\n]/).map((item) => item.trim()).filter(Boolean);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function loadHealth() {
  try {
    const data = await jsonRequest("/api/health");
    $("#health-dot").className = "ok";
    $("#health-text").textContent = `服务正常 · v${data.version}`;
  } catch (error) {
    $("#health-dot").className = "error";
    $("#health-text").textContent = "服务连接失败";
  }
}

async function loadFunctions() {
  try {
    const data = await jsonRequest("/api/functions");
    state.functions = data.functions;
    renderFunctions();
  } catch (error) {
    $("#function-list").innerHTML = `<p class="muted">${escapeHtml(error.message)}。如已设置访问令牌，请点击右上角填写。</p>`;
  }
}

function renderFunctions() {
  const groups = {};
  state.functions.forEach((item) => {
    (groups[item.category] ||= []).push(item);
  });
  $("#function-list").innerHTML = Object.entries(groups).map(([category, items]) => `
    <div class="function-group">
      <h4>${escapeHtml(categoryNames[category] || category)} · ${items.length}</h4>
      <div class="function-options">
        ${items.map((item) => {
          const disabled = item.status === "blocked";
          const requirements = item.specification || {};
          const tags = [
            requirements.requires_tree ? "需树" : "",
            requirements.requires_ko_annotation ? "需 KO" : "",
            requirements.requires_pathway_annotation ? "需 Pathway" : "",
            requirements.requires_source_sink ? "需来源/汇配置" : "",
          ].filter(Boolean).join(" · ");
          return `
            <label class="function-option ${disabled ? "disabled" : ""}">
              <input type="checkbox" name="analysis_function" value="${escapeHtml(item.function_id)}"
                data-status="${escapeHtml(item.status)}" ${disabled ? "disabled" : ""}>
              <span><strong>${escapeHtml(item.function_id)}</strong>
                <small>${escapeHtml(item.status)}${tags ? ` · ${escapeHtml(tags)}` : ""}</small>
              </span>
            </label>`;
        }).join("")}
      </div>
    </div>`).join("");
}

function renderInspection(data) {
  const result = data.inspection;
  state.inspection = result;
  state.uploadId = data.upload_id;
  const warnings = result.warnings || [];
  const blockers = result.blockers || [];
  const groups = Object.entries(result.groups || {});
  $("#inspection-result").classList.remove("hidden");
  $("#inspection-result").innerHTML = `
    <div class="metric-grid">
      <div class="metric"><small>检查状态</small><strong>${escapeHtml(result.status)}</strong></div>
      <div class="metric"><small>样本数</small><strong>${escapeHtml(result.sample_count)}</strong></div>
      <div class="metric"><small>特征数</small><strong>${escapeHtml(result.feature_count)}</strong></div>
      <div class="metric"><small>丰度表方向</small><strong>${escapeHtml(result.orientation)}</strong></div>
    </div>
    <p><strong>分组：</strong></p>
    <div class="group-tags">${groups.map(([name, count]) => `<span>${escapeHtml(name)} · n=${escapeHtml(count)}</span>`).join("") || "<span>未识别</span>"}</div>
    <p><strong>分类层级：</strong>${escapeHtml(result.selected_taxonomy_rank || "未识别")}</p>
    ${warnings.length ? `<p><strong>警告：</strong></p><ul class="message-list">${warnings.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
    ${blockers.length ? `<p><strong>阻断项：</strong></p><ul class="message-list blockers">${blockers.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
  `;
  const groupNames = groups.map(([name]) => name);
  const controlGuess = groupNames.find((name) => /control|ctrl|ck|对照/i.test(name)) || groupNames[0] || "";
  const treatmentGuess = groupNames.filter((name) => name !== controlGuess);
  $("#plan-form [name=controls]").value = controlGuess;
  $("#plan-form [name=treatments]").value = treatmentGuess.join(", ");
  unlock("design-section", "design-lock", blockers.length ? "存在阻断项，请修正" : "文件检查完成");
  activateStep(1);
  $("#design-section").scrollIntoView({ behavior: "smooth", block: "start" });
}

async function inspectFiles(event) {
  event.preventDefault();
  const button = $("#inspect-button");
  busy(button, true, "正在检查文件…");
  try {
    const form = new FormData(event.currentTarget);
    ["batch_column", "gradient_column"].forEach((name) => {
      if (!String(form.get(name) || "").trim()) form.delete(name);
    });
    const data = await jsonRequest("/api/uploads/inspect", { method: "POST", body: form });
    renderInspection(data);
    notify("文件检查完成，请确认实验设计与分析范围。", data.inspection.blockers?.length ? "error" : "success");
  } catch (error) {
    notify(`检查失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
}

function selectedFunctions() {
  return $$("input[name=analysis_function]:checked").map((item) => item.value);
}

function applyFunctionPreset(full) {
  $$("input[name=analysis_function]").forEach((item) => {
    item.checked = full && item.dataset.status === "verified" && !item.disabled;
  });
  $("#plan-form [name=analysis_scope]").value = full ? "full" : "targeted";
}

function renderContract(contract) {
  state.plan = contract;
  const warnings = contract.warnings || [];
  const blockers = contract.blockers || [];
  const design = contract.project_design || {};
  const confirmation = `CONFIRM ${contract.plan_id}`;
  $("#contract-view").classList.remove("empty");
  $("#contract-view").innerHTML = `
    <div class="contract-grid">
      <article><h4>研究设计</h4>
        <p>${escapeHtml(design.research_question)}</p>
        <p><strong>样本：</strong>${escapeHtml(design.sample_type)}</p>
        <p><strong>参照：</strong>${escapeHtml((design.controls || []).join(", "))}</p>
        <p><strong>处理：</strong>${escapeHtml((design.treatments || []).join(", "))}</p>
      </article>
      <article><h4>分析范围</h4>
        <p>${escapeHtml(contract.analysis_scope)} · ${contract.functions.length} 个模块/函数</p>
        <p>${contract.functions.map((item) => `<code>${escapeHtml(item)}</code>`).join(" ")}</p>
      </article>
      <article><h4>输入与参数</h4>
        <p>分组列：${escapeHtml(contract.group_column)}；置换：${escapeHtml(contract.parameters.permutations)}；Top N：${escapeHtml(contract.parameters.top_n)}</p>
        <p>计划编号：<code>${escapeHtml(contract.plan_id)}</code></p>
      </article>
      <article><h4>审查结果</h4>
        ${warnings.length ? `<ul>${warnings.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : "<p>没有额外警告。</p>"}
        ${blockers.length ? `<ul class="message-list blockers">${blockers.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
      </article>
    </div>
    <p><strong>一次性确认文本：</strong> <code>${escapeHtml(confirmation)}</code></p>
  `;
  unlock("approval-section", "approval-lock", blockers.length ? "计划被阻断" : "等待人工确认");
  const form = $("#approval-form");
  form.classList.toggle("hidden", blockers.length > 0);
  form.querySelector("input").value = "";
  form.querySelector("input").placeholder = confirmation;
  activateStep(2);
  $("#approval-section").scrollIntoView({ behavior: "smooth", block: "start" });
}

async function createPlan(event) {
  event.preventDefault();
  if (!state.uploadId) {
    notify("请先上传并检查文件。", "error");
    return;
  }
  const button = $("#plan-button");
  busy(button, true, "正在生成计划…");
  const form = new FormData(event.currentTarget);
  try {
    let functionParameters;
    try {
      functionParameters = JSON.parse(String(form.get("function_parameters") || "{}"));
    } catch (_) {
      throw new Error("函数参数必须是有效 JSON");
    }
    const payload = {
      upload_id: state.uploadId,
      group_column: $("#inspect-form [name=group_column]").value.trim(),
      batch_column: $("#inspect-form [name=batch_column]").value.trim() || null,
      gradient_column: $("#inspect-form [name=gradient_column]").value.trim() || null,
      research_question: String(form.get("research_question") || "").trim(),
      sample_type: String(form.get("sample_type") || "").trim(),
      controls: splitGroups(String(form.get("controls") || "")),
      treatments: splitGroups(String(form.get("treatments") || "")),
      design_notes: String(form.get("design_notes") || "").trim() || null,
      analysis_scope: String(form.get("analysis_scope") || "targeted"),
      functions: selectedFunctions(),
      permutations: Number(form.get("permutations")),
      top_n: Number(form.get("top_n")),
      function_parameters: functionParameters,
    };
    const contract = await jsonRequest("/api/plans", { method: "POST", body: payload });
    renderContract(contract);
    notify(contract.blockers.length ? "计划已生成，但存在阻断项，不能执行。" : "计划已生成，请核对后输入确认文本。", contract.blockers.length ? "error" : "success");
  } catch (error) {
    notify(`计划生成失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
}

async function approveAndRun(event) {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button");
  busy(button, true, "正在提交审批…");
  try {
    const confirmation = event.currentTarget.elements.confirmation.value.trim();
    const approval = await jsonRequest(`/api/plans/${state.plan.plan_id}/approve`, {
      method: "POST",
      body: { confirmation },
    });
    await jsonRequest(`/api/plans/${state.plan.plan_id}/run`, {
      method: "POST",
      body: { approval_token: approval.approval_token },
    });
    unlock("result-section", null, "");
    activateStep(3);
    $("#result-section").scrollIntoView({ behavior: "smooth", block: "start" });
    updateRunView({ status: "running", plan_id: state.plan.plan_id });
    startPolling();
    notify("审批成功，分析任务已开始。", "success");
  } catch (error) {
    notify(`无法运行：${error.message}`, "error");
    busy(button, false);
  }
}

function updateRunView(contract) {
  const queueStatus = contract.job?.status;
  const status = queueStatus === "queued" ? "queued" : contract.status;
  const badge = $("#run-status");
  const bar = $("#progress-bar");
  badge.textContent = {
    prepared: "已准备", queued: "任务已排队", running: "分析运行中", succeeded: "分析完成", failed: "运行失败",
  }[status] || status;
  badge.className = `status-pill ${status === "succeeded" ? "success" : status === "failed" ? "error" : "warning"}`;
  bar.className = status === "succeeded" ? "done" : ["queued", "running"].includes(status) ? "running" : "";
  $("#run-detail").classList.remove("empty");
  $("#run-detail").innerHTML = `
    <p><strong>计划编号：</strong><code>${escapeHtml(contract.plan_id)}</code></p>
    <p><strong>状态：</strong>${escapeHtml(status)}</p>
    ${queueStatus ? `<p><strong>队列状态：</strong>${escapeHtml(queueStatus)}</p>` : ""}
    ${(contract.error || contract.job?.error) ? `<ul class="message-list blockers"><li>${escapeHtml(contract.error || contract.job.error)}</li></ul>` : ""}
  `;
  const done = status === "succeeded";
  $("#report-button").classList.toggle("hidden", !done);
  $("#interpret-button").classList.toggle("hidden", !done);
}

function startPolling() {
  window.clearInterval(state.pollTimer);
  const poll = async () => {
    try {
      const contract = await jsonRequest(`/api/plans/${state.plan.plan_id}`);
      updateRunView(contract);
      if (["succeeded", "failed"].includes(contract.status)) {
        window.clearInterval(state.pollTimer);
        const result = await jsonRequest(`/api/plans/${state.plan.plan_id}/validation`).catch(() => null);
        if (contract.status === "succeeded") {
          notify(result?.status === "pass" ? "分析与自动校验均已通过。" : "分析完成，请检查校验详情。", result?.status === "pass" ? "success" : "error");
        }
      }
    } catch (error) {
      notify(`状态读取失败：${error.message}`, "error");
    }
  };
  poll();
  state.pollTimer = window.setInterval(poll, 3000);
}

async function openReport() {
  if (!state.plan) return;
  const button = $("#report-button");
  busy(button, true, "正在打开…");
  try {
    const response = await request(`/api/plans/${state.plan.plan_id}/report`);
    const url = URL.createObjectURL(await response.blob());
    window.open(url, "_blank", "noopener");
    window.setTimeout(() => URL.revokeObjectURL(url), 60000);
  } catch (error) {
    notify(`报告打开失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
}

async function interpretResults() {
  const button = $("#interpret-button");
  busy(button, true, "模型正在解读…");
  try {
    await jsonRequest(`/api/plans/${state.plan.plan_id}/interpret`, {
      method: "POST",
      body: modelPayload(),
    });
    notify("针对当前实验设计的结果解读已写入报告。", "success");
    await loadMe();
    await openReport();
  } catch (error) {
    notify(`模型解读失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
}

async function loadModelSettings() {
  try {
    const [presetData, config] = await Promise.all([
      jsonRequest("/api/model/presets"),
      jsonRequest("/api/model"),
    ]);
    state.presets = presetData.presets;
    $("#model-provider").innerHTML = state.presets.map((item) => `<option value="${escapeHtml(item.id)}">${escapeHtml(item.label)}</option>`).join("");
    const saved = sessionStorage.getItem("ampliconModelSettings");
    state.modelSettings = saved ? JSON.parse(saved) : state.modelSettings;
    const value = state.modelSettings || config.server_default;
    $("#model-provider").value = value.provider;
    $("#model-protocol").value = value.protocol;
    $("#model-base-url").value = value.base_url;
    $("#model-name").value = value.model;
    $("#model-form").elements.api_key.value = value.api_key || "";
    $("#model-form").elements.remember_model.checked = Boolean(saved);
    const quota = config.quota;
    $("#model-state").textContent = config.server_default.api_key_configured
      ? `共享模型本月剩余 ${quota.monthly_model_remaining}/${quota.monthly_model_quota} 次；填写自己的 API Key 不占共享额度。`
      : "共享模型尚未配置；请填写自己的 API Key。";
  } catch (error) {
    $("#model-state").textContent = error.message;
  }
}

function applyProviderPreset() {
  const preset = state.presets.find((item) => item.id === $("#model-provider").value);
  if (!preset) return;
  $("#model-protocol").value = preset.protocol;
  $("#model-base-url").value = preset.base_url;
  $("#model-name").value = preset.model;
}

function modelPayload(formElement = $("#model-form")) {
  const form = new FormData(formElement);
  const payload = {
    provider: String(form.get("provider") || ""),
    protocol: String(form.get("protocol") || ""),
    base_url: String(form.get("base_url") || ""),
    model: String(form.get("model") || ""),
  };
  const apiKey = String(form.get("api_key") || "").trim();
  if (apiKey) payload.api_key = apiKey;
  return payload;
}

async function saveModel(event) {
  event.preventDefault();
  const formElement = event.currentTarget;
  const payload = modelPayload(formElement);
  state.modelSettings = payload;
  if (formElement.elements.remember_model.checked) {
    sessionStorage.setItem("ampliconModelSettings", JSON.stringify(payload));
  } else {
    sessionStorage.removeItem("ampliconModelSettings");
  }
  $("#model-dialog").close();
  notify(payload.api_key ? "已使用你自己的模型密钥；仅在当前浏览器会话中保留。" : "已选择共享模型额度。", "success");
}

async function testModel() {
  const button = $("#test-model");
  busy(button, true, "正在测试…");
  try {
    const data = await jsonRequest("/api/model/test", {
      method: "POST",
      body: modelPayload(),
    });
    $("#model-state").textContent = `连接成功：${data.reply}`;
    await loadMe();
  } catch (error) {
    $("#model-state").textContent = `连接失败：${error.message}`;
  } finally {
    busy(button, false);
  }
}

function renderAccount() {
  const user = state.user;
  $("#account-summary").innerHTML = `
    <div class="metric-grid">
      <div class="metric"><small>账户</small><strong>${escapeHtml(user.email)}</strong></div>
      <div class="metric"><small>数据保留期</small><strong>${escapeHtml(user.retention_days)} 天</strong></div>
      <div class="metric"><small>共享模型额度</small><strong>${escapeHtml(user.monthly_model_remaining)} / ${escapeHtml(user.monthly_model_quota)}</strong></div>
      <div class="metric"><small>活动任务</small><strong>${escapeHtml(user.active_jobs)}</strong></div>
    </div>`;
}

async function logout() {
  await jsonRequest("/api/auth/logout", { method: "POST", body: {} });
  sessionStorage.clear();
  location.href = "/";
}

async function deleteMyData(deleteAccount = false) {
  const input = $("#account-form").elements.delete_confirmation;
  const required = deleteAccount ? "DELETE MY ACCOUNT" : "DELETE MY DATA";
  if (input.value.trim() !== required) {
    notify(`请输入确认文本：${required}`, "error");
    return;
  }
  const message = deleteAccount
    ? "确定永久注销账户并删除全部数据吗？此操作无法撤销。"
    : "确定删除全部上传、计划和分析结果吗？此操作无法撤销。";
  if (!window.confirm(message)) return;
  const path = deleteAccount ? "/api/me/account" : "/api/me/data";
  await jsonRequest(path, {
    method: "DELETE",
    body: { confirmation: required },
  });
  sessionStorage.removeItem("ampliconModelSettings");
  if (deleteAccount) {
    sessionStorage.clear();
    location.href = "/";
    return;
  }
  state.uploadId = null;
  state.plan = null;
  $("#account-dialog").close();
  await loadMe();
  notify("你的上传、计划和分析结果已删除。", "success");
}

function wireEvents() {
  $$("[data-close-dialog]").forEach((button) => button.addEventListener("click", () => {
    document.getElementById(button.dataset.closeDialog).close();
  }));
  $$(".step").forEach((item, index) => item.addEventListener("click", () => {
    activateStep(index);
    $(`#${item.dataset.target}`).scrollIntoView({ behavior: "smooth", block: "start" });
  }));
  $$("input[type=file]").forEach((input) => input.addEventListener("change", () => {
    const label = document.querySelector(`[data-file-label="${input.name}"]`);
    label.textContent = input.files[0]?.name || "选择文件";
    input.closest(".file-card").classList.toggle("has-file", Boolean(input.files.length));
  }));
  $("#inspect-form").addEventListener("submit", inspectFiles);
  $("#plan-form").addEventListener("submit", createPlan);
  $("#approval-form").addEventListener("submit", approveAndRun);
  $("#preset-targeted").addEventListener("click", () => applyFunctionPreset(false));
  $("#preset-full").addEventListener("click", () => applyFunctionPreset(true));
  $("#report-button").addEventListener("click", openReport);
  $("#interpret-button").addEventListener("click", interpretResults);
  $("#open-model").addEventListener("click", async () => {
    await loadModelSettings();
    $("#model-dialog").showModal();
  });
  $("#model-provider").addEventListener("change", applyProviderPreset);
  $("#model-form").addEventListener("submit", saveModel);
  $("#test-model").addEventListener("click", testModel);
  $("#account-button").addEventListener("click", async () => {
    await loadMe();
    renderAccount();
    $("#account-form").elements.delete_confirmation.value = "";
    $("#account-dialog").showModal();
  });
  $("#logout-button").addEventListener("click", () => logout().catch((error) => notify(error.message, "error")));
  $("#delete-data-button").addEventListener("click", () => deleteMyData(false).catch((error) => notify(error.message, "error")));
  $("#delete-account-button").addEventListener("click", () => deleteMyData(true).catch((error) => notify(error.message, "error")));
  $("#install-app").addEventListener("click", async () => {
    if (!state.installPrompt) return;
    state.installPrompt.prompt();
    await state.installPrompt.userChoice;
    state.installPrompt = null;
    $("#install-app").classList.add("hidden");
  });
}

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  state.installPrompt = event;
  $("#install-app").classList.remove("hidden");
});

window.addEventListener("DOMContentLoaded", async () => {
  wireEvents();
  await loadMe();
  await Promise.all([loadHealth(), loadFunctions()]);
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
});
