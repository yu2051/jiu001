---
title: SillyTavern Docker & HF部署
emoji: 🐳
colorFrom: cyan
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
    *   **内容**: 你需要将你的 `config.yaml` 文件的**完整内容**（确保**已删除所有注释** `#` 开头的内容）作为这个环境变量的值传入。
    *   **注意**: 必须是有效的 YAML 格式。

2.  `PLUGINS`: **可选**。
    *   **作用**: 指定需要在容器启动时自动安装的 SillyTavern 插件。
    *   **内容**: 一个**逗号分隔**的插件 Git 仓库 URL 列表。
    *   **格式示例**: `https://github.com/user/plugin1.git,https://github.com/user/plugin2.git`
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
    ```bash
    # 示例：只传递必要的 CONFIG_YAML
    docker run -p 8000:8000 --name my-sillytavern \
      -e CONFIG_YAML='dataRoot: ./data
    listen: true
    # ... (粘贴你完整的、无注释的 config.yaml 内容) ...
    enableServerPluginsAutoUpdate: false' \
      sillytavern-local
    
    # 示例：同时传递 CONFIG_YAML 和 PLUGINS
    docker run -p 8000:8000 --name my-sillytavern \
      -e CONFIG_YAML='dataRoot: ./data
    listen: true
    # ... (粘贴你完整的、无注释的 config.yaml 内容) ...
    enableServerPluginsAutoUpdate: false' \
      -e PLUGINS='https://github.com/fuwei99/plugin-manager.git,https://github.com/fuwei99/cloud-saves.git,https://github.com/fuwei99/data-sync.git' \
      sillytavern-local
    ```
    *   `-p 8000:8000`: 将容器的 8000 端口映射到宿主机的 8000 端口。
    *   `--name my-sillytavern`: 为容器命名，方便管理。
    *   `-e CONFIG_YAML='...'`: 传递配置内容。**注意**：在命令行中传递多行 YAML 可能需要根据你的 Shell 环境进行特殊处理（如使用单引号包裹，并可能需要转义 YAML 内的特殊字符）。最简单的方法可能是将配置保存到一个文件，然后用 `-e CONFIG_YAML=$(cat path/to/your/config.yaml)` 的方式传递。
    *   `-e PLUGINS='...'`: 传递插件列表。

4.  **访问**: 打开浏览器访问 `http://localhost:8000`。

## 方法二：Hugging Face Spaces 部署

这是推荐的在线部署方式，利用 Hugging Face 的免费计算资源和 Secrets 管理功能。

1.  **创建 Space**: 在 Hugging Face 上创建一个新的 Space，选择 **Docker** SDK。

2.  **上传文件**: 将本项目中的 `Dockerfile` 和 `README.md` 文件上传到你的 Space 仓库根目录。

3.  **配置 Secrets**: 进入你的 Space 页面的 **Settings -> Secrets** 部分。
    *   **添加 `CONFIG_YAML` Secret**:
        *   点击 "New secret"。
        *   名称 (Name) 输入: `CONFIG_YAML`
        *   值 (Value) 粘贴: 你准备好的**完整、无注释**的 `config.yaml` 内容。
        *   点击 "Add secret"。
    *   **(可选) 添加 `PLUGINS` Secret**:
        *   再次点击 "New secret"。
        *   名称 (Name) 输入: `PLUGINS`
        *   值 (Value) 粘贴: 你的插件 Git URL 列表，**逗号分隔，无空格**。例如：`https://github.com/fuwei99/plugin-manager.git,https://github.com/fuwei99/cloud-saves.git,https://github.com/fuwei99/data-sync.git`。
        *   点击 "Add secret"。如果你不需要安装额外插件，可以跳过这一步。

4.  **构建与启动**: Hugging Face 会自动检测到 `Dockerfile` 和 Secrets，并开始构建镜像、启动容器。你可以在 Space 的 **Logs** 标签页查看构建和启动过程。

5.  **访问**: 构建成功并启动后，通过 Space 提供的公共 URL 访问 SillyTavern 界面。

## 插件访问

如果通过 `PLUGINS` 环境变量安装了插件，你需要根据各个插件的说明文档找到访问其界面的路径，通常是相对于你的 SillyTavern URL 的 `/api/plugins/插件名称/ui` 或类似路径。
