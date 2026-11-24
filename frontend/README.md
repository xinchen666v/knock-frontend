# knock frontend

knock 的 Windows 桌面客户端（Flutter）。项目总览、安全模型、协议细节、
测试与分发说明见[根目录 README](../README.md)。

## 常用命令

```powershell
flutter pub get
flutter run -d windows
flutter test
flutter build windows --release
powershell -ExecutionPolicy Bypass -File .\scripts\package-windows.ps1
```

普通使用不需要环境变量；同机 A/B 调试与服务器地址配置见根目录 README。