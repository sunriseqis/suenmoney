# hw/ —— HarmonyOS NEXT (鸿蒙纯血) 原生客户端工程

本目录是 **SuenMoney 鸿蒙 NEXT 客户端原生工程**（基于 HarmonyOS NEXT / OpenHarmony API 11/12+ Stage 模型，ArkTS / ArkUI 体系构建）。

## 这里放什么

DevEco Studio 维护的鸿蒙原生工程。构建与运行流水线：

```
web/（Vue 源码） → vite build → web/dist/ → npm run hw:sync → hw/.../rawfile/ → DevEco Studio / Hvigor → HAP
```

## 工程结构与关键文件

```
hw/
├── build-profile.json5         # 工程级构建配置（API 11/12 Stage 模型）
├── hvigorfile.ts               # Hvigor 构建系统入口
├── oh-package.json5            # 工程级依赖清单
├── README.md                   # 本说明文件
└── entry/                      # 主入口模块 (HAP)
    ├── build-profile.json5     # 模块构建配置
    ├── hvigorfile.ts           # 模块构建脚本
    ├── oh-package.json5        # 模块依赖清单
    └── src/main/
        ├── module.json5        # 模块配置（声明 EntryAbility、网络权限 INTERNET、沉浸式窗口）
        ├── resources/          # 鸿蒙资源目录
        │   ├── base/element/   # 字符常量 string.json、启动色 color.json
        │   ├── base/media/     # 高清应用母版图标 app_icon.png
        │   ├── base/profile/   # 页面路由清单 main_pages.json
        │   └── rawfile/        # Web 编译产物存放目录（通过 npm run hw:sync 同步，已被 .gitignore 忽略）
        └── ets/                # ArkTS 源码
            ├── entryability/
            │   └── EntryAbility.ets  # 应用生命周期、沉浸式全屏布局、状态栏样式、安全区高度计算
            └── pages/
                └── Index.ets         # 主页面：ArkWeb 组件、IndexedDB 数据库支持、JSBridge 桥接、系统返回手势拦截
```

## 核心设计与约束

1. **零业务代码侵入（§架构解耦纪律）**：
   - 所有的记账、报表、流水、同步计算与 UI 界面 100% 来源于 `web/`；
   - `hw/` 仅作为原生宿主容器，负责鸿蒙系统特有的窗口生命周期、安全区注入、返回手势拦截与网络通信权限。
2. **沉浸式与安全区适配**：
   - `EntryAbility.ets` 监听系统状态栏避让区与底部手势导航条避让区高度；
   - `Index.ets` 在页面加载完毕后动态注入 CSS 变量 `--safe-top` 和 `--safe-bottom`，无缝贴合鸿蒙手机/折叠屏/平板设备；
   - Web 容器启用了 `databaseAccess(true)`，完美保障离线优先（IndexedDB）记账引擎无损运行。
3. **原生 JSBridge 交互**：
   - 向前端注入 `window.SuenHarmony` 原生对象，支持动态读取原生实际版本号与构建号，以及外部浏览器安全唤起。

## 本地开发与构建指南

### 1. 同步 Web 最新构建产物
在仓库根目录下执行：
```bash
npm run hw:sync
```
该命令会自动编译前端（`web/dist`）并将静态文件同步至 `hw/entry/src/main/resources/rawfile/`。

### 2. 使用 DevEco Studio 运行或打包
1. 打开 **DevEco Studio**（推荐 4.1 Release / 5.0 Release 或更高版本，兼容 HarmonyOS NEXT）；
2. 菜单选择 **File → Open...**，选择本项目下的 `hw` 目录导入；
3. 连接 HarmonyOS NEXT 真机或启动模拟器，点击 **Run 'entry'** (Shift + F10) 即可运行；
4. 构建正式产物：菜单选择 **Build → Build Hap(s)/APP(s) → Build Hap(s)** 即可产出安装包。
