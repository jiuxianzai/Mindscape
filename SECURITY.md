# Security Policy

Mindscape 是纯本地应用：不登录、不上传数据；除检查更新外不联网。导图数据保存在本机 SQLite 文件中。

## 报告安全问题

请不要在公开 issue 中披露漏洞细节。优先使用 GitHub 的私密漏洞报告：

**Security → Report a vulnerability**

如果该入口不可用，请先开一个不含利用细节的 issue，说明希望私下联系维护者。

## 范围

- 本地数据库读写与路径处理
- Markdown / OPML / JSON 导入
- 画布文本编辑与剪贴板粘贴
- 发布包签名与分发

## 不支持的范围

- 已越狱 / 被注入的 macOS 环境
- 用户自行修改源码后产生的问题
- 社会工程、物理访问、系统级恶意软件
