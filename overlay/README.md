# overlay/

构建上下文是 `scripts/prepare-context.sh` 拉取的上游 OpenMAIC 源码树。这个目录
是唯一的"覆盖补丁"入口：其中每个条目（文件或目录）都会在拉取完成后被 `cp -a`
覆盖到源码树根目录，因此可以在**不 vendor 上游 Dockerfile** 的前提下打补丁，
例如替换某个配置文件、追加一个构建产物。

## 当前状态

**没有实际补丁。** 目录里只有这份说明，构建完全使用上游 Dockerfile。机制先行
保留，是为了让"上游某处需要改一行"的场景不必退化成复制整个 Dockerfile。

## 使用约定

- 路径即目标位置。`overlay/Dockerfile` 会覆盖上游根目录的 `Dockerfile`；
  `overlay/configs/x.json` 会写到 `<src>/configs/x.json`。
- 文件名必须是 `README.md` 之外的任何东西；`README.md` 只用于本说明，不会被复制。
- 上游根目录 `.dockerignore` 会排除 `*.md`、`assets`、`docs`、`data`、`.git`
  等路径，所以这些名字的补丁进不了镜像——它们也不会进构建上下文。
- 补丁是隐式的：升级 `OPENMAIC_REF` 后如果上游改了同名文件，覆盖会继续生效。
  每次改动上游版本时请复查本目录，必要时删除已上游化的补丁。
- 上游 `Dockerfile` 的构建参数（`ALPINE_MIRROR`、`NPM_REGISTRY`、
  `NEXT_PUBLIC_*`、`ALLOWED_FRAME_ANCESTORS`）由 workflow 统一处理，补丁不需要
  重复声明。
