# StarPie 桌宠素材

由 [Star-Pie 组织](https://github.com/Star-Pie)托管，SoftBlack42 维护。素材独立下载，不随主程序或桌宠插件安装包携带。

当前提供 **大肥鱼、沃雅妮莎、星绫和 Stocking** 四套桌宠形象。每套包含常驻、眨眼、点击反馈、悬空拖动和八方向姿态，共 12 张 512×512 透明 PNG；合集包含 48 张运行素材。

| 形象 | 预览 | 单独下载 |
| --- | --- | --- |
| 大肥鱼（原蓝鲸女仆） | <img src="pets/bluewhale-maid/idle.png" alt="大肥鱼" width="120"> | [v1.0.1](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/StarPie-PetAsset-local.bluewhale-maid-1.0.1.zip) |
| 沃雅妮莎 · 鱼形点心 | <img src="pets/vodyanitsa/idle.png" alt="沃雅妮莎" width="120"> | [v1.0.0](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/StarPie-PetAsset-local.vodyanitsa.chibi-1.0.0.zip) |
| 星绫（小名「绫绫」） | <img src="pets/starpie-chibi/idle.png" alt="星绫" width="120"> | [v1.0.1](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/StarPie-PetAsset-local.starpie-chibi-1.0.1.zip) |
| Stocking | <img src="pets/stocking/idle.png" alt="Stocking" width="120"> | [v1.0.0](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/StarPie-PetAsset-local.stocking-1.0.0.zip) |

## 下载与使用

[下载四套素材合集](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/StarPie-DesktopPet-Assets-2026.10.10.1.zip) · [SHA-256 校验](https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/SHA256SUMS.txt)

单独包解压后，在 StarPie「管理桌宠 → 导入文件夹」选择解压目录，再选择形象并使用。合集需选择其中的角色子文件夹，例如「大肥鱼」，不选择合集最外层。当前插件不直接导入 ZIP。

需要支持该 12 状态 PNG 格式的桌宠插件和匹配的主程序。桌宠插件 0.1.6 正式版要求 SDK 1.11，可在 StarPie v1.8.0-beta.7 的官方插件市场安装。本仓库只提供素材，不包含主程序或插件。

## 初期试用

目前用于桌宠插件的早期功能试用，先验证导入、形象切换、悬空拖动和轮盘方向联动。大肥鱼仅更新名称与说明，蓝鲸女仆原有图片不变；星绫图片与已有 v1.0.1 下载包相同。历史迭代草稿、参考原图和废弃方案不重复收入合集。

## 维护工具

`tools/Test-PetAssets.ps1` 检查全部素材；`tools/Pack-PetAssets.ps1` 生成四套单独包，`-PackId` 可选择一套。角色 ID 和 12 状态文件名保持稳定。最终下载包的 SHA-256 附于 Release。
