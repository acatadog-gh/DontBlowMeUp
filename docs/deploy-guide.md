# 《别炸我！》发布与上线指南

> 版本：v1.0（2026-10-29）　配套工程：`DontBlowMeUp-Godot`（Godot 4.7.2）
> 适用场景：改了功能/数值/美术后重新发布；后期正式上线

---

## 一、现在的部署状态（WorkBuddy 托管）

| 项目 | 说明 |
|---|---|
| 线上链接 | https://dont-blow-me-up.app.workbuddy.host/?sharecode=GEDR4ON5C3 |
| 托管位置 | WorkBuddy 云端应用沙箱（平台托管，你电脑关机不影响访问） |
| 站点类型 | 纯静态站点（Godot Web 导出产物 = 一堆静态文件） |
| 导出产物 | `/Users/czh/项目/DontBlowMeUp-Web/`（index.html / index.wasm / index.pck 等 9 个文件） |
| 特殊配置 | **无**。我们用的是"无线程版"Web 构建（`thread_support=false`），普通静态托管即可，不需要 COOP/COEP 响应头 |

**产物体积**：index.pck 13MB（游戏数据+中文字体）+ index.wasm 38MB（引擎，服务器 gzip 后约 10MB）。首次加载需下载约 40-50MB（有缓存，二次进入很快）。

---

## 二、改了功能后重新发布（标准流程）

### 第 1 步：改代码 / 数值 / 美术

正常改 Godot 工程 `/Users/czh/项目/DontBlowMeUp-Godot/` 即可。

### 第 2 步：跑自检（改了玩法逻辑必做）

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/czh/项目/DontBlowMeUp-Godot -s tests/run_tests.gd 2>&1 | grep -c PASS
```

当前基线：**77 个 PASS**。数字变了先看哪条 FAIL。

### 第 3 步：导出 Web 版

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path /Users/czh/项目/DontBlowMeUp-Godot \
  --export-release "Web" ../DontBlowMeUp-Web/index.html
```

导出前确认目标目录存在：`mkdir -p /Users/czh/项目/DontBlowMeUp-Web`。

> 导出读取的是 `export_presets.cfg` 里的 Web 预设，其中 `exclude_filter` 排除了 `tests/ docs/ assets/art/`——如果以后美术正式接入（美术目录被代码引用了），记得把对应目录从排除列表里移出来。

### 第 4 步：重新发布到线上

两条路任选：

**路 A（推荐，喊我）**：对话里说一句"重新发布"，我会调用发布能力把 `/Users/czh/项目/DontBlowMeUp-Web/` 重新上传——**链接不变**，内容被覆盖更新。

**路 B（自己动手）**：编辑器里 File → Export… → 选 Web 预设 → Export Project；然后在 WorkBuddy 对话里发起发布（或用任何静态托管工具上传该目录）。

### 完整命令速查（复制即用）

```bash
# 一条龙：自检 → 导出
cd /Users/czh/项目
/Applications/Godot.app/Contents/MacOS/Godot --headless --path DontBlowMeUp-Godot -s tests/run_tests.gd 2>&1 | grep -c PASS
/Applications/Godot.app/Contents/MacOS/Godot --headless --path DontBlowMeUp-Godot --export-release "Web" ../DontBlowMeUp-Web/index.html
```

> **注意**：Godot 编辑器开着同一工程时，无头导出可能报"工程被占用"，先退出编辑器或等它空闲。

---

## 三、后期正式上线（三条路线对比）

### 路线 1：腾讯云 COS / 阿里云 OSS + CDN（推荐，成本最低）

静态站点的教科书式上线方式，**推荐这个**。

- 成本：存储+流量约 **几元~几十元/月**（个人游戏绰绰有余）
- 步骤：
  1. 开通对象存储桶（腾讯云 COS 选"静态网站"模式）
  2. 把 `DontBlowMeUp-Web/` 整个目录上传到桶里
  3. 开启 CDN 加速，绑定自己的域名（需 ICP 备案；不备案可用海外 CDN 如 Cloudflare Pages——免费）
  4. 微信内分享需注意：域名须备案 + HTTPS，COS+CDN 都能配
- 优点：便宜、稳定、可绑自己域名、可上 HTTPS

### 路线 2：免费托管平台（Cloudflare Pages / GitHub Pages / Vercel）

- 成本：**免费**，绑域名也免费（海外节点，国内访问速度一般）
- 步骤（以 Cloudflare Pages 为例）：把 `DontBlowMeUp-Web/` 目录拖拽上传即可
- 适合：先给朋友试玩、不想花钱；后期再迁国内

### 路线 3：自己的 VPS + Nginx（完全可控）

```nginx
server {
    listen 443 ssl;
    server_name games.example.com;          # 你的域名
    root /var/www/dontblowmeup;             # DontBlowMeUp-Web 目录内容
    gzip on;
    gzip_types application/wasm application/javascript;   # wasm 必须 gzip，体积差 4 倍
    location ~* \.wasm$ { add_header Content-Type application/wasm; }
}
```

- 成本：轻量服务器约 30-100 元/月
- 适合：以后做**联机版**时顺便把前端也放上（联机还需要后端 WebSocket 服务，那是另一套架构）

### 路线选择建议

| 阶段 | 建议 |
|---|---|
| 现在（朋友试玩） | WorkBuddy 托管链接，够用 |
| 想让更多人玩 / 微信里分享 | 路线 1（COS/CDN + 备案域名）或路线 2（先凑合） |
| 做联机版（M2） | 路线 3 + 后端 WebSocket 服务 |

---

## 四、常见问题

**Q：重新导出后线上没变化？**
浏览器缓存。Ctrl/Cmd+Shift+R 强刷；正式上线后建议给 pck/wasm 文件名加版本号（如 `index_v2.pck`）破缓存。

**Q：朋友打开是黑屏/一直加载？**
首次要下载约 40-50MB，弱网需等待；确认对方浏览器不是老旧的 IE/低版微信内置浏览器（需支持 WebAssembly，2018 年后的浏览器都行）。

**Q：能上手机玩吗？**
能，链接手机浏览器直接开。但目前是热座传设备玩法，没有适配触屏拖拽，体验待优化（可加虚拟按钮/触控手势，列入待办）。

**Q：导出报错 "目标文件夹不存在"？**
先 `mkdir -p /Users/czh/项目/DontBlowMeUp-Web`。

**Q：换了电脑怎么导出？**
新机器装 Godot 4.7.2 + 导出模板（版本必须一致 4.7.2.stable），工程目录整体拷过去即可。

---

## 五、发布检查清单（每次发布前过一遍）

- [ ] 逻辑自检 77/77 通过（或明确知晓新增/删除断言后的数字）
- [ ] 主场景无头启动零错误：`Godot --headless --path 工程目录 --quit-after 30 scenes/main.tscn`
- [ ] `export_presets.cfg` 的 exclude_filter 正确（美术接入后记得移出排除项）
- [ ] 导出产物 pck 体积正常（约 13MB 起步，美术接入后会变大）
- [ ] 本地用浏览器打开 `DontBlowMeUp-Web/index.html` 快速过一局（或 python3 -m http.server 起本地服务试）
- [ ] 发布后强刷链接验证新内容生效
