# 视频播放器官网 — 部署与内容管理指南

仿「浮宇宙 / FloGravity」星空深色风格的产品官网，基于 WordPress 主题实现，SEO 友好（爬虫可读）。

## 目录结构

```
website/
├── preview.html                  # 设计预览页（无需 WordPress，浏览器直接打开看效果）
├── videoplayer-theme-1.0.0.zip   # 主题安装包（WordPress 后台上传用）
├── wp-theme/
│   └── videoplayer/              # 主题源码
│       ├── style.css             # 主题样式（含主题头信息）
│       ├── functions.php         # 初始化、菜单、SEO（meta/OG/Twitter/JSON-LD）、FAQ 数据
│       ├── header.php / footer.php
│       ├── front-page.php        # 首页（hero/六特性/下载/更新日志/FAQ）
│       ├── index.php / single.php / page.php / 404.php
│       ├── template-parts/       # 六个特性的视觉 mock 组件
│       └── assets/
│           ├── img/              # 图标、hero 截图、OG 分享图
│           └── js/site.js        # 星空粒子、顶栏滚动态、滚动渐显、导航高亮
└── README-部署指南.md            # 本文件
```

## 一、环境要求

- WordPress 6.0+（PHP 7.4+ / 8.x，MySQL 5.7+ 或 MariaDB）
- 服务器或虚拟主机均可（宝塔 / LNMP / Docker 皆可）

## 二、安装步骤

1. WordPress 后台 → **外观 → 主题 → 安装主题 → 上传主题**，上传 `videoplayer-theme-1.0.0.zip` → 启用。
   （或者把 `wp-theme/videoplayer/` 整个目录上传到服务器 `wp-content/themes/` 下再启用。）
2. 启用后首页即生效（`front-page.php` 自动接管站点根路径，无需设置静态页面）。
3. **设置 → 固定链接** → 选择「文章名」并保存（伪静态，对爬虫友好；Nginx 需配置 WP 重写规则，宝塔一键即可）。
4. **设置 → 常规**：站点标题填「视频播放器」，副标题填一句产品描述。

## 三、内容管理（WordPress 后台）

### 1. 首页文案 / 下载链接（重要）

外观 → **自定义** → 「首页内容」分组，可修改：

| 字段 | 用途 |
|------|------|
| Hero 眉题 / 主标题 / 渐变词 / 注释 / 描述 | 首屏文案 |
| 下载链接 | 发新版后改成最新 DMG 地址（GitHub Releases 的 `latest/download/` 地址会自动跟随最新版，通常不用改） |
| GitHub 仓库链接 | 页脚与顶栏按钮 |
| 当前版本号 | 全站显示的版本徽标 |
| 页脚版权文字 | 支持 `{year}` 占位符 |

### 2. 顶部导航菜单

外观 → **菜单** → 创建菜单（勾选「顶部导航」位置）：

- 自定义链接：`/#features` → 功能、`/#download` → 下载、`/#changelog` → 更新日志、`/#faq` → 常见问题
- 分类：选「更新日志」分类 → 归档页
- 未配置菜单时主题会显示默认锚点导航

### 3. 更新日志（首页自动展示最近 3 条）

- 文章 → 写文章 → 分类选择「更新日志」（主题首次加载会自动创建该分类）
- 标题建议写版本号（如 `1.0.6 发布`），正文写本次更新内容
- 首页「更新日志」区块与文章归档页自动同步

### 4. 隐私说明页

页面 → 新建「隐私说明」，按需编辑内容，页脚「隐私说明」链接自动指向 `/privacy`（固定链接为「文章名」时）。

### 5. 站标（可选）

外观 → 自定义 → 站点身份 → 上传 Logo（建议 256×256 圆角方形）。

## 四、SEO（爬虫友好）说明

主题已内置，无需额外插件即可满足：

1. **语义化 HTML5**：`header/nav/main/section/article/footer`、单一 `h1`、层级清晰的 h2/h3；
2. **Meta**：每页自动输出 `description`（首页取 Hero 描述，文章取摘要）；
3. **Open Graph + Twitter Card**：分享到微信/QQ/Twitter 等有卡片预览（首页用内置分享图，文章用特色图片）；
4. **结构化数据 JSON-LD**：
   - 首页：`SoftwareApplication`（软件名、版本、下载地址、免费 Offer、操作系统）
   - 首页：`FAQPage`（FAQ 问答 → Google 富摘要资格）
   - 文章页：`BreadcrumbList` 面包屑
5. **Sitemap**：WordPress 5.5+ 自带 `wp-sitemap.xml`，无需配置；
6. **Canonical**：WordPress 核心自动输出；
7. **性能**：无 jQuery 依赖，单个 CSS + 单个原生 JS（星空画布、滚动动效），无外链字体。

上线后建议：

- 提交 `https://你的域名/wp-sitemap.xml` 到 Google Search Console 与 Bing Webmaster；
- 若想加装 SEO 插件（如 Rank Math / Yoast），主题自带的 meta 与其功能重叠，可在插件里关闭重复项即可，不装也完全可用。

## 五、发布新版本时官网要改什么

1. 外观 → 自定义 → 「当前版本号」改为新版本；
2. 首页 FAQ、下载区块文案如有变化可在 `front-page.php` 或 FAQ（`functions.php` 的 `vp_faq_items()`）中调整；
3. 若 DMG 文件名变化（`latest/download/` 链接失效的情况），更新「下载链接」字段；
4. 发布一篇「更新日志」分类的文章。

## 六、本地预览

直接双击打开 `preview.html`（或在终端 `open preview.html`）即可无 WordPress 预览整体设计；改样式请同步 `wp-theme/videoplayer/style.css`（预览页引用同一份样式）。
