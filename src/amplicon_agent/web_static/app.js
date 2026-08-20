const state = {
  uploadId: null,
  inspection: null,
  plan: null,
  functions: [],
  presets: [],
  user: null,
  modelSettings: null,
  assistantHistory: [],
  metadataDraft: null,
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

const statusNames = {
  ready: "检查通过",
  warning: "有警告",
  blocked: "已阻断",
  verified: "已验证",
  experimental: "实验性",
  planned: "待验证",
  prepared: "已准备",
  queued: "任务已排队",
  running: "分析运行中",
  succeeded: "分析完成",
  failed: "运行失败",
  pass: "校验通过",
};

const orientationNames = {
  feature_by_sample: "Feature × Sample",
  sample_by_feature: "Sample × Feature（将自动转置）",
  unknown: "无法识别",
};

const analysisScopeNames = { targeted: "针对问题选择", full: "全部适用分析" };
const baselineMethodNames = {
  qc: "数据质量控制（QC）",
  alpha: "Alpha 多样性分析",
  beta: "Beta 多样性分析",
  composition: "群落组成分析",
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

function parseDelimitedHeader(line) {
  const delimiters = ["\t", ",", ";"];
  const delimiter = delimiters.sort((a, b) => line.split(b).length - line.split(a).length)[0];
  const values = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (char === '"') {
      if (quoted && line[index + 1] === '"') {
        value += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (char === delimiter && !quoted) {
      values.push(value.trim());
      value = "";
    } else {
      value += char;
    }
  }
  values.push(value.trim());
  return values.filter(Boolean);
}

async function populateMetadataColumns(file) {
  const select = $("#group-column");
  select.disabled = true;
  select.innerHTML = '<option value="">正在读取 metadata 表头…</option>';
  if (!file) return;
  try {
    const text = await file.slice(0, 65536).text();
    const firstLine = text.replace(/^\uFEFF/, "").split(/\r?\n/).find((line) => line.trim());
    const columns = firstLine ? parseDelimitedHeader(firstLine) : [];
    if (columns.length < 2) throw new Error("至少需要 Sample ID 列和一个分组候选列");
    select.innerHTML = [
      '<option value="">请选择分组列</option>',
      ...columns.slice(1).map((column) => `<option value="${escapeHtml(column)}">${escapeHtml(column)}</option>`),
    ].join("");
    select.disabled = false;
  } catch (error) {
    select.innerHTML = `<option value="">表头读取失败：${escapeHtml(error.message)}</option>`;
    notify(`无法读取 metadata 表头：${error.message}`, "error");
  }
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
              <span><strong>${escapeHtml(item.display_name)}</strong>
                <small class="function-description">${escapeHtml(item.description)}</small>
                <small class="function-meta">${escapeHtml(statusNames[item.status] || item.status)}${tags ? ` · ${escapeHtml(tags)}` : ""}</small>
              </span>
            </label>`;
        }).join("")}
      </div>
    </div>`).join("");
}

function functionName(functionId) {
  return baselineMethodNames[functionId]
    || state.functions.find((item) => item.function_id === functionId)?.display_name
    || "扩展分析方法";
}

function renderInspection(data) {
  const result = data.inspection;
  state.inspection = result;
  state.uploadId = data.upload_id || state.uploadId;
  const warnings = result.warnings || [];
  const blockers = result.blockers || [];
  const groups = Object.entries(result.groups || {});
  const selectedGroup = $("#group-column").value;
  const metadataColumns = result.metadata_columns || [];
  const groupOptions = metadataColumns.slice(1).map((column) => `
    <option value="${escapeHtml(column)}" ${column === selectedGroup ? "selected" : ""}>${escapeHtml(column)}</option>`).join("");
  $("#inspection-result").classList.remove("hidden");
  $("#inspection-result").innerHTML = `
    <div class="metric-grid">
      <div class="metric"><small>检查状态</small><strong>${escapeHtml(statusNames[result.status] || result.status)}</strong></div>
      <div class="metric"><small>样本数</small><strong>${escapeHtml(result.sample_count)}</strong></div>
      <div class="metric"><small>特征数</small><strong>${escapeHtml(result.feature_count)}</strong></div>
      <div class="metric"><small>丰度表方向</small><strong>${escapeHtml(orientationNames[result.orientation] || result.orientation)}</strong></div>
    </div>
    <p><strong>分组：</strong></p>
    <div class="group-tags">${groups.map(([name, count]) => `<span>${escapeHtml(name)} · n=${escapeHtml(count)}</span>`).join("") || "<span>未识别</span>"}</div>
    <p><strong>分类层级：</strong>${escapeHtml(result.selected_taxonomy_rank || "未识别")}</p>
    ${warnings.length ? `<p><strong>警告：</strong></p><ul class="message-list">${warnings.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
    ${blockers.length ? `<p><strong>阻断项：</strong></p><ul class="message-list blockers">${blockers.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
    <div class="manual-recheck">
      <label><span>重新指定分组列</span><select id="reinspect-group">${groupOptions}</select></label>
      <button id="reinspect-button" type="button" class="button">按此分组重新检查</button>
    </div>
    ${(warnings.length || blockers.length) ? `<div class="inspection-actions"><button id="ask-ai-from-inspection" type="button" class="button primary">在右侧咨询 AI</button><span class="muted">只有点击发送后才调用模型。</span></div>` : ""}
  `;
  const groupNames = groups.map(([name]) => name);
  const controlGuess = groupNames.find((name) => /control|ctrl|ck|对照/i.test(name)) || groupNames[0] || "";
  const treatmentGuess = groupNames.filter((name) => name !== controlGuess);
  $("#plan-form [name=controls]").value = controlGuess;
  $("#plan-form [name=treatments]").value = treatmentGuess.join(", ");
  $("#reinspect-button").addEventListener("click", reinspectUpload);
  const askButton = $("#ask-ai-from-inspection");
  if (askButton) askButton.addEventListener("click", () => {
    const summary = [...blockers, ...warnings].join("；");
    $("#assistant-form textarea").value = `请解释当前检查问题，并结合我的实验设计帮助我处理：${summary}`;
    openAssistant();
    $("#assistant-form textarea").focus();
  });
  const designSection = $("#design-section");
  const designBadge = $("#design-lock");
  designSection.classList.toggle("locked", blockers.length > 0);
  designBadge.textContent = blockers.length ? "存在阻断项，请先修正" : "文件检查完成";
  designBadge.className = `status-pill ${blockers.length ? "error" : warnings.length ? "warning" : "success"}`;
  $("#assistant-context").textContent = `当前：数据检查 · ${statusNames[result.status] || result.status}`;
  if (!blockers.length) {
    activateStep(1);
    $("#design-section").scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

async function reinspectUpload() {
  if (!state.uploadId) return;
  const button = $("#reinspect-button");
  const groupColumn = $("#reinspect-group").value;
  if (!groupColumn) {
    notify("请先选择分组列。", "error");
    return;
  }
  busy(button, true, "正在重新检查…");
  try {
    $("#group-column").value = groupColumn;
    const data = await jsonRequest(`/api/uploads/${state.uploadId}/reinspect`, {
      method: "POST",
      body: {
        group_column: groupColumn,
        batch_column: $("#inspect-form [name=batch_column]").value.trim() || null,
        gradient_column: $("#inspect-form [name=gradient_column]").value.trim() || null,
      },
    });
    renderInspection(data);
    notify(data.inspection.blockers?.length ? "重新检查后仍有阻断项。" : "重新检查完成，可以继续确认实验设计。", data.inspection.blockers?.length ? "error" : "success");
  } catch (error) {
    notify(`重新检查失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
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
    notify(data.inspection.blockers?.length ? "文件检查发现阻断项，可重新选择分组列或咨询右侧 AI。" : "文件检查完成，请确认实验设计与分析范围。", data.inspection.blockers?.length ? "error" : "success");
  } catch (error) {
    notify(`检查失败：${error.message}`, "error");
  } finally {
    busy(button, false);
  }
}

function openAssistant() {
  $("#assistant-panel").classList.remove("collapsed");
  $("#assistant-open").classList.add("hidden");
}

function closeAssistant() {
  $("#assistant-panel").classList.add("collapsed");
  $("#assistant-open").classList.remove("hidden");
}

function addAssistantMessage(role, content) {
  state.assistantHistory.push({ role, content });
  state.assistantHistory = state.assistantHistory.slice(-12);
  const article = document.createElement("article");
  article.className = `assistant-message ${role === "user" ? "user" : "assistant"}`;
  article.innerHTML = `<small>${role === "user" ? "你" : "AI 助手"}</small><p>${escapeHtml(content)}</p>`;
  $("#assistant-messages").appendChild(article);
  $("#assistant-messages").scrollTop = $("#assistant-messages").scrollHeight;
}

function renderMetadataDraft(draft, warning = "") {
  const box = $("#metadata-draft");
  if (!draft) {
    state.metadataDraft = null;
    if (warning) {
      box.classList.remove("hidden");
      box.innerHTML = `<h3>未生成修改预览</h3><p>${escapeHtml(warning)}</p>`;
    } else {
      box.classList.add("hidden");
      box.innerHTML = "";
    }
    return;
  }
  state.metadataDraft = draft;
  const proposal = draft.proposal || {};
  const columns = (draft.preview_columns || []).slice(0, 7);
  const rows = (draft.preview_rows || []).slice(0, 8);
  const notes = [...(proposal.questions || []), ...(proposal.warnings || [])];
  box.classList.remove("hidden");
  box.innerHTML = `
    <h3>metadata 修正预览</h3>
    <p>${escapeHtml(proposal.summary || "模型已提出结构化修改建议。")}</p>
    <p><strong>建议分组列：</strong>${escapeHtml(proposal.recommended_group_column)}</p>
    <p><strong>可执行修改：</strong>${escapeHtml((draft.changes || []).length)} 项；样本行数保持 ${escapeHtml(draft.row_count)} 行。</p>
    ${notes.length ? `<ul>${notes.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : ""}
    <div class="table-scroll"><table class="metadata-preview"><thead><tr>${columns.map((column) => `<th>${escapeHtml(column)}</th>`).join("")}</tr></thead><tbody>
      ${rows.map((row) => `<tr>${columns.map((column) => `<td title="${escapeHtml(row[column] ?? "")}">${escapeHtml(row[column] ?? "")}</td>`).join("")}</tr>`).join("")}
    </tbody></table></div>
    <label class="check-row"><input id="accept-metadata-draft" type="checkbox"><span>我已核对列名、分组含义和预览内容，同意生成新的 metadata 文件</span></label>
    <button id="apply-metadata-draft" class="button primary wide" type="button">应用这份预览</button>
  `;
  $("#apply-metadata-draft").addEventListener("click", applyMetadataDraft);
}

function replaceGroupOptions(columns, selected) {
  const select = $("#group-column");
  select.innerHTML = [
    '<option value="">请选择分组列</option>',
    ...columns.slice(1).map((column) => `<option value="${escapeHtml(column)}">${escapeHtml(column)}</option>`),
  ].join("");
  select.disabled = false;
  select.value = selected;
}

async function applyMetadataDraft() {
  if (!state.metadataDraft || !$("#accept-metadata-draft").checked) {
    notify("请先核对预览并勾选确认。", "error");
    return;
  }
  const button = $("#apply-metadata-draft");
  busy(button, true, "正在应用…");
  try {
    const data = await jsonRequest(`/api/uploads/${state.uploadId}/metadata/apply`, {
      method: "POST",
      body: { draft_id: state.metadataDraft.draft_id, accepted: true },
    });
    replaceGroupOptions(data.inspection.metadata_columns || [], data.group_column);
    $("#inspect-form [name=batch_column]").value = data.batch_column || "";
    $("#inspect-form [name=gradient_column]").value = data.gradient_column || "";
    renderInspection({ upload_id: state.uploadId, inspection: data.inspection });
    const design = data.experimental_design || {};
    if (design.research_question) $("#plan-form [name=research_question]").value = design.research_question;
    if (design.sample_type) $("#plan-form [name=sample_type]").value = design.sample_type;
    if (design.controls?.length) $("#plan-form [name=controls]").value = design.controls.join(", ");
    if (design.treatments?.length) $("#plan-form [name=treatments]").value = design.treatments.join(", ");
    const notes = [design.design_notes, design.gradient_direction].filter(Boolean).join("\n");
    if (notes) $("#plan-form [name=design_notes]").value = notes;
    $("#metadata-draft").innerHTML = `<h3>已应用修正</h3><p>原始 metadata 保留不变，后续分析将使用修正后的副本。</p><a href="${escapeHtml(data.download_url)}" class="button" target="_blank">下载修正后的 metadata</a>`;
    state.metadataDraft = null;
    addAssistantMessage("assistant", "修正后的 metadata 已通过程序复检。请继续核对实验设计；原始文件仍然保留。 ");
    notify("metadata 修正副本已生成并重新检查。", data.inspection.blockers?.length ? "error" : "success");
  } catch (error) {
    notify(`应用修正失败：${error.message}`, "error");
    busy(button, false);
  }
}

async function sendAssistantMessage(event) {
  event.preventDefault();
  const textarea = event.currentTarget.elements.message;
  const message = textarea.value.trim();
  if (!message) return;
  const previous = state.assistantHistory.slice(-6);
  addAssistantMessage("user", message);
  textarea.value = "";
  const button = $("#assistant-send");
  busy(button, true, "思考中…");
  try {
    const data = await jsonRequest("/api/assistant/chat", {
      method: "POST",
      body: {
        message,
        upload_id: state.uploadId,
        plan_id: state.plan?.plan_id || null,
        group_column: $("#group-column").value || null,
        batch_column: $("#inspect-form [name=batch_column]").value.trim() || null,
        gradient_column: $("#inspect-form [name=gradient_column]").value.trim() || null,
        history: previous,
        settings: state.modelSettings,
      },
    });
    addAssistantMessage("assistant", data.reply);
    renderMetadataDraft(data.metadata_draft, data.proposal_warning || "");
    await loadMe();
  } catch (error) {
    addAssistantMessage("assistant", `调用失败：${error.message}`);
    await loadMe().catch(() => null);
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
        <p>${escapeHtml(analysisScopeNames[contract.analysis_scope] || contract.analysis_scope)} · ${contract.functions.length} 个分析方法</p>
        <div class="method-tags">${contract.functions.map((item) => `<span>${escapeHtml(functionName(item))}</span>`).join("")}</div>
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
  $("#assistant-context").textContent = "当前：分析计划已生成，等待人工审批";
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
      throw new Error("高级方法参数必须是有效 JSON");
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
    <p><strong>状态：</strong>${escapeHtml(statusNames[status] || status)}</p>
    ${queueStatus ? `<p><strong>队列状态：</strong>${escapeHtml(statusNames[queueStatus] || queueStatus)}</p>` : ""}
    ${(contract.error || contract.job?.error) ? `<ul class="message-list blockers"><li>${escapeHtml(contract.error || contract.job.error)}</li></ul>` : ""}
  `;
  const done = status === "succeeded";
  $("#report-button").classList.toggle("hidden", !done);
  $("#interpret-button").classList.toggle("hidden", !done);
  $("#assistant-context").textContent = `当前：${statusNames[status] || status} · 可询问进度、报错或结果`;
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
      body: state.modelSettings || {},
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
      ? `共享模型本月剩余 ${quota.monthly_model_remaining}/${quota.monthly_model_quota} 次；对话、解读或连接测试成功后各扣 1 次，填写自己的 API Key 不占共享额度。`
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
  $$("input[type=file]").forEach((input) => input.addEventListener("change", async () => {
    const label = document.querySelector(`[data-file-label="${input.name}"]`);
    label.textContent = input.files[0]?.name || "选择文件";
    input.closest(".file-card").classList.toggle("has-file", Boolean(input.files.length));
    if (input.name === "metadata") await populateMetadataColumns(input.files[0]);
  }));
  $("#inspect-form").addEventListener("submit", inspectFiles);
  $("#plan-form").addEventListener("submit", createPlan);
  $("#approval-form").addEventListener("submit", approveAndRun);
  $("#preset-targeted").addEventListener("click", () => applyFunctionPreset(false));
  $("#preset-full").addEventListener("click", () => applyFunctionPreset(true));
  $("#report-button").addEventListener("click", openReport);
  $("#interpret-button").addEventListener("click", interpretResults);
  $("#assistant-form").addEventListener("submit", sendAssistantMessage);
  $("#assistant-collapse").addEventListener("click", closeAssistant);
  $("#assistant-open").addEventListener("click", openAssistant);
  $$("[data-ai-prompt]").forEach((button) => button.addEventListener("click", () => {
    $("#assistant-form textarea").value = button.dataset.aiPrompt;
    $("#assistant-form textarea").focus();
  }));
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
  if (window.innerWidth <= 1350) closeAssistant();
  await loadMe();
  await Promise.all([loadHealth(), loadFunctions()]);
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
});
