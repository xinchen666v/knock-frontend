# knock

端到端加密的点对点聊天工具。本仓库是 **Windows 桌面客户端**（Flutter），
中继服务端在独立的 Go 仓库中维护：<https://github.com/xinchen666v/knock>。

服务器只能看到密文；消息在两端之间加密，历史记录只保存在本机。
客户端当前专注于文本消息，文件传输暂未实现。

## 功能

- v2 协议端到端加密：X25519 + HKDF-SHA256 + XChaCha20-Poly1305
- 基于邀请链接/二维码建立会话，链接内含公钥与校验和
- 安全码（6 位 SAS）核对、身份指纹展示、已核实标记
- 送达/已读状态、对方正在输入提示
- 离线消息由服务器暂存，下次订阅时补投
- 本地 SQLite 聊天记录：明文保存，自动保留最近 30 天
- 联系人列表：别名、本地最后消息预览、验证标记、重命名、删除
- 同机 A/B 调试：不同身份目录互不干扰
- 服务器地址可在界面修改，默认使用云端联调服务器
- Material 3 界面，深/浅色主题，Windows 11 自适应标题栏

## 快速使用

从 `dist/knock-windows-x64.zip` 解压后直接运行 `knock.exe`。
**不要只复制 exe**：`data/`、`flutter_windows.dll`、`sqlite3.dll` 必须一起保留。

首次启动会自动生成本机身份，不需要设置环境变量。欢迎页：

1. “创建一扇门”：生成你的邀请链接/二维码，发给对方；
2. “我有邀请链接”：粘贴对方的链接，建立加密会话；
3. 创建/加入成功后，联系人会出现在欢迎页列表里，点击即可继续；
4. 欢迎页“创建一扇门”下方的“服务器”一行可修改服务器地址。


启动时，在页面设置你自己托管的服务器地址和端口，例如`your-server.example.com:443`。

加入别人的邀请链接时，始终使用链接里携带的服务器地址，不受该设置影响。

## 安全模型

- 邀请链接：`knock://<host>:<port>/v2/<qid>?k=<公钥>&c=<校验和>`
- 密钥协商：双方静态 X25519 + 每条消息的一次性 X25519，HKDF-SHA256 派生方向密钥
- 消息加密：XChaCha20-Poly1305（24 字节 nonce、16 字节 tag），AAD 绑定 `qid|mid`
- 身份指纹：`SHA256(BoxPub)` 前 8 字节，按 4 位分组展示
- 安全码：双方公钥排序后计算 6 位 SAS，用于当面/电话核对
- 服务器只做队列转发；消息被 ACK 后即删除，不保存聊天历史

注意：默认云端地址使用明文 `ws://`，消息内容仍是端到端加密的，但传输层元数据
（连接时间、流量大小等）不加密。正式对外使用建议通过域名 + Caddy/Nginx
反向代理走 `wss://`，并把邀请链接里的端口设为 443（链接中不带端口会按 wss 443 处理）。

本地聊天记录是**明文 SQLite**，保留最近 30 天；能读到本机磁盘的人可以读取记录。
后续可以接入 Windows DPAPI/系统钥匙串做本地加密。

## 开发

要求：Windows 10/11 x64、Flutter 3.47+（Dart 3.10+）。

```powershell
cd frontend
flutter pub get
flutter run -d windows
```

Release 构建：

```powershell
cd frontend
flutter build windows --release
```

构建产物在 `frontend/build/windows/x64/runner/Release/`。

### 测试

```powershell
cd frontend
flutter test
```

测试包含：

- 加密层跨语言向量（与 Go 实现一致）
- 邀请链接解析与校验和
- SQLite 历史/联系人读写、30 天清理、删除级联
- Session 服务器设置、联系人重命名/删除
- 真实 Go 服务端互通：双向消息、已读、输入中、SAS、离线补投、重启恢复历史
- Go CLI ↔ Flutter 客户端跨语言互通

互通测试默认跳过，需要先构建 Go 服务端和 CLI：

```powershell
cd <go-repo>
go build -o <frontend>/.tmp/knock-server.exe ./server
go build -o <frontend>/.tmp/knock-cli.exe ./client

cd <frontend>
$env:KNOCK_SERVER_BIN="<absolute-path>/knock-server.exe"
$env:KNOCK_CLI_BIN="<absolute-path>/knock-cli.exe"
flutter test
```

### 打包

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File .\scripts\package-windows.ps1
```

脚本会：

1. 执行 `flutter build windows --release`（可加 `-SkipBuild` 跳过）；
2. 复制完整 Release 目录；
3. 带上 VC++ 运行库（`msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`）；
4. 附上首次使用说明 `README-FIRST.txt`；
5. 输出 `frontend/dist/knock-windows-x64.zip` 和对应的 `.sha256` 校验文件。

程序未签名，Windows SmartScreen 可能提示“已保护你的电脑”，需要“更多信息 → 仍要运行”。
需要 64 位 Windows 10/11。

## 同机 A/B 调试

两个实例各自指定身份文件即可，服务和状态完全隔离：

```powershell
$env:KNOCK_IDENTITY="D:\knock-debug\A\identity.json"
$env:KNOCK_PROFILE="A"
$env:KNOCK_SERVER="127.0.0.1:7801"
D:\path\to\knock.exe
```

第二个窗口把 `A` 换成 `B`。调试模式下：

- 身份文件旁边会生成 `state-<指纹前8位>.json` 和 `history.db`；
- 窗口内显示“调试 · A/B”徽标；
- `KNOCK_SERVER` 优先于界面设置，去掉后界面地址才生效。

普通使用不需要设置任何环境变量。

注意：Flutter 客户端与 Go CLI 的状态文件字段不同，**不要让两者共用同一个
identity 目录**，否则可能互相覆盖状态。

## 数据存放

| 模式 | 身份 | 状态/历史 |
| --- | --- | --- |
| 普通 | 当前用户 SharedPreferences | 系统应用数据目录下的 `history.db` |
| 调试 | `KNOCK_IDENTITY` 指定文件 | 身份文件同目录下的 `state-<fp8>.json`、`history.db` |

联系人、聊天记录（最近 30 天）都在 `history.db` 中；删除联系人会同时删除该联系人的
本地历史和“已核实”标记。重置身份不会自动删除本地历史与联系人。

## 目录结构

```
frontend/
├── lib/
│   ├── crypto/        X25519 / HKDF / XChaCha20-Poly1305 与测试向量
│   ├── protocol/      信封、邀请链接、协议载荷
│   ├── session/       会话状态机、发送/接收、信号、重连、本地历史接入
│   ├── history/       SQLite 历史与联系人存储
│   ├── contacts/      联系人模型
│   ├── identity/      身份与状态持久化（prefs / 文件）
│   ├── pages/         欢迎页、邀请页、聊天页
│   ├── widgets/       消息气泡、信任弹窗、调试徽标
│   ├── theme/         Material 3 主题与语义色
│   └── platform/      AppEnv、环境变量、路由观察者
├── windows/           Windows runner（标题栏配色、应用图标）
├── scripts/           打包脚本与首次使用说明
└── test/              单元测试与真实服务端互通测试
```

## 当前限制

- 仅文本消息；文件分块传输尚未实现
- 一次只有一个活跃联系人；其他联系人的消息留在服务器队列里，点开时才补投，
  因此联系人列表不显示实时未读
- 本地历史为明文，未做系统级加密
- 不跨设备同步；每个身份/设备各自保存联系人历史
- 默认云端服务器为明文 `ws://`，生产使用请配置 `wss://`
- exe 未签名，分发时可能触发 SmartScreen