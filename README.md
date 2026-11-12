# WCAIChatAvatars

为微信的 WeClaw 和 AI 助手会话显示双方头像。安装后重启微信即可启用，普通聊天保持原样。

- 左侧显示助手头像，点击进入该会话的微信原生资料设置。
- 右侧显示本人头像，点击进入本人资料主页。
- 普通文本和流式 Markdown 回复按消息行宽度排版，为头像留出空间。

## 安装

从 [Releases](https://github.com/qiu7c/WCAIChatAvatars/releases) 选择与你的越狱环境对应的 `.deb`，用包管理器安装。

| 越狱环境 | 安装包后缀 |
| --- | --- |
| 有根（Rootful） | `iphoneos-arm.deb` |
| 普通无根（Rootless） | `iphoneos-arm64.deb` |
| RootHide | `iphoneos-arm64e.deb` |

有根和普通无根环境也可手动安装，把对应 ZIP 里的 `WCAIChatAvatars.dylib` 和 `WCAIChatAvatars.plist` 一起放到加载器的插件目录。RootHide 使用对应的 `.deb` 安装。

包名为 `com.qiu7c.wcaichatavatars`。每种包的 dylib 都以 arm64 和 arm64e 为编译目标。微信接口已对照 8.0.79 和 8.0.80 的头文件。

注入范围为 `com.tencent.xin` 和 `com.tencent.qy.xin`。

## 构建

[GitHub Actions](https://github.com/qiu7c/WCAIChatAvatars/actions/workflows/build.yml) 支持推送触发和手动运行，三个环境分别生成 `.deb` 和 dylib ZIP。有根和普通无根使用 Theos 打包。

```sh
make clean package FINALPACKAGE=1
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

RootHide 使用 [RootHide Theos](https://github.com/roothide/theos) 打包。

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```
