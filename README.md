# WCAIChatAvatars

为微信的 WeClaw 和 AI 助手会话显示双方头像。安装后重启微信即可启用，普通聊天保持原样。

- 左侧显示助手头像，点击进入该会话的微信原生资料设置。
- 右侧显示本人头像，点击进入微信个人信息页。
- 普通文本和流式 Markdown 回复按消息行宽度排版，为头像留出空间。

## 安装

从 [Releases](https://github.com/qiu7c/WCAIChatAvatars/releases) 选择与你的越狱环境对应的 `rootless`（无根）或 `rootful`（有根）安装包。`.deb` 可通过包管理器安装。手动安装时，把 ZIP 里的 `WCAIChatAvatars.dylib` 和 `WCAIChatAvatars.plist` 一起放到加载器的插件目录。

包名为 `com.qiu7c.wcaichatavatars`，目标为 arm64 和 arm64e。微信接口已对照 8.0.79 和 8.0.80 的头文件。

## 构建

[GitHub Actions](https://github.com/qiu7c/WCAIChatAvatars/actions/workflows/build.yml) 支持推送触发和手动运行，构建结果包含 `.deb` 和 dylib ZIP。在本地可用 Theos 打包。

```sh
make clean package FINALPACKAGE=1
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```
