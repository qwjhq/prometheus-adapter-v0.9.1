multi-build-template
构建跨平台应用（二进制以及容器的模板项目），直接clone添加代码进行使用

创建跨架构构架驱动器
make multi-driver

一键构建不同架构镜像
make build-all-images

一键push镜像 生成manifest至镜像仓库
make manifest-auto

常见问题
构建过程超过5分钟
直接停止重新构建，构建过程使用docker-container，特殊条件下存在问题

构建驱动器配置文件
https://github.com/moby/buildkit/blob/master/docs/buildkitd.toml.md