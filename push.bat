@echo off
chcp 65001 >nul
echo ===== MyHub 一键上传到 GitHub =====
echo.

cd /d "%~dp0"
echo 当前目录: %CD%
echo.

:: 初始化 Git
git init
git branch -M main

:: 配置身份（请修改成你自己的信息）
git config user.name "Kyle-lmy"
git config user.email "qlu62037@gmail.com"

:: 添加文件并提交
git add .
git commit -m "初始提交：作品集主页+开发文档"

:: 连接远程仓库并推送
git remote remove origin 2>nul
git remote add origin https://github.com/Kyle-lmy/MyHub.git

echo.
echo ===== 准备推送，请输入 GitHub Token =====
echo 用户名输入: Kyle-lmy
echo 密码输入: 你的 GitHub Token（不是登录密码）
echo.
git push -u origin main

pause
