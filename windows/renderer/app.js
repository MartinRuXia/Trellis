(() => {
  'use strict';

  const ROOT_ID = '__root__';
  const PALETTE = ['#8B5CF6', '#2E55DB', '#06B6D4', '#F59E0B', '#14B8A6', '#6366F1', '#DB2777', '#EF4444'];
  const $ = (sel, root = document) => root.querySelector(sel);
  const IS_WIN = navigator.userAgent.toLowerCase().includes('windows');
  const SEP = IS_WIN ? '\\' : '/';

  const state = {
    templates: [],
    recents: [],
    selectedTemplateId: null,
    selectedNodeId: null,
    editingId: null,
    editingMode: 'none',
    canvasActive: false,
    zoom: 1,
    layout: null,
    draftName: '',
    draftTarget: '',
    lastCreated: null
  };

  const els = {
    templateList: $('#template-list'),
    recentList: $('#recent-list'),
    recentSection: $('#recent-section'),
    sideCount: $('#side-count'),
    templateName: $('#template-name'),
    templateNote: $('#template-note'),
    stats: $('#template-stats'),
    banner: $('#creating-banner'),
    canvas: $('#canvas'),
    canvasInner: $('#canvas-inner'),
    canvasContent: $('#canvas-content'),
    links: $('#links'),
    nodes: $('#nodes'),
    editor: $('#inline-editor'),
    emptyHint: $('#empty-hint'),
    projectName: $('#project-name'),
    targetPath: $('#target-path'),
    previewPath: $('#preview-path'),
    previewMeta: $('#preview-meta'),
    nameError: $('#name-error'),
    successCard: $('#success-card'),
    successName: $('#success-name'),
    successPath: $('#success-path'),
    infoName: $('#info-name'),
    infoCount: $('#info-count'),
    infoDepth: $('#info-depth'),
    revealAfter: $('#reveal-after'),
    toast: $('#toast'),
    modal: $('#modal'),
    modalTitle: $('#modal-title'),
    modalMessage: $('#modal-message'),
    modalInput: $('#modal-input'),
    modalConfirm: $('#modal-confirm'),
    modalCancel: $('#modal-cancel'),
    contextMenu: $('#context-menu')
  };

  const nodeEls = new Map();
  let saveTimer = null;
  let committing = false;
  let toastTimer = null;
  let modalHandler = null;

  // ---------------- utils ----------------

  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'n' + Math.random().toString(36).slice(2) + Date.now().toString(36));

  function selectedTemplate() {
    return state.templates.find(t => t.id === state.selectedTemplateId) || null;
  }

  function walk(list, fn, parent = null) {
    for (const node of list || []) {
      fn(node, parent);
      walk(node.children || [], fn, node);
    }
  }

  function findNode(list, id) {
    let found = null;
    walk(list, n => { if (n.id === id) found = n; });
    return found;
  }

  function findParent(list, id, parent = null) {
    for (const node of list || []) {
      if (node.id === id) return parent;
      const p = findParent(node.children || [], id, node);
      if (p !== undefined) return p;
    }
    return undefined;
  }

  function removeNode(list, id) {
    const index = list.findIndex(n => n.id === id);
    if (index >= 0) { list.splice(index, 1); return true; }
    for (const node of list) if (removeNode(node.children || [], id)) return true;
    return false;
  }

  function insertAfter(list, id, node) {
    const index = list.findIndex(n => n.id === id);
    if (index >= 0) { list.splice(index + 1, 0, node); return true; }
    for (const item of list) if (insertAfter(item.children || [], id, node)) return true;
    return false;
  }

  function cloneWithNewIds(node) {
    return {
      id: uid(),
      name: node && node.name ? String(node.name) : '',
      children: ((node && node.children) || []).map(cloneWithNewIds)
    };
  }

  function countNodes(list) {
    let count = 0;
    walk(list, () => { count += 1; });
    return count;
  }

  function depthOf(list) {
    let depth = 0;
    const rec = (arr, level) => {
      depth = Math.max(depth, level);
      for (const node of arr || []) rec(node.children || [], level + 1);
    };
    rec(list, 0);
    return depth;
  }

  const pad2 = n => String(n).padStart(2, '0');

  function expand(raw, projectName, date = new Date()) {
    const map = {
      '{项目名}': projectName,
      '{日期}': `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`,
      '{yyyyMMdd}': `${date.getFullYear()}${pad2(date.getMonth() + 1)}${pad2(date.getDate())}`,
      '{时间}': `${pad2(date.getHours())}-${pad2(date.getMinutes())}`,
      '{年}': String(date.getFullYear()),
      '{月}': pad2(date.getMonth() + 1),
      '{日}': pad2(date.getDate())
    };
    let out = raw || '';
    for (const [token, value] of Object.entries(map)) out = out.split(token).join(value);
    return out.trim();
  }

  function validateName(raw) {
    const name = (raw || '').trim();
    if (!name) return '名称不能为空';
    if (/[\\/:*?"<>|]/.test(name)) return '名称不能包含 \\ / : * ? " < > |';
    if (name.startsWith('.')) return '名称不能以 “.” 开头';
    if (/[. ]$/.test(name)) return '名称不能以空格或 “.” 结尾';
    if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i.test(name)) return '这是 Windows 保留名称';
    if (name.length > 120) return '名称过长';
    return null;
  }

  function collectIssues(list, projectName, prefix = '') {
    const issues = [];
    const seen = new Set();
    for (const node of list || []) {
      const name = expand(node.name, projectName);
      const full = prefix + name;
      const err = validateName(name);
      if (err) issues.push({ path: full, message: err });
      if (seen.has(name)) issues.push({ path: full, message: '同级目录中存在重名文件夹' });
      seen.add(name);
      issues.push(...collectIssues(node.children || [], projectName, full + SEP));
    }
    return issues;
  }

  function expandTree(list, projectName) {
    return (list || []).map(node => ({
      name: expand(node.name, projectName),
      children: expandTree(node.children || [], projectName)
    }));
  }

  function formatTime(timestamp) {
    const date = new Date(timestamp || Date.now());
    return `${date.getFullYear()}/${pad2(date.getMonth() + 1)}/${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }

  // ---------------- layout ----------------

  function buildLayout(template) {
    const NODE_W = 150;
    const ROOT_W = 96;
    const ROW = 48;
    const STEP = 206;
    const PAD = 40;
    const rootX = PAD + ROOT_W / 2;
    const levelOneX = rootX + ROOT_W / 2 + 76 + NODE_W / 2;

    const nodes = [];
    const edges = [];
    let cursor = 0;

    function place(node, depth, branch) {
      const children = (node.children || []).map(child => place(child, depth + 1, branch));
      let y;
      if (!children.length) {
        y = PAD + cursor + ROW / 2;
        cursor += ROW;
      } else {
        y = (children[0].y + children[children.length - 1].y) / 2;
      }
      const x = levelOneX + (depth - 1) * STEP;
      const color = PALETTE[branch % PALETTE.length];
      const model = { id: node.id, name: node.name, depth, color, x, y, w: NODE_W, root: false };
      nodes.push(model);
      for (const child of children) {
        edges.push({ from: { x: x + NODE_W / 2, y }, to: { x: child.x - child.w / 2, y: child.y }, color });
      }
      return model;
    }

    const tops = (template.nodes || []).map((node, index) => place(node, 1, index));
    const rootY = tops.length ? (tops[0].y + tops[tops.length - 1].y) / 2 : PAD + ROW / 2;
    const root = { id: ROOT_ID, name: '根节点', depth: 0, color: '#94A3B8', x: rootX, y: rootY, w: ROOT_W, root: true };
    nodes.push(root);
    for (const child of tops) {
      edges.push({ from: { x: rootX + ROOT_W / 2, y: rootY }, to: { x: child.x - child.w / 2, y: child.y }, color: child.color });
    }

    const maxX = Math.max(...nodes.map(n => n.x + n.w / 2), 0);
    const maxY = Math.max(...nodes.map(n => n.y + 28), 0);
    return {
      nodes,
      edges,
      width: Math.max(maxX + PAD, 620),
      height: Math.max(maxY + PAD, 460)
    };
  }

  function drawLinks(layout) {
    let markup = '';
    for (const edge of layout.edges) {
      const dx = Math.max(26, (edge.to.x - edge.from.x) * 0.5);
      markup += `<path d="M ${edge.from.x} ${edge.from.y} C ${edge.from.x + dx} ${edge.from.y}, ${edge.to.x - dx} ${edge.to.y}, ${edge.to.x} ${edge.to.y}" fill="none" stroke="${edge.color}" stroke-opacity="0.5" stroke-width="1.8" stroke-linecap="round"/>`;
    }
    els.links.innerHTML = markup;
    els.links.setAttribute('width', String(layout.width));
    els.links.setAttribute('height', String(layout.height));
    els.links.setAttribute('viewBox', `0 0 ${layout.width} ${layout.height}`);
  }

  function applyZoom() {
    if (!state.layout) return;
    const { width, height } = state.layout;
    els.canvasInner.style.width = `${width * state.zoom}px`;
    els.canvasInner.style.height = `${height * state.zoom}px`;
    els.canvasContent.style.width = `${width}px`;
    els.canvasContent.style.height = `${height}px`;
    els.canvasContent.style.transform = `scale(${state.zoom})`;
  }

  // ---------------- rendering ----------------

  function renderAll() {
    renderSidebar();
    renderHeader();
    renderCanvas();
    renderInspector();
    updateBanner();
  }

  function renderSidebar() {
    els.templateList.innerHTML = '';
    if (!state.templates.length) {
      const empty = document.createElement('div');
      empty.className = 'muted small';
      empty.style.padding = '8px 9px';
      empty.textContent = '还没有模板';
      els.templateList.appendChild(empty);
    }
    for (const template of state.templates) {
      const item = document.createElement('div');
      item.className = 'side-item' + (template.id === state.selectedTemplateId ? ' selected' : '');
      item.innerHTML = '<span class="folder-ico"></span><span class="meta"><span class="name"></span><span class="sub"></span></span>';
      item.querySelector('.name').textContent = template.name || '未命名模板';
      item.querySelector('.sub').textContent = `${countNodes(template.nodes)} 个文件夹`;
      item.addEventListener('click', () => selectTemplate(template.id));
      item.addEventListener('contextmenu', event => {
        event.preventDefault();
        showTemplateMenu(event, template.id);
      });
      els.templateList.appendChild(item);
    }

    els.recentList.innerHTML = '';
    if (!state.recents.length) {
      const empty = document.createElement('div');
      empty.className = 'muted small';
      empty.style.padding = '8px 9px';
      empty.textContent = '还没有生成过项目';
      els.recentList.appendChild(empty);
    }
    for (const recent of state.recents) {
      const item = document.createElement('div');
      item.className = 'side-item recent';
      item.innerHTML = '<span class="clock">◷</span><span class="meta"><span class="name"></span><span class="sub"></span></span>';
      item.querySelector('.name').textContent = recent.name;
      item.querySelector('.sub').textContent = formatTime(recent.createdAt);
      item.title = recent.path;
      item.addEventListener('click', () => window.trellis.reveal(recent.path));
      item.addEventListener('contextmenu', event => {
        event.preventDefault();
        openContextMenu(event.clientX, event.clientY, [
          { label: '在资源管理器中显示', action: () => window.trellis.reveal(recent.path) },
          { label: '重命名文件夹…', action: () => renameRecent(recent) },
          { sep: true },
          { label: '从列表移除', danger: true, action: () => { state.recents = state.recents.filter(r => r.id !== recent.id); saveSoon(); renderSidebar(); } }
        ]);
      });
      els.recentList.appendChild(item);
    }

    els.sideCount.textContent = `${state.templates.length}`;
  }

  function renderHeader() {
    const template = selectedTemplate();
    const disabled = !template;
    $('#add-root').disabled = disabled;
    $('#add-root-2').disabled = disabled;
    $('#template-menu').disabled = disabled;

    if (!template) {
      els.templateName.value = '';
      els.templateNote.value = '';
      els.stats.textContent = '还没有模板，点左下角「新建模板」开始';
      return;
    }
    if (document.activeElement !== els.templateName) els.templateName.value = template.name || '';
    if (document.activeElement !== els.templateNote) els.templateNote.value = template.note || '';
    els.stats.textContent = `${countNodes(template.nodes)} 个文件夹 · ${depthOf(template.nodes)} 级 · 更新于 ${formatTime(template.updatedAt)}`;
  }

  function renderCanvas() {
    const template = selectedTemplate();
    if (!template) {
      nodeEls.forEach(el => el.remove());
      nodeEls.clear();
      els.links.innerHTML = '';
      els.canvasContent.style.width = '620px';
      els.canvasContent.style.height = '460px';
      els.canvasInner.style.width = '620px';
      els.canvasInner.style.height = '460px';
      els.emptyHint.textContent = '还没有模板，点左下角「新建模板」开始';
      els.emptyHint.classList.remove('hidden');
      return;
    }

    const layout = buildLayout(template);
    state.layout = layout;
    applyZoom();

    const seen = new Set();
    for (const model of layout.nodes) {
      seen.add(model.id);
      let el = nodeEls.get(model.id);
      if (!el) {
        el = createNodeEl();
        nodeEls.set(model.id, el);
        els.nodes.appendChild(el);
        el.classList.add('enter');
        requestAnimationFrame(() => el.classList.remove('enter'));
      }
      updateNodeEl(el, model);
      el.style.transform = `translate(${model.x - model.w / 2}px, ${model.y - 17}px)`;
    }
    for (const [id, el] of [...nodeEls]) {
      if (!seen.has(id)) {
        el.remove();
        nodeEls.delete(id);
      }
    }

    drawLinks(layout);
    if (!template.nodes.length && !state.editingId) {
      els.emptyHint.textContent = '按 回车 或点「根节点」右侧的 + 添加第一个文件夹';
      els.emptyHint.classList.remove('hidden');
    } else {
      els.emptyHint.classList.add('hidden');
    }
    if (state.editingId) positionEditor();
  }

  function refreshCounts() {
    const template = selectedTemplate();
    if (!template) return;
    els.stats.textContent = `${countNodes(template.nodes)} 个文件夹 · ${depthOf(template.nodes)} 级 · 更新于 ${formatTime(template.updatedAt)}`;
    renderSidebar();
    renderInspector();
  }

  function renderInspector() {
    const template = selectedTemplate();
    if (document.activeElement !== els.projectName) els.projectName.value = state.draftName;
    els.targetPath.textContent = state.draftTarget || '未选择';
    els.infoName.textContent = template ? template.name : '—';
    els.infoCount.textContent = `${template ? countNodes(template.nodes) : 0} 个`;
    els.infoDepth.textContent = `${template ? depthOf(template.nodes) : 0} 级`;
    updatePreview();
    if (state.lastCreated) {
      els.successCard.classList.remove('hidden');
      els.successName.textContent = state.lastCreated.name;
      els.successPath.textContent = state.lastCreated.path;
    } else {
      els.successCard.classList.add('hidden');
    }
  }

  function updatePreview() {
    const template = selectedTemplate();
    const name = state.draftName.trim();
    if (!state.draftTarget) {
      els.previewPath.textContent = '请先选择目标位置';
    } else {
      els.previewPath.textContent = state.draftTarget + SEP + (name || '{项目名称}');
    }

    const err = name ? validateName(name) : null;
    if (err) {
      els.nameError.textContent = err;
      els.nameError.classList.remove('hidden');
    } else {
      els.nameError.classList.add('hidden');
    }

    if (!template) {
      els.previewMeta.textContent = '';
      return;
    }
    const issues = collectIssues(template.nodes, name || '项目');
    const parts = [`${countNodes(template.nodes)} 个文件夹`];
    if (issues.length) parts.push(`${issues.length} 处命名问题`);
    els.previewMeta.textContent = parts.join(' · ');
    els.previewMeta.style.color = issues.length ? '#B45309' : '';
  }

  function updateBanner() {
    if (state.editingMode === 'creating') {
      els.banner.classList.remove('hidden');
    } else {
      els.banner.classList.add('hidden');
    }
  }

  // ---------------- nodes ----------------

  function createNodeEl() {
    const el = document.createElement('div');
    el.className = 'node';
    el.innerHTML = '<span class="folder-ico"></span><span class="name"></span><span class="count"></span><button class="plus" title="新建子文件夹">＋</button>';
    el.addEventListener('click', event => {
      if (event.target.closest('.plus')) return;
      handleNodeClick(el.dataset.id);
    });
    el.querySelector('.plus').addEventListener('click', event => {
      event.stopPropagation();
      activateCanvas();
      if (el.dataset.id === ROOT_ID) createRootNode();
      else createChild(el.dataset.id, true);
    });
    el.addEventListener('contextmenu', event => {
      event.preventDefault();
      showNodeMenu(event, el.dataset.id);
    });
    return el;
  }

  function updateNodeEl(el, model) {
    el.dataset.id = model.id;
    el.className = 'node' + (model.root ? ' root' : model.depth === 1 ? ' depth1' : ' leaf') + (state.selectedNodeId === model.id ? ' selected' : '');
    el.style.setProperty('--node-color', model.color);
    el.querySelector('.name').textContent = model.name && model.name.length ? model.name : '未命名';
    const count = el.querySelector('.count');
    if (!model.root) {
      const node = findNode(selectedTemplate() ? selectedTemplate().nodes : [], model.id);
      const children = (node && node.children) ? node.children.length : 0;
      count.textContent = children ? String(children) : '';
    } else {
      count.textContent = '';
    }
    const plus = el.querySelector('.plus');
    plus.title = model.root ? '新建根文件夹' : '新建子文件夹';
  }

  function handleNodeClick(id) {
    if (!id) return;
    activateCanvas();
    if (state.editingId && state.editingId !== id) commitEdit('end');
    if (id === ROOT_ID) {
      state.selectedNodeId = null;
      renderCanvas();
      return;
    }
    if (state.selectedNodeId === id && !state.editingId) {
      startEdit(id, 'renaming');
    } else {
      state.selectedNodeId = id;
      renderCanvas();
    }
  }

  // ---------------- inline editing ----------------

  function positionEditor() {
    if (!state.layout || !state.editingId) return;
    const model = state.layout.nodes.find(n => n.id === state.editingId);
    if (!model) return;
    els.editor.style.left = `${model.x - model.w / 2 + 4}px`;
    els.editor.style.top = `${model.y - 12}px`;
    els.editor.style.width = `${model.w - 8}px`;
  }

  function startEdit(id, mode) {
    const template = selectedTemplate();
    if (!template) return;
    const node = findNode(template.nodes, id);
    if (!node) return;

    state.editingId = id;
    state.editingMode = mode;
    if (id !== ROOT_ID) state.selectedNodeId = id;
    els.editor.value = mode === 'renaming' ? (node.name || '') : '';
    els.editor.classList.remove('hidden');
    renderCanvas();
    positionEditor();
    updateBanner();
    requestAnimationFrame(() => {
      els.editor.focus();
      els.editor.select();
    });
  }

  function commitEdit(command) {
    if (!state.editingId || committing) return;
    committing = true;

    const id = state.editingId;
    const mode = state.editingMode;
    const template = selectedTemplate();
    const name = els.editor.value.trim();

    state.editingId = null;
    state.editingMode = 'none';
    els.editor.classList.add('hidden');

    if (!template) {
      committing = false;
      return;
    }

    if (!name) {
      if (mode === 'creating') {
        removeNode(template.nodes, id);
        if (state.selectedNodeId === id) state.selectedNodeId = null;
      }
      template.updatedAt = Date.now();
      saveSoon();
      renderAll();
      committing = false;
      return;
    }

    const node = findNode(template.nodes, id);
    if (node) {
      node.name = name;
      template.updatedAt = Date.now();
    }
    saveSoon();
    renderCanvas();
    renderSidebar();
    renderHeader();
    updatePreview();

    committing = false;

    if (mode === 'creating' && command === 'sibling') {
      createSibling(id, true);
    } else if (command === 'child') {
      createChild(id, true);
    } else {
      renderAll();
    }
  }

  function cancelEdit() {
    const id = state.editingId;
    const mode = state.editingMode;
    const template = selectedTemplate();
    state.editingId = null;
    state.editingMode = 'none';
    els.editor.classList.add('hidden');
    if (template && mode === 'creating' && id) {
      removeNode(template.nodes, id);
      if (state.selectedNodeId === id) state.selectedNodeId = null;
      template.updatedAt = Date.now();
      saveSoon();
    }
    renderAll();
  }

  function createSibling(id, edit) {
    const template = selectedTemplate();
    if (!template) return;
    const node = { id: uid(), name: '', children: [] };
    if (!insertAfter(template.nodes, id, node)) return;
    template.updatedAt = Date.now();
    saveSoon();
    state.selectedNodeId = node.id;
    renderCanvas();
    refreshCounts();
    if (edit) startEdit(node.id, 'creating');
  }

  function createChild(parentId, edit) {
    const template = selectedTemplate();
    if (!template) return;
    const node = { id: uid(), name: '', children: [] };
    if (parentId === ROOT_ID) {
      template.nodes.push(node);
    } else {
      const parent = findNode(template.nodes, parentId);
      if (!parent) return;
      parent.children = parent.children || [];
      parent.children.push(node);
    }
    template.updatedAt = Date.now();
    saveSoon();
    state.selectedNodeId = node.id;
    renderCanvas();
    refreshCounts();
    if (edit) startEdit(node.id, 'creating');
  }

  function createRootNode() {
    const template = selectedTemplate();
    if (!template) return;
    activateCanvas();
    createChild(ROOT_ID, true);
  }

  function moveNode(id, delta) {
    const template = selectedTemplate();
    if (!template) return;
    const parent = findParent(template.nodes, id);
    const list = parent ? parent.children : template.nodes;
    const index = list.findIndex(n => n.id === id);
    const target = index + delta;
    if (index < 0 || target < 0 || target >= list.length) return;
    const [node] = list.splice(index, 1);
    list.splice(target, 0, node);
    template.updatedAt = Date.now();
    saveSoon();
    renderCanvas();
    refreshCounts();
  }

  // ---------------- canvas activation ----------------

  function activateCanvas() {
    state.canvasActive = true;
    els.canvas.classList.add('active');
    const active = document.activeElement;
    if (active && active.tagName === 'INPUT' && active !== els.editor) active.blur();
  }

  function deactivateCanvas() {
    if (state.editingId) commitEdit('end');
    state.canvasActive = false;
    els.canvas.classList.remove('active');
  }

  // ---------------- templates ----------------

  function selectTemplate(id) {
    if (state.editingId) cancelEdit();
    state.selectedTemplateId = id;
    state.selectedNodeId = null;
    state.lastCreated = null;
    deactivateCanvas();
    renderAll();
  }

  function newTemplate() {
    showModal({
      title: '新建模板',
      message: '模板只保存目录结构，不会创建任何文件。',
      input: '新模板',
      confirmText: '创建',
      onConfirm: value => {
        const name = value.trim();
        if (!name) return;
        const template = { id: uid(), name, note: '', nodes: [], createdAt: Date.now(), updatedAt: Date.now() };
        state.templates.push(template);
        state.selectedTemplateId = template.id;
        state.selectedNodeId = null;
        saveSoon();
        renderAll();
        toast(`已创建模板「${name}」`);
      }
    });
  }

  function renameTemplate(template) {
    showModal({
      title: '重命名模板',
      message: '只修改模板名称，不影响已生成的项目文件夹。',
      input: template.name,
      confirmText: '保存',
      onConfirm: value => {
        const name = value.trim();
        if (!name) return;
        template.name = name;
        template.updatedAt = Date.now();
        saveSoon();
        renderAll();
      }
    });
  }

  function duplicateTemplate(template) {
    const copy = {
      id: uid(),
      name: uniqueTemplateName(`${template.name} 副本`),
      note: template.note || '',
      nodes: (template.nodes || []).map(cloneWithNewIds),
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
    state.templates.push(copy);
    state.selectedTemplateId = copy.id;
    state.selectedNodeId = null;
    saveSoon();
    renderAll();
    toast(`已复制为「${copy.name}」`);
  }

  function deleteTemplate(template) {
    showModal({
      title: `删除模板「${template.name}」？`,
      message: '只删除模板，不会动磁盘上已经生成的项目文件夹。',
      confirmText: '删除',
      danger: true,
      onConfirm: () => {
        state.templates = state.templates.filter(t => t.id !== template.id);
        if (state.selectedTemplateId === template.id) {
          state.selectedTemplateId = state.templates.length ? state.templates[0].id : null;
          state.selectedNodeId = null;
        }
        saveSoon();
        renderAll();
        toast('模板已删除');
      }
    });
  }

  function uniqueTemplateName(base) {
    let candidate = base;
    let index = 2;
    while (state.templates.some(t => t.name === candidate)) {
      candidate = `${base} ${index}`;
      index += 1;
    }
    return candidate;
  }

  async function exportTemplate(template) {
    const target = template || selectedTemplate();
    if (!target) return;
    const result = await window.trellis.exportTemplate(target.name, target);
    if (result.ok) toast('已导出模板');
    else if (!result.canceled) toast(result.error || '导出失败');
  }

  async function importTemplate() {
    const result = await window.trellis.importTemplate();
    if (!result.ok) {
      if (!result.canceled) toast(result.error || '导入失败');
      return;
    }
    const data = result.data || {};
    const template = {
      id: uid(),
      name: uniqueTemplateName(data.name || '导入的模板'),
      note: data.note || '',
      nodes: (data.nodes || []).map(cloneWithNewIds),
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
    state.templates.push(template);
    state.selectedTemplateId = template.id;
    state.selectedNodeId = null;
    saveSoon();
    renderAll();
    toast(`已导入「${template.name}」`);
  }

  // ---------------- generate ----------------

  async function generate(nameOverride) {
    const template = selectedTemplate();
    if (!template) return;
    const name = String(nameOverride || state.draftName || '').trim();
    const err = validateName(name);
    if (err) {
      els.nameError.textContent = err;
      els.nameError.classList.remove('hidden');
      els.projectName.focus();
      return;
    }
    if (!state.draftTarget) {
      showModal({ title: '提示', message: '请先选择目标位置' });
      return;
    }
    const issues = collectIssues(template.nodes, name);
    if (issues.length) {
      showModal({
        title: '模板有误',
        message: issues.slice(0, 4).map(i => `${i.message}：${i.path}`).join('\n')
      });
      return;
    }

    const result = await window.trellis.createProject({
      target: state.draftTarget,
      name,
      nodes: expandTree(template.nodes, name)
    });

    if (!result.ok) {
      if (result.error === 'exists') {
        const suggestion = await window.trellis.suggestName(state.draftTarget, name);
        showModal({
          title: '已存在同名文件夹',
          message: `目标位置已存在「${name}」。\n可以改用「${suggestion}」，或返回修改名称。`,
          confirmText: `使用「${suggestion}」`,
          onConfirm: () => generate(suggestion)
        });
      } else {
        showModal({ title: '操作失败', message: result.error });
      }
      return;
    }

    const created = { id: uid(), name, path: result.path, templateName: template.name, createdAt: Date.now() };
    state.lastCreated = created;
    state.recents.unshift(created);
    if (state.recents.length > 50) state.recents.length = 50;
    state.draftName = '';
    els.projectName.value = '';
    saveSoon();
    renderSidebar();
    renderInspector();
    toast(`已生成「${name}」`);
    if (els.revealAfter.checked) window.trellis.reveal(result.path);
  }

  async function renameRecent(recent) {
    showModal({
      title: '重命名项目文件夹',
      message: recent.path,
      input: recent.name,
      confirmText: '重命名',
      onConfirm: async value => {
        const name = value.trim();
        const err = validateName(name);
        if (err) { toast(err); return; }
        const result = await window.trellis.renameDir({ dirPath: recent.path, newName: name });
        if (!result.ok) { toast(result.error || '重命名失败'); return; }
        recent.name = name;
        recent.path = result.path;
        saveSoon();
        renderSidebar();
        if (state.lastCreated && state.lastCreated.id === recent.id) {
          state.lastCreated = recent;
          renderInspector();
        }
        toast(`已重命名为「${name}」`);
      }
    });
  }

  // ---------------- menus / modal / toast ----------------

  function showNodeMenu(event, id) {
    if (id === ROOT_ID) {
      openContextMenu(event.clientX, event.clientY, [
        { label: '新建根文件夹', action: () => createRootNode() }
      ]);
      return;
    }
    openContextMenu(event.clientX, event.clientY, [
      { label: '新建子文件夹', action: () => createChild(id, true) },
      { label: '重命名', action: () => startEdit(id, 'renaming') },
      { label: '复制（含子目录）', action: () => duplicateNode(id) },
      { sep: true },
      { label: '上移', action: () => moveNode(id, -1) },
      { label: '下移', action: () => moveNode(id, 1) },
      { sep: true },
      { label: '删除', danger: true, action: () => deleteNode(id) }
    ]);
  }

  function showTemplateMenu(event, id) {
    const template = state.templates.find(t => t.id === id);
    if (!template) return;
    openContextMenu(event.clientX, event.clientY, [
      { label: '重命名模板…', action: () => renameTemplate(template) },
      { label: '复制模板', action: () => duplicateTemplate(template) },
      { label: '导出模板…', action: () => exportTemplate(template) },
      { sep: true },
      { label: '删除模板', danger: true, action: () => deleteTemplate(template) }
    ]);
  }

  function duplicateNode(id) {
    const template = selectedTemplate();
    if (!template) return;
    const node = findNode(template.nodes, id);
    if (!node) return;
    const copy = cloneWithNewIds(node);
    copy.name = `${node.name} 副本`;
    if (!insertAfter(template.nodes, id, copy)) return;
    template.updatedAt = Date.now();
    saveSoon();
    state.selectedNodeId = copy.id;
    renderCanvas();
    refreshCounts();
  }

  function deleteNode(id) {
    const template = selectedTemplate();
    if (!template) return;
    removeNode(template.nodes, id);
    template.updatedAt = Date.now();
    if (state.selectedNodeId === id) state.selectedNodeId = null;
    saveSoon();
    renderCanvas();
    refreshCounts();
  }

  function openContextMenu(x, y, items) {
    const menu = els.contextMenu;
    menu.innerHTML = '';
    for (const item of items) {
      if (item.sep) {
        const sep = document.createElement('div');
        sep.className = 'sep';
        menu.appendChild(sep);
        continue;
      }
      const button = document.createElement('button');
      button.textContent = item.label;
      if (item.danger) button.classList.add('danger');
      button.addEventListener('click', () => {
        closeContextMenu();
        item.action();
      });
      menu.appendChild(button);
    }
    menu.classList.remove('hidden');
    const rect = menu.getBoundingClientRect();
    const left = Math.min(x, window.innerWidth - rect.width - 8);
    const top = Math.min(y, window.innerHeight - rect.height - 8);
    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
  }

  function closeContextMenu() {
    els.contextMenu.classList.add('hidden');
  }

  function showModal(options) {
    modalHandler = options.onConfirm || null;
    els.modalTitle.textContent = options.title || '提示';
    els.modalMessage.textContent = options.message || '';
    els.modalConfirm.textContent = options.confirmText || '确定';
    els.modalConfirm.classList.toggle('danger', !!options.danger);
    els.modalCancel.textContent = options.cancelText || '取消';
    if (options.input !== undefined && options.input !== null) {
      els.modalInput.classList.remove('hidden');
      els.modalInput.value = String(options.input);
    } else {
      els.modalInput.classList.add('hidden');
      els.modalInput.value = '';
    }
    els.modal.classList.remove('hidden');
    if (options.input !== undefined && options.input !== null) {
      requestAnimationFrame(() => {
        els.modalInput.focus();
        els.modalInput.select();
      });
    }
  }

  function hideModal() {
    els.modal.classList.add('hidden');
    modalHandler = null;
  }

  function toast(message) {
    els.toast.textContent = message;
    els.toast.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => els.toast.classList.add('hidden'), 2400);
  }

  function saveSoon() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      window.trellis.saveLibrary({ templates: state.templates, recents: state.recents });
    }, 300);
  }

  // ---------------- events ----------------

  function bindUI() {
    $('#new-template').addEventListener('click', newTemplate);
    $('#add-root').addEventListener('click', createRootNode);
    $('#add-root-2').addEventListener('click', createRootNode);

    $('#template-menu').addEventListener('click', event => {
      const template = selectedTemplate();
      if (!template) return;
      const rect = event.currentTarget.getBoundingClientRect();
      showTemplateMenu({ clientX: rect.left, clientY: rect.bottom + 4 }, template.id);
    });

    els.templateName.addEventListener('input', () => {
      const template = selectedTemplate();
      if (!template) return;
      template.name = els.templateName.value;
      template.updatedAt = Date.now();
      renderSidebar();
      saveSoon();
    });
    els.templateName.addEventListener('blur', () => {
      const template = selectedTemplate();
      if (!template) return;
      const name = els.templateName.value.trim();
      if (!name) {
        els.templateName.value = template.name;
        return;
      }
      template.name = name;
      els.templateName.value = name;
      template.updatedAt = Date.now();
      renderSidebar();
      saveSoon();
    });

    els.templateNote.addEventListener('input', () => {
      const template = selectedTemplate();
      if (!template) return;
      template.note = els.templateNote.value;
      template.updatedAt = Date.now();
      saveSoon();
    });

    els.projectName.addEventListener('input', () => {
      state.draftName = els.projectName.value;
      updatePreview();
    });
    els.projectName.addEventListener('keydown', event => {
      if (event.key === 'Enter') generate();
    });

    $('#paste-name').addEventListener('click', async () => {
      const text = await window.trellis.readClipboard();
      if (text) {
        state.draftName = text.replace(/\s+/g, ' ').trim();
        els.projectName.value = state.draftName;
        els.projectName.focus();
        updatePreview();
      }
    });

    $('#choose-target').addEventListener('click', async () => {
      const dir = await window.trellis.chooseDirectory();
      if (dir) {
        state.draftTarget = dir;
        els.targetPath.textContent = dir;
        updatePreview();
      }
    });

    $('#generate').addEventListener('click', () => generate());
    $('#export-template').addEventListener('click', () => exportTemplate());

    $('#reveal-created').addEventListener('click', () => {
      if (state.lastCreated) window.trellis.reveal(state.lastCreated.path);
    });

    els.revealAfter.addEventListener('change', () => {
      localStorage.setItem('trellis.reveal', els.revealAfter.checked ? '1' : '0');
    });

    els.canvas.addEventListener('click', event => {
      if (event.target.closest('.node')) return;
      if (event.target === els.editor) return;
      if (event.target.closest('#zoom-controls')) return;
      activateCanvas();
      if (state.editingId) commitEdit('end');
      state.selectedNodeId = null;
      renderCanvas();
    });

    els.editor.addEventListener('keydown', event => {
      if (event.key === 'Enter') {
        event.preventDefault();
        commitEdit('sibling');
      } else if (event.key === 'Tab') {
        event.preventDefault();
        commitEdit('child');
      } else if (event.key === 'Escape') {
        event.preventDefault();
        cancelEdit();
      }
    });
    els.editor.addEventListener('blur', () => {
      if (state.editingId && !committing) commitEdit('end');
    });

    document.addEventListener('keydown', event => {
      if (state.editingId) return;
      const tag = document.activeElement && document.activeElement.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (!state.canvasActive || !state.selectedNodeId) return;
      if (event.key === 'Enter') {
        event.preventDefault();
        createSibling(state.selectedNodeId, true);
      } else if (event.key === 'Tab') {
        event.preventDefault();
        createChild(state.selectedNodeId, true);
      }
    });

    document.addEventListener('click', event => {
      if (!event.target.closest('#context-menu')) closeContextMenu();
    });
    document.addEventListener('scroll', closeContextMenu, true);

    $('#sidebar').addEventListener('pointerdown', event => {
      if (!event.target.closest('.side-item')) deactivateCanvas();
    });
    $('#inspector').addEventListener('pointerdown', () => deactivateCanvas());
    $('#editor-header').addEventListener('pointerdown', () => deactivateCanvas());

    document.querySelectorAll('#zoom-controls button').forEach(button => {
      button.addEventListener('click', () => {
        const action = Number(button.dataset.zoom);
        if (action === 0) state.zoom = 1;
        else state.zoom = Math.min(1.8, Math.max(0.5, state.zoom + action * 0.1));
        applyZoom();
        positionEditor();
      });
    });

    els.modalCancel.addEventListener('click', hideModal);
    els.modalConfirm.addEventListener('click', () => {
      const handler = modalHandler;
      const value = els.modalInput.value;
      hideModal();
      if (handler) handler(value);
    });
    els.modalInput.addEventListener('keydown', event => {
      if (event.key === 'Enter') {
        event.preventDefault();
        els.modalConfirm.click();
      } else if (event.key === 'Escape') {
        hideModal();
      }
    });
    els.modal.addEventListener('click', event => {
      if (event.target === els.modal) hideModal();
    });

    window.trellis.onMenuImport(importTemplate);
    window.trellis.onMenuExport(() => exportTemplate());
  }

  // ---------------- init ----------------

  async function init() {
    els.revealAfter.checked = localStorage.getItem('trellis.reveal') !== '0';
    bindUI();

    try {
      const library = await window.trellis.loadLibrary();
      state.templates = (library.templates || []).map(t => ({
        id: t.id || uid(),
        name: t.name || '未命名模板',
        note: t.note || '',
        nodes: Array.isArray(t.nodes) ? t.nodes : [],
        createdAt: t.createdAt || Date.now(),
        updatedAt: t.updatedAt || Date.now()
      }));
      state.recents = Array.isArray(library.recents) ? library.recents : [];
    } catch (error) {
      console.error(error);
    }

    if (!state.templates.length) {
      state.templates.push({
        id: uid(),
        name: '我的模板',
        note: '',
        nodes: [],
        createdAt: Date.now(),
        updatedAt: Date.now()
      });
    }
    state.selectedTemplateId = state.templates[0].id;
    renderAll();
    saveSoon();
  }

  window.addEventListener('DOMContentLoaded', init);
})();
