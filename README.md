# StarPie 桌宠素材

当前提供 **星绫**（小名「绫绫」）v1.0.0：蓝紫长发、四角星与轮盘发饰、白色指针胸针。包含常驻、眨眼、点击反馈、悬空拖动和八方向姿态，共 12 张 512×512 透明 PNG。

![星绫](pets/starpie-chibi/idle.png)

## 下载与使用

[下载星绫 v1.0.0](https://github.com/SoftBlack42/StarPie-DesktopPet-Assets/releases/download/xingling-v1.0.0/StarPie-PetAsset-local.starpie-chibi-1.0.0.zip) · [SHA-256 校验](https://github.com/SoftBlack42/StarPie-DesktopPet-Assets/releases/download/xingling-v1.0.0/SHA256SUMS.txt)

解压后，在 StarPie「管理桌宠 → 导入文件夹」选择解压目录，然后选择「星绫」并使用此形象。当前插件不直接导入 ZIP。

需要支持该 12 状态 PNG 格式的桌宠插件和匹配的主程序。当前桌宠插件候选要求 SDK 1.11；对应的 StarPie v1.8.0-beta.7 正在准备。本仓库只提供素材，不包含主程序或插件。

## 来源与分发

素材由内置 imagegen 生成，SoftBlack42 负责整理与发布。配色和装饰元素参考 StarPie 软件图标；人物轮廓与 Q 版比例参考用户提供的形象图，参考图制作者署名 [这个刀子真甜](https://space.bilibili.com/23315338)。原参考图未上传。

用户已确认本套生成素材公开分发。详细依据见 [RIGHTS.md](pets/starpie-chibi/RIGHTS.md)；不声明 MIT、CC0 或另行商用、再许可授权。此前蓝鲸女仆 Release 和主分支素材已撤回，旧版本仅保留在 Git 历史。

## 维护工具

`tools/Test-PetAssets.ps1` 检查素材；`tools/Pack-PetAssets.ps1 -PackId local.starpie-chibi` 生成星绫包。角色 ID 保持稳定，名称变更不改变 12 状态文件名。最终下载包的 SHA-256 附于 Release。
