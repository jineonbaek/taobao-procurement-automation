# TaoBao Procurement Automation / 淘宝采购清单自动化工具

## Features / 功能
- Paste a Taobao/Tmall share link -> auto-extract product info (variant, price, shop)
- 粘贴淘宝/天猫分享链接 -> 自动解析商品信息（颜色分类、价格、店铺）
- Automatically append to a local Excel file
- 自动追加到本地 Excel 文件

## Requirements / 环境要求
- Python 3.10+ (with pip)
- Windows / macOS / Linux
- A Taobao account (recommend dedicated account without payment info / 建议使用未绑定支付的专用账号)
- Internet connection / 网络连接

## File Structure / 文件结构

```
purchase workflow/
├── setup.bat              # First-time configuration / 首次配置
├── run.bat                # Daily use / 日常使用
├── setup.ps1              # Setup script (called by setup.bat)
├── run.ps1                # Run script (called by run.bat)
├── taobao_parser.py       # Core parser / 核心解析脚本
├── requirements.txt       # Python dependencies / Python依赖
├── README.md              # This file / 本文件
├── data/                  # Account data (delete to reset login / 删此文件夹=重置登录)
│   ├── .taobao.env         #   Your Taobao credentials / 淘宝账号密码
│   └── .taobao_cookies.json # Login session / 登录Cookie
└── 采购清单.xlsx           # OUTPUT: procurement list / 输出文件：采购清单
```

## First-Time Setup / 首次配置

Double-click `setup.bat` / 双击 `setup.bat`：
1. Install Python dependencies (playwright, openpyxl) / 安装Python依赖
2. Download Chromium browser (~180MB, one-time) / 下载Chromium浏览器（约180MB，仅一次）
3. Enter Taobao phone number and password / 输入淘宝手机号和密码
4. Complete login (may require SMS verification) / 完成登录（可能需要短信验证）

## Daily Use / 日常使用

Double-click `run.bat` -> paste Taobao link -> Enter -> appended to Excel
双击 `run.bat` -> 粘贴淘宝链接 -> 回车 -> 追加到Excel

The Excel file `采购清单.xlsx` is saved in the same folder.
Excel 文件保存在同一文件夹下。

## Excel Format / Excel格式

| Date | Item (Variant) | Qty | Source | Price | Link |
| 日期 | 采购物品(颜色分类) | 数量 | 渠道 | 价格 | 链接 |
|---|---|---|---|---|---|---|
| 07-23 | Silver Moon Gray / 银月灰 | 1 | Taobao | Y=469 | direct link |

## Reset Login / 重置登录

Delete the `data/` folder, then run `setup.bat` again.
删除 `data/` 文件夹，重新运行 `setup.bat`。

## Security / 安全说明
- Credentials in `data/.taobao.env` are stored locally only, never uploaded
- 账号密码仅存储在本地 `data/.taobao.env`，绝不上传
- Login cookies in `data/.taobao_cookies.json` auto-renew on each use
- 登录Cookie自动续期
- The `data/` folder contains ALL personal data - delete it to wipe everything
- 删除 `data/` 文件夹即可清除所有个人数据

## Troubleshooting / 常见问题

| Problem / 问题 | Solution / 解决方法 |
|---|---|
| Login failed / 登录失败 | Run `setup.bat` again, check SMS / 重跑 setup.bat，检查短信 |
| Garbled terminal text / 终端乱码 | Normal, Excel output is correct / 正常现象，Excel输出不受影响 |
| Chromium download slow / 下载太慢 | One-time only, ~180MB / 仅首次下载约180MB |
| "Not logged in" on run.bat | Run setup.bat first / 先运行 setup.bat |
