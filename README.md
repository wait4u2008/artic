# Artic — 私人加密保险箱（Android）

一个"隐形"的文件保险箱 App。把电脑上的 txt / md / 图片 / 视频文件导入手机后，**文件会被加密藏起来**：
在任何文件管理器、电脑 USB 连接、甚至其他 App 里都找不到原文，只能在 Artic 里看。

- 界面全英文，App 名 **Artic**（图标为太极图）
- 打开 App 是极简门禁界面：一张写着 "There is nothing！" 的空卡片（无图标、无提示）→ **长按 3 秒** → 弹密码框
- 密码已写死在程序里（`art`），必须手动输入
- **1 分钟免密**：切到后台后 1 分钟内回来，自动解锁并**直接回到刚才的界面**（文章/文件夹/首页），不用长按输密码；超过 1 分钟则需重新登录
- **记住阅读位置**：文章读到哪，下次打开接着读（滚动位置自动保存）
- 支持文件夹管理：新建 / 重命名 / 移动 / 删除，可无限层级
- **三空间分类**：顶部 **Text / Images / Videos** 三个 tab，文本、图片、视频分开存放（根目录和子文件夹都有）
- **支持图片**（jpg/png/gif/webp/bmp）：点击查看，米黄底色、可双指缩放
- **支持视频**（mp4/mkv/avi/mov/webm/3gp）：内置播放器（media_kit/libmpv 内核，支持几乎所有编码格式，含软解兜底），**播放完临时解密副本立即自动删除**
- **大文件导入不卡不闪退**：文件选择在后台线程处理，加密在后台隔离线程执行，导入几百 MB 的视频也不会卡死 App
- **多选管理**：列表右上角 ☑ 进入选择模式 → 勾选多个文件/文件夹 → 批量移动 / 批量删除
- **子目录内直接导入**：进入任意子文件夹后，点 + 或右上角上传图标，即可把文件导入当前目录
- 阅读界面是**米黄纸张色 + 深墨文字**的护眼配色（不再是黑底白字），md 渲染排版、txt 纯文本
- 防截图：App 内无法截屏，最近任务列表里也看不到内容
- 切到后台自动上锁，回来要重新长按 3 秒

## 怎么用

1. 把 `Artic.apk` 传到手机（微信/QQ 发送给自己，或数据线拷贝），点击安装。若你拿到的是源码仓库（不包含 APK），先按下方「重新构建」用 `build.bat` 生成 `Artic.apk`
2. 打开 App → 长按 "Files" 卡片 3 秒（按住时卡片变暗）→ 松手进入文件列表
3. 首次使用会自动建库（无需设置密码）
4. 导入：点右下角 **+** → "Import files"（或顶栏上传图标）→ 选 txt/md/图片/视频文件（可多选）→ 自动加密存入当前 tab 对应的空间
5. 分类：建文件夹，长按文件 → "Move to…" 移动到其他文件夹
6. 批量管理：顶栏 ☑ → 勾选 → 底部 "Move" / "Delete"
7. 阅读：点文件 → 米黄护眼阅读页，md 有排版，txt 可长按选择复制；图片可双指缩放；视频用内置播放器（播完自动清除临时副本）

## 为什么文件"找不到"？

用生活类比：你的文件像**进了保险箱**，而不是放在桌上。

| 你的担心 | 实际做法 |
|:--|:--|
| 文件会不会以 txt/md 原样存在手机里？ | 不会。内容用 **AES-256 加密**（银行同级别）后变成乱码，文件名也是随机数字 |
| 用文件管理器能看到吗？ | 看不到。存在 App 私有沙盒目录，系统禁止其他应用和文件管理器访问 |
| 连电脑 USB 能看到吗？ | 看不到。Android 10+ 连电脑只能看到共享目录 |
| 别人打开 App 能看到吗？ | 看不到。必须长按 3 秒才能进，且没有文字提示 |
| 截图/录屏偷看呢？ | App 内禁止截图（FLAG_SECURE），最近任务预览也是黑的 |
| 视频会泄露吗？ | 播放时临时解密到 App 私有缓存目录（其他应用/文件管理器/USB 均不可见），**退出播放即自动删除**，磁盘上不留明文 |
| 换手机备份数据？ | 禁用了系统备份，加密文件不会跟着云备份走 |

**原理**：密码 → Argon2id（防暴力破解）派生密钥 → 每个文件 AES-256 加密。文本用 AES-256-GCM 一次性加密；图片/视频等大文件用 **AES-256-CTR + HMAC-SHA256 流式加密**（分块处理，不整文件载入内存）。密钥只在内存里，切后台即丢弃。磁盘上永远只有加密乱码。

> 唯一例外：手机被 ROOT 过的"极客"设备理论上可暴力读取内存。普通人（包括系统文件管理器）拿不到。

## 给开发者：项目结构

```
artic/
├── build.bat              # 双击一键重新构建 APK（输出 Artic.apk）
├── lib/
│   ├── main.dart          # 入口（全局深色主题）
│   └── src/
│       ├── crypto/vault_crypto.dart    # Argon2id 密钥派生 + AES-256-GCM 加解密 + AES-256-CTR 流式加解密
│       ├── storage/vault_store.dart    # 加密清单/文件读写、后台隔离线程流式导入、临时视频解密、目录树操作、密码常量 kPassword
│       ├── models/vault_models.dart    # FolderEntry / FileEntry（含类型判断）/ VaultManifest
│       ├── screens/
│       │   ├── login_screen.dart       # 门禁：长按3秒（Whisper 风格，无提示无密码框）
│       │   ├── home_screen.dart        # 根目录 + Text/Images/Videos 三 tab + 多选模式
│       │   ├── folder_screen.dart      # 子目录视图 + 三 tab + 当前目录导入 + 多选模式
│       │   ├── reader_screen.dart      # 护眼阅读器（米黄纸色，md 渲染 / txt 纯文本；图片/视频路由到专属页）
│       │   ├── image_viewer_screen.dart # 图片查看（内存解密，双指缩放）
│       │   └── video_player_screen.dart # 视频播放（media_kit 内核，临时解密，退出即删）
│       ├── utils/
│       │   ├── auto_lock.dart          # 切后台自动上锁
│       │   ├── import_helper.dart      # file_picker 系统文件选择器导入（后台复制，不卡主线程）
│       │   └── file_actions.dart       # 长按菜单 + 批量移动/删除 + 目录选择器
│       └── widgets/                    # 文件/文件夹卡片（支持选择态）、底部批量操作栏
└── android/
    └── app/src/main/
        ├── AndroidManifest.xml         # 应用名 Artic、禁止备份
        ├── res/mipmap-*/ic_launcher.png  # 自绘图标（书+锁，深蓝渐变）
        └── kotlin/com/nv/notes/MainActivity.kt  # FLAG_SECURE 防截图
```

### 磁盘上的加密布局（app 私有目录 /vault/）

| 文件 | 内容 |
|:--|:--|
| `vault.salt` | 随机盐（16 字节） |
| `vault.key` | 随机主密钥（32 字节），用"密码派生密钥"加密包裹 |
| `manifest.enc` | 目录结构清单（文件夹/文件名 + 每个文件的加密方式 cipher），用主密钥加密 |
| `files/<随机>.enc` | 每个文件内容，用主密钥加密（cipher='gcm' 文本 / 'ctr' 大媒体） |

文件名全是随机数，没有任何一处明文。文本用 AES-256-GCM 一次性加密；图片/视频等大文件用 AES-256-CTR + HMAC-SHA256 流式加密（分块处理，不整文件载入内存，也不阻塞 UI）。

## 关键实现与问题解决（开发者视角）

### 1. 大文件流式加密：AES-CTR + HMAC-SHA256

文本文件小，用 AES-256-GCM 一次性加密即可；但几百 MB 的视频若也整块加密，会**内存溢出**。因此媒体文件改用 **AES-256-CTR + HMAC-SHA256 流式加密**（`cryptography` 包的纯 Dart 实现，16KB 分块、每 4MB 让出事件循环）。

两种 blob 格式按 `FileEntry.cipher` 字段区分（旧数据默认 'gcm'，null 安全）：

| cipher | 算法 | 布局 | 用途 |
|:--|:--|:--|:--|
| `gcm` | AES-256-GCM 一次性 | nonce(12) ‖ ciphertext ‖ mac(16) | 文本（原格式） |
| `ctr` | AES-256-CTR + HMAC-SHA256 流式 | nonce(16) ‖ ciphertext ‖ mac(32) | 图片/视频大文件 |

**踩过的坑**：`Cipher.encryptStream` 的 `onMac` 回调在 `addStream` 期间触发，此时向同一个 IOSink `add` 会抛 "StreamSink is bound to a stream"——需先捕获 MAC，`addStream` 结束后再写。

### 2. 致命 bug：解密误删加密源文件

曾有一版 `decryptStream` 在 finally 里删除了 `input`——而 `input` 是 **vault 里的加密源 blob**（`files/<随机>.enc`）。后果：**每次打开图片/视频就删掉源文件**，manifest 仍引用不存在的 blob，导致"已导入的媒体全部打不开"。

修复原则：**解密函数绝不删除输入**；加密源必须保留，只删除调用方创建的临时明文（图片的 `tmp_`、视频播放器的缓存副本）。测试断言同步改为"解密后输入必须存在"。

### 3. 大视频导入闪退：两层修复

**第一层（Dart 层）**：流式加密在主 isolate 跑会阻塞 UI → ANR。修复：`importFileStream` 用 `Isolate.run` 把"读源文件 + 加密 + 写 blob"放**后台 isolate**，主 isolate 只更新 manifest。

**第二层（原生层，真正的元凶）**：`file_selector` 在 Android 上把选中文件**同步复制到 cacheDir**（主线程），大视频复制几秒触发 ANR，Dart 层 isolate 拦不住。**换用 `file_picker`**：其 Android 端复制在 `Dispatchers.IO` 后台协程，不阻塞主线程。

最终导入链路：picker（后台协程复制）→ isolate（后台加密）→ 主线程（更新清单）。

### 4. 视频播放：ExoPlayer 硬解崩溃 → media_kit

`video_player`（ExoPlayer）在某台设备上播放 H.264 High Profile 1080p 报 `MediaCodecVideoRenderer error`（`format_supported=Yes` 但运行时解码失败）——设备硬件解码器崩溃，ExoPlayer 不暴露解码器配置，无法修复。

**换用 `media_kit`**（libmpv + FFmpeg 内核）：自带完整解码器 + **软解兜底**，这类视频走 FFmpeg 软解正常播放，且支持 HEVC/AV1/mkv/avi 等几乎所有格式。代价：APK 从 54MB 增到约 90MB（libmpv 解码器，含 4 个 ABI）。

### 5. 三空间 Tab 分类

根目录与子文件夹均为 Text / Images / Videos 三个 tab（`TabController` + `_tabFiles()` 按当前 tab 过滤）。文件夹在所有 tab 显示；多选"全选"只选当前 tab 的文件；导入的文件按类型落入对应空间（按扩展名判断，与 FileEntry.isImage/isVideo 一致）。

## 重新构建

双击项目根目录的 `build.bat`（已配置好 JDK/Android SDK 路径），完成后 APK 出现在项目根目录 `Artic.apk`。

依赖：`cryptography`（Argon2id+AES-GCM+AES-CTR 流式）、`path_provider`（私有目录）、`file_picker`（系统文件选择器导入，后台复制不卡主线程）、`flutter_markdown`（md 渲染）、`media_kit` + `media_kit_video` + `media_kit_libs_android_video`（libmpv/FFmpeg 视频播放，APK 约 90MB）。
