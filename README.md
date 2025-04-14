---
title: SillyTavern Docker & HF部署
emoji: 🥂
colorFrom: pink
colorTo: blue
sdk: docker
pinned: false
app_port: 8000 # SillyTavern 默认端口
# 定义所需的 Hugging Face Secrets
secrets:
  - name: CONFIG_YAML
    description: "你的 config.yaml 文件内容（无注释）"
    required: true # 配置是必需的
  - name: PLUGINS
    description: "要安装的插件Git URL列表（逗号分隔）"
    required: false # 插件是可选的
---

# 最简单的方法：一键部署

如果你不想手动配置，可以直接点击下方按钮，一键将 SillyTavern Docker 部署到你自己的 Hugging Face Space 中（需要先注册 Hugging Face 账号）：

[![部署到 Hugging Face Spaces](https://huggingface.co/datasets/huggingface/badges/resolve/main/deploy-to-spaces-lg.svg)](https://huggingface.co/spaces/malt666/Tavern-Docker)

点击按钮后，系统会帮你复制一份完整的项目配置，你只需要按照提示设置 Secrets（主要是修改 CONFIG_YAML 中的用户名和密码），即可完成部署。这是最适合新手的快捷部署方式。

---

# SillyTavern Docker 与 Hugging Face 部署指南

本指南说明了如何使用提供的 `Dockerfile` 来构建和运行 SillyTavern，以及如何在 Hugging Face Spaces 上进行部署。部署的核心思想是通过环境变量在容器启动时动态配置 SillyTavern 和安装插件。

## 关键文件

*   `Dockerfile`: 用于构建 SillyTavern 运行环境的 Docker 镜像。它会：
    *   基于官方 Node.js Alpine 镜像。
    *   安装必要的系统依赖（如 `git`）。
    *   从 GitHub 克隆 SillyTavern 的 `staging` 分支代码。
    *   设置工作目录和用户权限。
    *   定义容器启动时的 `ENTRYPOINT` 脚本，该脚本负责：
        *   读取 `CONFIG_YAML` 环境变量并写入 `./config.yaml` 文件。
        *   读取 `PLUGINS` 环境变量，并克隆、安装指定的插件。
        *   启动 SillyTavern 服务器 (`node server.js`)。
*   `README.md`: 本说明文件。

## 配置方式：环境变量

我们通过两个主要的环境变量来配置容器：

1.  `CONFIG_YAML`: **必需**。
    *   **作用**: 定义 SillyTavern 的运行配置。
    *   **内容**: 下面是推荐的默认配置内容。你可以直接复制粘贴使用，但**强烈建议你修改其中的认证信息**。
    *   **推荐配置内容**:
        ```yaml
        dataRoot: ./data
        listen: true
        listenAddress:
          ipv4: 0.0.0.0
          ipv6: '[::]'
        protocol:
            ipv4: true
            ipv6: false
        dnsPreferIPv6: false
        autorunHostname: "auto"
        port: 8000
        autorunPortOverride: -1
        ssl:
          enabled: false
          certPath: "./certs/cert.pem"
          keyPath: "./certs/privkey.pem"
        whitelistMode: false
        enableForwardedWhitelist: false
        whitelist:
          - ::1
          - 127.0.0.1
        whitelistDockerHosts: true
        basicAuthMode: true
        basicAuthUser:
          username: "用户名" # 请务必修改为你自己的用户名
          password: "密码" # 请务必修改为你自己的密码
        enableCorsProxy: false
        requestProxy:
          enabled: false
          url: "socks5://username:password@example.com:1080"
          bypass:
            - localhost
            - 127.0.0.1
        enableUserAccounts: false
        enableDiscreetLogin: false
        autheliaAuth: false
        perUserBasicAuth: false
        sessionTimeout: -1
        disableCsrfProtection: false
        securityOverride: false
        logging:
          enableAccessLog: true
          minLogLevel: 0
        rateLimiting:
          preferRealIpHeader: false
        autorun: false
        avoidLocalhost: false
        backups:
          common:
            numberOfBackups: 50
          chat:
            enabled: true
            checkIntegrity: true
            maxTotalBackups: -1
            throttleInterval: 10000
        thumbnails:
          enabled: true
          format: "jpg"
          quality: 95
          dimensions: { 'bg': [160, 90], 'avatar': [96, 144] }
        performance:
          lazyLoadCharacters: false
          memoryCacheCapacity: '100mb'
          useDiskCache: true
        allowKeysExposure: false
        skipContentCheck: false
        whitelistImportDomains:
          - localhost
          - cdn.discordapp.com
          - files.catbox.moe
          - raw.githubusercontent.com
        requestOverrides: []
        extensions:
          enabled: true
          autoUpdate: true
          models:
            autoDownload: true
            classification: Cohee/distilbert-base-uncased-go-emotions-onnx
            captioning: Xenova/vit-gpt2-image-captioning
            embedding: Cohee/jina-embeddings-v2-base-en
            speechToText: Xenova/whisper-small
            textToSpeech: Xenova/speecht5_tts
        enableDownloadableTokenizers: true
        promptPlaceholder: "[Start a new chat]"
        openai:
          randomizeUserId: false
          captionSystemPrompt: ""
        deepl:
          formality: default
        mistral:
          enablePrefix: false
        ollama:
          keepAlive: -1
          batchSize: -1
        claude:
          enableSystemPromptCache: false
          cachingAtDepth: -1
        enableServerPlugins: true
        enableServerPluginsAutoUpdate: false
        ```
    *   **⚠️ 重要警告**: 请务必修改上方配置中 `basicAuthUser` 下的 `username` 和 `password` 为你自己的凭据，以确保安全！**不要使用默认的 "用户名" 和 "密码"！**
    *   **注意**: 必须是有效的 YAML 格式，且**不应包含任何 `#` 开头的注释行**。

2.  `PLUGINS`: **可选**。
    *   **作用**: 指定需要在容器启动时自动安装的 SillyTavern 插件。
    *   **内容**: 一个**逗号分隔**的插件 Git 仓库 URL 列表。
    *   **推荐安装**: 强烈建议安装 `cloud-saves` 插件，以便在不同部署环境（如本地和 Hugging Face）之间同步数据。
        *   **插件地址**: `https://github.com/fuwei99/cloud-saves.git`
        *   **重要前置条件**: 为了让容器/Hugging Face Space 能够拉取你的存档，你**必须**先在你本地的 SillyTavern 中安装好 `cloud-saves` 插件，并**至少进行一次数据存档操作**。这样，远程部署的环境才能通过该插件下载你的存档。
    *   **格式示例**: `https://github.com/fuwei99/cloud-saves.git` (注意包含推荐的 cloud-saves 插件)
    *   **注意**: URL 之间**只能用英文逗号 `,` 分隔**，且逗号前后**不能有空格**。如果留空或不提供此变量，则不会安装额外插件。

## 方法一：本地 Docker 部署

你可以在本地使用 Docker 来构建和运行 SillyTavern。

1.  **构建镜像**: 在包含 `Dockerfile` 的目录下，运行：
    ```bash
    docker build -t sillytavern-local .
    ```
    将 `sillytavern-local` 替换为你想要的镜像名称。

2.  **准备配置**: 将你的 `config.yaml` 内容（无注释）准备好。

3.  **运行容器**: 使用 `docker run` 命令，并通过 `-e` 参数传递环境变量。
    *   将上方提供的**推荐配置内容**复制，并作为 `CONFIG_YAML` 环境变量的值。**确保你已经修改了其中的用户名和密码！**
    *   如果你需要安装插件（**推荐安装 `cloud-saves`**），请准备好插件 URL 列表。

    ```bash
    # 示例：使用推荐配置并安装 cloud-saves 插件
    # 1. 将推荐配置（修改密码后）保存到名为 config_no_comments.yaml 的文件中
    # 2. 运行以下命令

    docker run -p 8000:8000 --name my-sillytavern \\
      -e CONFIG_YAML="$(cat config_no_comments.yaml)" \\
      -e PLUGINS='https://github.com/fuwei99/cloud-saves.git' \\
      sillytavern-local

    # 如果你需要安装更多插件，用逗号隔开添加到 PLUGINS 变量中
    # 例如：
    # docker run -p 8000:8000 --name my-sillytavern \
    #   -e CONFIG_YAML="$(cat config_no_comments.yaml)" \
    #   -e PLUGINS='https://github.com/fuwei99/cloud-saves.git,https://github.com/user/other-plugin.git' \
    #   sillytavern-local
    ```
    *   `-p 8000:8000`: 将容器的 8000 端口映射到宿主机的 8000 端口。
    *   `--name my-sillytavern`: 为容器命名，方便管理。
    *   `-e CONFIG_YAML="$(cat config_no_comments.yaml)"`: 从文件读取配置内容并传递。这是处理多行 YAML 最可靠的方式。**再次确认：运行前务必修改 `config_no_comments.yaml` 文件中的用户名和密码！**
    *   `-e PLUGINS='...'`: 传递插件列表，这里以安装 `cloud-saves` 为例。

4.  **访问**: 打开浏览器访问 `http://localhost:8000`。

## 方法二：Hugging Face Spaces 部署

这是推荐的在线部署方式，利用 Hugging Face 的免费计算资源和 Secrets 管理功能。

1.  **创建 Space**: 在 Hugging Face 上创建一个新的 Space，选择 **Docker** SDK。

2.  **上传文件**: 将本项目中的 `Dockerfile` 和 `README.md` 文件上传到你的 Space 仓库根目录。

3.  **配置 Secrets**: 进入你的 Space 页面的 **Settings -> Secrets** 部分。
    *   **添加 `CONFIG_YAML` Secret**:
        *   点击 "New secret"。
        *   名称 (Name) 输入: `CONFIG_YAML`
        *   值 (Value) 粘贴: **复制上方提供的推荐配置内容**。**再次强调：粘贴前请务必修改 `basicAuthUser` 下的 `username` 和 `password` 为你自己的安全凭据！**
        *   点击 "Add secret"。
    *   **(推荐) 添加 `PLUGINS` Secret**:
        *   再次点击 "New secret"。
        *   名称 (Name) 输入: `PLUGINS`
        *   值 (Value) 粘贴: 推荐至少包含 `cloud-saves` 插件。例如：`https://github.com/fuwei99/cloud-saves.git`。如果你需要其他插件，用逗号隔开添加，例如：`https://github.com/fuwei99/cloud-saves.git,https://github.com/user/other-plugin.git`。
        *   **重要提醒**: 请确保你已经在本地 SillyTavern 安装了 `cloud-saves` 并至少进行了一次存档。
        *   点击 "Add secret"。如果你确实不需要任何额外插件，可以跳过这一步。

4.  **构建与启动**: Hugging Face 会自动检测到 `Dockerfile` 和 Secrets，并开始构建镜像、启动容器。你可以在 Space 的 **Logs** 标签页查看构建和启动过程。

5.  **访问**: 构建成功并启动后，通过 Space 提供的公共 URL 访问 SillyTavern 界面。

## 插件访问

如果通过 `PLUGINS` 环境变量安装了插件，你需要根据各个插件的说明文档找到访问其界面的路径。

*   对于推荐安装的 `cloud-saves` 插件，其管理界面通常位于:
    `http://<你的SillyTavern访问地址>/api/plugins/cloud-saves/ui`
    例如，如果是本地部署，则为 `http://127.0.0.1:8000/api/plugins/cloud-saves/ui`。如果是 Hugging Face Space，则将 `<你的SillyTavern访问地址>` 替换为你的 Space 公共 URL。

其他插件的访问路径请参考其各自的文档。
