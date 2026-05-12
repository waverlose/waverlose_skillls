---
name: image-gen
description: 使用 gpt-image-2 模型生成图片并保存到指定目录。支持自定义提示词、尺寸、参考图等参数。
license: MIT
compatibility: opencode
---

## 功能说明

调用兼容 OpenAI Images API 的 `gpt-image-2` 生成图片，并保存到用户指定目录或默认目录。

适用场景：
- 用户明确要求你生成图片并落盘
- 需要指定尺寸、文件名或保存位置
- 需要返回实际输出文件路径

## 使用方法

当用户请求生成图片时：

1. 确认保存目录。
默认保存到桌面，如果用户指定了路径则优先使用指定路径。

2. 若用户未提供足够信息，先补齐必要参数：
- 图片主题或提示词
- 期望尺寸：`1024x1024`、`1024x1792`、`1792x1024`
- 保存目录或文件名（如用户在意）

3. 使用 `image-gen` skill 生成时，不要在回复里暴露任何 API key，也不要把密钥写入 skill、脚本或工作区文件。

4. 默认按兼容接口处理：
- Base URL 通过环境变量 `OPENAI_BASE_URL` 或参数 `-BaseUrl` 传入
- 无参考图 → `POST /v1/images/generations`（JSON）
- 有参考图（1~5 张）→ `POST /v1/images/edits`（multipart）
- 异步模式 → 路径追加 `:submit` 提交，轮询 `GET /v1/images/tasks/{task_id}` 获取结果
- API key 通过环境变量 `OPENAI_API_KEY` 或参数 `-ApiKey` 传入

5. 优先使用内置脚本：

```powershell
# 纯文本生图（同步）
& "./scripts/generate-image.ps1" `
  -Prompt "a cute corgi puppy" -Size "1024x1024"

# 参考图编辑（异步，避免同步阻塞）
& "./scripts/generate-image.ps1" `
  -Prompt "add metallic texture" `
  -ReferenceImages "C:\path\to\image.jpg" -Async
```

6. 使用前，应确保：
- 输出目录存在
- `OPENAI_API_KEY` 已配置，或在必要时通过 `-ApiKey` 显式传入
- `OPENAI_BASE_URL` 已配置，或传入 `-BaseUrl`
- 有参考图时脚本自动使用 `/v1/images/edits`（multipart）；无参考图时使用 `/v1/images/generations`（JSON）

7. 如果用户要多张图，优先先确认数量；若未指定，默认 `n = 1`。

8. 如果用户使用中文提示词，可直接生成；只有在用户追求更细的风格控制时，再考虑补充英文风格描述，不要擅自改写用户核心语义。

## 参数说明

- `prompt`：图片描述（必填）
- `size`：图片尺寸，可选值：
  - `1024x1024`（默认）
  - `1024x1792`（竖版）
  - `1792x1024`（横版）
- `n`：生成数量（默认 1）
- `output_dir`：保存目录，默认桌面
- `filename`：可选，自定义输出文件名；未指定时使用时间戳命名
- `reference_images`：参考图路径或 URL 数组，用于图编辑/融合（0 ~ 5 张）
- `quality`：质量档位：`auto`（推荐）、`low`、`medium`、`high`
- `async_mode`：是否使用异步提交 + 轮询（避免同步阻塞）
- `base_url`：必填（或通过 `OPENAI_BASE_URL` 环境变量设置）
- `api_key`：可选；优先从 `OPENAI_API_KEY` 读取

## 示例

用户说："帮我生成一张猫的图片"

执行步骤：
1. 确认桌面目录可用
2. 调用 API 生成图片
3. 解码 base64 并保存到桌面
4. 向用户报告保存路径

用户说："生成一张横版科幻城市夜景，保存到 D:\renders"

执行步骤：
1. 校验 `D:\renders` 的父目录存在
2. 使用 `size = 1792x1024`
3. 生成并保存 `.png`
4. 返回实际保存路径

用户说："给这张图加上金属质感"

执行步骤：
1. 确认参考图路径
2. 使用 `-Async` 异步模式（有参考图时推荐）
3. 脚本自动使用 `/v1/images/edits`（multipart）提交
4. 轮询任务状态直到完成
5. 下载生成的图片到桌面
6. 返回保存路径

## 注意事项

- 严禁在 skill 文本、代码示例或回复中硬编码或泄露任何真实密钥。
- 优先通过环境变量读取 API key，例如 `OPENAI_API_KEY`。
- 优先通过环境变量 `OPENAI_BASE_URL` 传入 Base URL。
- 当前环境是 Windows PowerShell，示例命令必须与 PowerShell 兼容。
- 完成后可删除临时 JSON 文件，但不要删除用户输出图片。

## 脚本参数

`generate-image.ps1` 支持以下参数：

- `-Prompt`：必填，图片提示词
- `-Size`：默认 `1024x1024`
- `-Count`：默认 `1`
- `-OutputDir`：默认桌面
- `-FileName`：可选，单图时直接使用；多图时自动追加序号
- `-ReferenceImages`：可选，参考图路径或 URL 数组（最多 5 张）
- `-Model`：默认 `gpt-image-2`
- `-Quality`：质量档位，可选 `auto`、`low`、`medium`、`high`，默认 `auto`
- `-Async`：开关，启用异步提交 + 轮询模式（推荐有参考图时使用）
- `-BaseUrl`：必填（或通过 `OPENAI_BASE_URL` 环境变量设置）
- `-ApiKey`：可选，不推荐；优先使用环境变量
