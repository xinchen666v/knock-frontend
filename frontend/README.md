# knock

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

客户端聊天记录仅存于内存（Session 单例），App 重启后消失；服务器仅补投未签收消息。本地历史持久化（如 SQLite/Drift）列为后续议题——注意若做，须与 M3 的 E2E 加密一并设计（密文存储 vs 明文存储是安全决策，不是存储选型）。