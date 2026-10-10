# StarPie 桌宠素材

当前提供 **星绫**（小名「绫绫」）v1.0.1：蓝紫长发、四角星与轮盘发饰、白色指针胸针。包含常驻、眨眼、点击反馈、悬空拖动和八方向姿态，共 12 张 512×512 透明 PNG。

![星绫](pets/starpie-chibi/idle.png)

## 下载与使用

[下载星绫 v1.0.1](https://github.com/SoftBlack42/StarPie-DesktopPet-Assets/releases/download/xingling-v1.0.1/StarPie-PetAsset-local.starpie-chibi-1.0.1.zip) · [SHA-256 校验](https://github.com/SoftBlack42/StarPie-DesktopPet-Assets/releases/download/xingling-v1.0.1/SHA256SUMS.txt)

解压后，在 StarPie「管理桌宠 → 导入文件夹」选择解压目录，然后选择「星绫」并使用此形象。当前插件不直接导入 ZIP。

需要支持该 12 状态 PNG 格式的桌宠插件和匹配的主程序。当前桌宠插件候选要求 SDK 1.11；对应的 StarPie v1.8.0-beta.7 正在准备。本仓库只提供素材，不包含主程序或插件。

## 初期试用

目前用于桌宠插件的早期功能试用，先验证导入、形象切换、悬空拖动和轮盘方向联动。v1.0.1 只更新说明和素材信息，12 张 PNG 与 v1.0.0 完全一致。更完整的使用教程、素材目录和反馈方式随配套版本逐步完善。

## 维护工具

`tools/Test-PetAssets.ps1` 检查素材；`tools/Pack-PetAssets.ps1 -PackId local.starpie-chibi` 生成星绫包。角色 ID 保持稳定，名称变更不改变 12 状态文件名。最终下载包的 SHA-256 附于 Release。
