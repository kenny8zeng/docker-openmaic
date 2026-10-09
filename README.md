# docker-openmaic

把开源项目 [OpenMAIC](https://github.com/THU-MAIC/OpenMAIC)（THU-MAIC，MIT）构建成容器镜像的
**发布仓库**。

这个仓库**不包含任何 OpenMAIC 源码**，也**不维护自己的 Dockerfile**：构建时按 `OPENMAIC_REF`
里固定的上游 ref 拉取源码树，直接用上游自带的 `Dockerfile` 构建、打标签、推送到 GHCR 和
Docker Hub。上游把构建方式改对了，这里不需要跟着改。

> **非官方镜像。** 由本仓库自动构建，与 THU-MAIC 无关，不提供任何支持承诺。镜像里的代码
> 版权归上游所有（MIT），请以 [上游仓库](https://github.com/THU-MAIC/OpenMAIC) 为准。

## 镜像

| Registry | 镜像 |
| --- | --- |
| GHCR | `ghcr.io/kenny8zeng/openmaic` |
| Docker Hub | `<dockerhub-user>/openmaic` |

GHCR 的 owner 取自 `github.repository_owner`，fork 后自动变成你的账号；Docker Hub 的
`<dockerhub-user>` 由仓库变量 `DOCKERHUB_USERNAME` 决定（见[仓库配置](#仓库配置)）。

### 标签策略

| 标签 | 含义 |
| --- | --- |
| `v1.1.3` | 上游 ref 规范化后的值，与上游 release 一一对应 |
| `sha-8c3a90d` | 上游 commit 前 7 位，构建的确切来源 |
| `latest` | 跟随 `OPENMAIC_REF` |
| `main` | 本仓库默认分支的构建 |

后两个是浮动标签，**只在构建的是 `OPENMAIC_REF` 时**才会更新：手动 dispatch 一个 ref 覆盖
属于一次性构建，不会移动它们。

镜像附带 OCI 标签（`title` / `description` / `source` / `version` / `revision`），
`version` 是上游 `package.json` 的版本，`revision` 是上游 commit。

## 使用

镜像是上游 `docker compose up --build` 会产出的那个应用容器，**只是不再本地构建**。
最小改动用法：在你自己的 `docker-compose.yml` 里把 `build:` 换成 `image:`。

```yaml
services:
  openmaic:
    # 原本是：build: {context: ., args: [...]}
    image: ghcr.io/kenny8zeng/openmaic:v1.1.3
    ports:
      - '127.0.0.1:3000:3000'
    env_file:
      - docker-compose.defaults.env
      - .env.local
    volumes:
      - openmaic-data:/app/data
```

其余部分（PostgreSQL、`.env.local`、`openmaic.yml` 模型配置、可选 render-service）完全按
上游 [README-zh](https://github.com/THU-MAIC/OpenMAIC/blob/main/README-zh.md#docker-部署)
和 [部署文档](https://github.com/THU-MAIC/OpenMAIC/blob/main/packages/docs/content/docs/hosting.mdx)
来。两点提醒：

- 镜像里**没有**任何密钥或模型配置，全部在运行时通过环境变量 / 挂载提供。
- 课程、媒体和用量写在 `/app/data`，挂载卷，否则容器重建即丢。

本仓库**不**提供 compose 编排，也不构建 `render-service`（视频导出用的 Chromium + FFmpeg
镜像）——需要时用上游的 `render-service/Dockerfile` 自行构建。

## 升级上游版本

`OPENMAIC_REF` 是上游 ref 的单一事实来源，当前锁定 **`v1.1.3`**（最新稳定版）。

**自动（默认路径）**：`.github/workflows/check-upstream.yml` 每天 03:17 UTC 查一次上游
releases，发现更新的**稳定版**就开一个 bump PR。合并后 `push` 自动触发构建发布。

- 走 releases API 而不是 tag 列表，因为上游 monorepo 还有 `@openmaic/storage@0.37.3` 这类包 tag。
- 只认非 prerelease 的 release，并按**去掉前后缀后的数字版本**比较：这样既能阻止把
  `v1.2.0-rc.1` 降级回 `v1.1.3`，也能在 `v1.2.0` 正式版发布后把 `v1.2.0-rc.1` 顶上去。
  （直接对全串跑 `sort -V` 会把 `v1.2.0-rc.1` 排在 `v1.2.0` 后面，永远等不到正式版。）
- 如果 `OPENMAIC_REF` 被改成分支名或 commit sha，自动 bump 会跳过（不覆盖有意为之的锁定）。
- 幂等：同名分支/PR 已存在时直接跳过。

**手动**：改 `OPENMAIC_REF` 提 PR 合并，或直接 dispatch 构建任意 ref：

```bash
gh workflow run build-and-push.yml -f ref=v1.2.0-rc.1                # 一次性构建，不动 latest
gh workflow run build-and-push.yml -f ref=main -f platforms=linux/amd64 -f push=false
```

`push=false` 是**只验证能不能构建**：多平台镜像无法 `--load`，所以不会产出本地可用的镜像，
也不推送。

## 本地构建

```bash
./scripts/prepare-context.sh          # 拉取 OPENMAIC_REF 到 ./src（覆盖式）
docker build -t openmaic:local ./src

# 任意 ref / 慢速网络加速（构建参数由上游 Dockerfile 定义）
./scripts/prepare-context.sh v1.2.0-rc.1
docker build -t openmaic:local \
  --build-arg ALPINE_MIRROR=mirrors.tuna.tsinghua.edu.cn \
  --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
  ./src
```

`src/` 已在 `.gitignore` 中。脚本还把结果写进 `$GITHUB_OUTPUT`（CI 用），并输出
`ref` / `tag` / `sha` / `short_sha` / `version` 供 workflow 打标签。

## 仓库配置

| 类型 | 名称 | 用途 |
| --- | --- | --- |
| Variable 或 Secret | `DOCKERHUB_USERNAME` | Docker Hub 账号；不配则删除 workflow 里的第二个 `images` 条目 |
| Secret | `DOCKERHUB_TOKEN` | Docker Hub access token（Read & Write） |
| GitHub Actions 权限 | Settings → Actions → General | 勾选 **Allow GitHub Actions to create and approve pull requests**，否则 `check-upstream` 无法开 PR |

GHCR 用内置 `GITHUB_TOKEN`（`packages: write`），无需额外配置。发布走
`concurrency: openmaic-image-publish` 串行，避免并发写 GHCR manifest。

## 目录结构

```
OPENMAIC_REF                        # 上游 ref，唯一需要改动的地方
scripts/prepare-context.sh          # 拉取上游源码 + 应用 overlay + 计算构建输出
overlay/                            # 覆盖补丁入口（当前为空，见 overlay/README.md）
.github/workflows/build-and-push.yml  # 构建并推送镜像
.github/workflows/check-upstream.yml  # 检测上游新版本并开 PR
src/                                # 构建上下文（脚本生成，不入库）
```

构建流程：`checkout` → `prepare-context.sh`（`git fetch --depth 1 <ref>` + `checkout
FETCH_HEAD`；tag/branch 同一路径，commit sha 回退到 blobless clone）→ 应用 `overlay/` →
QEMU + Buildx → 登录 GHCR / Docker Hub → `metadata-action` 算标签 → `build-push-action`
（`context: ./src`、`file: ./src/Dockerfile`、默认 `linux/amd64,linux/arm64`、
GHA layer cache）。

需要在上游源码上打补丁时，把文件放进 `overlay/`——路径即目标位置，不用复制整个
Dockerfile。约束见 [`overlay/README.md`](overlay/README.md)。

## License

本仓库的脚本与配置为 MIT。OpenMAIC 源码同样为 MIT，版权归 THU-MAIC 所有。
