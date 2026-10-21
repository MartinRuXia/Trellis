const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const path = require('path');
const fs = require('fs');

app.setName('Trellis');

let mainWindow = null;

if (process.env.TRELLIS_TEST === '1') {
  app.setPath('userData', path.join(process.cwd(), '.test-userdata'));
}

function libraryPath() {
  return path.join(app.getPath('userData'), 'library.json');
}

function loadLibrary() {
  try {
    const raw = fs.readFileSync(libraryPath(), 'utf8');
    const data = JSON.parse(raw);
    return { templates: data.templates || [], recents: data.recents || [] };
  } catch {
    return { templates: [], recents: [] };
  }
}

function saveLibrary(data) {
  const file = libraryPath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify({ templates: data.templates || [], recents: data.recents || [] }, null, 2), 'utf8');
  fs.renameSync(tmp, file);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 1040,
    minHeight: 680,
    backgroundColor: '#fbfcfe',
    title: 'Trellis · 目录模板',
    autoHideMenuBar: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });

  if (process.env.TRELLIS_DEV === '1') {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }

  if (process.env.TRELLIS_TEST === '1') {
    mainWindow.webContents.once('did-finish-load', () => {
      setTimeout(async () => {
        try {
          await mainWindow.webContents.executeJavaScript(`(async () => {
            const wait = ms => new Promise(r => setTimeout(r, ms));
            document.querySelector('#add-root').click();
            await wait(250);
            const ed = document.querySelector('#inline-editor');
            ed.value = '01 素材';
            ed.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
            await wait(350);
            const afterEnter = document.querySelectorAll('.node').length;
            const ed2 = document.querySelector('#inline-editor');
            ed2.value = '视频';
            ed2.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
            await wait(350);
            return {
              afterEnter,
              total: document.querySelectorAll('.node').length,
              names: [...document.querySelectorAll('.node .name')].map(n => n.textContent)
            };
          })()`).then(result => {
            console.log('TEST_RESULT ' + JSON.stringify(result));
          });
          if (process.env.TRELLIS_SHOT) {
            const image = await mainWindow.webContents.capturePage();
            fs.writeFileSync(process.env.TRELLIS_SHOT, image.toPNG());
          }
          app.exit(0);
        } catch (error) {
          console.error('TEST_ERROR', error);
          app.exit(1);
        }
      }, 1000);
    });
  }
}

function buildMenu() {
  const template = [
    {
      label: '文件',
      submenu: [
        { label: '导入模板…', click: () => mainWindow && mainWindow.webContents.send('menu-import') },
        { label: '导出当前模板…', click: () => mainWindow && mainWindow.webContents.send('menu-export') },
        { type: 'separator' },
        { role: 'quit', label: '退出' }
      ]
    },
    {
      label: '编辑',
      submenu: [
        { role: 'undo', label: '撤销' },
        { role: 'redo', label: '重做' },
        { type: 'separator' },
        { role: 'cut', label: '剪切' },
        { role: 'copy', label: '复制' },
        { role: 'paste', label: '粘贴' },
        { role: 'selectAll', label: '全选' }
      ]
    },
    {
      label: '视图',
      submenu: [
        { role: 'reload', label: '重新加载' },
        { role: 'toggleDevTools', label: '开发者工具' },
        { type: 'separator' },
        { role: 'resetZoom', label: '实际大小' },
        { role: 'zoomIn', label: '放大' },
        { role: 'zoomOut', label: '缩小' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: '全屏' }
      ]
    },
    {
      label: '帮助',
      submenu: [
        {
          label: '关于 Trellis',
          click: () => {
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: '关于 Trellis',
              message: 'Trellis · 目录模板',
              detail: '版本 ' + app.getVersion() + '\n把常用的项目目录结构保存成模板，一键生成项目文件夹。'
            });
          }
        }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function friendlyFsError(err, target) {
  if (err && err.code === 'EPERM') return `没有写入权限：${target}\n请换一个位置，或用管理员身份运行。`;
  if (err && err.code === 'ENOSPC') return `磁盘空间不足：${target}`;
  if (err && err.code === 'EEXIST') return `已存在同名文件夹：${target}`;
  return `创建文件夹失败：${target}\n${err && err.message ? err.message : err}`;
}

app.whenReady().then(() => {
  app.setAppUserModelId('com.martin.trellis');
  buildMenu();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

ipcMain.handle('library:load', () => loadLibrary());

ipcMain.handle('library:save', (_event, data) => {
  try {
    saveLibrary(data || {});
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
});

ipcMain.handle('dialog:directory', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: '选择生成项目的目标位置',
    properties: ['openDirectory', 'createDirectory'],
    buttonLabel: '选择'
  });
  if (result.canceled || !result.filePaths.length) return null;
  return result.filePaths[0];
});

ipcMain.handle('fs:createProject', (_event, payload) => {
  const { target, name, nodes } = payload || {};
  if (!target || !name) return { ok: false, error: '缺少目标位置或项目名称' };
  const root = path.join(target, name);
  try {
    if (fs.existsSync(root)) return { ok: false, error: 'exists', path: root };
    fs.mkdirSync(root, { recursive: true });
    const walk = (list, base) => {
      for (const node of list || []) {
        const dir = path.join(base, node.name);
        fs.mkdirSync(dir, { recursive: true });
        walk(node.children, dir);
      }
    };
    walk(nodes, root);
    return { ok: true, path: root };
  } catch (err) {
    return { ok: false, error: friendlyFsError(err, root), path: root };
  }
});

ipcMain.handle('fs:suggestName', (_event, payload) => {
  const { target, base } = payload || {};
  if (!target || !base) return base || '';
  let candidate = base;
  let index = 2;
  try {
    while (fs.existsSync(path.join(target, candidate)) && index < 1000) {
      candidate = `${base} ${index}`;
      index += 1;
    }
  } catch {}
  return candidate;
});

ipcMain.handle('fs:renameDir', (_event, payload) => {
  const { dirPath, newName } = payload || {};
  if (!dirPath || !newName) return { ok: false, error: '缺少参数' };
  const parent = path.dirname(dirPath);
  const next = path.join(parent, newName);
  try {
    if (next !== dirPath && fs.existsSync(next)) return { ok: false, error: '同级目录已存在同名文件夹' };
    fs.renameSync(dirPath, next);
    return { ok: true, path: next };
  } catch (err) {
    return { ok: false, error: friendlyFsError(err, dirPath) };
  }
});

ipcMain.handle('fs:reveal', (_event, target) => {
  if (target && fs.existsSync(target)) shell.showItemInFolder(target);
  return true;
});

ipcMain.handle('dialog:exportTemplate', async (_event, payload) => {
  const { name, data } = payload || {};
  const result = await dialog.showSaveDialog(mainWindow, {
    title: '导出模板',
    defaultPath: `${name || '模板'}.json`,
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePath) return { ok: false, canceled: true };
  try {
    fs.writeFileSync(result.filePath, JSON.stringify(data, null, 2), 'utf8');
    return { ok: true, path: result.filePath };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
});

ipcMain.handle('dialog:importTemplate', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: '导入模板',
    properties: ['openFile'],
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePaths.length) return { ok: false, canceled: true };
  try {
    const data = JSON.parse(fs.readFileSync(result.filePaths[0], 'utf8'));
    return { ok: true, data };
  } catch (err) {
    return { ok: false, error: '模板文件无法解析：' + (err.message || err) };
  }
});

ipcMain.handle('app:version', () => app.getVersion());
