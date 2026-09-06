@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem ============================================================
rem  Captive 一键诊断（只读检查，不修改任何配置）
rem  用法：右键 → 以管理员身份运行
rem ============================================================

rem ---- 需要管理员权限才能识别端口占用者 ----
if defined CI_SKIP_ADMIN goto :hasadmin
net session >nul 2>&1
if errorlevel 1 (
  echo 诊断需要管理员权限（要识别端口占用者），正在请求提升...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  echo.
  echo 如果上方没有弹出 UAC 权限确认框，说明提权被取消或失败。
  echo 请关闭本窗口后，右键此文件选择【以管理员身份运行】。
  pause
  exit /b
)
:hasadmin

set "ROOT=%~dp0"
set "NODE=%ROOT%runtime\node\node.exe"
set "CAPTIVE=%ROOT%apps\captive"
set "CNT=0"
set "LASTQ="

echo.
echo ============================================================
echo   Captive 故障诊断
echo   逐项只读检查。标 [失败] 的行按"处理"操作即可。
echo ============================================================
echo.

rem ================= [1] 便携 Node =================
echo [1] 便携 Node
if not exist "%NODE%" (
  echo   [失败] 未找到 runtime\node\node.exe
  echo          处理: 便携包不完整，请整包拷贝（含 runtime 目录）
  set /a CNT+=1
) else (
  for /f %%v in ('"%NODE%" -v 2^>nul') do echo   [OK] node %%v 可用
)
echo.

rem ================= [2] TLS 证书 =================
echo [2] TLS 证书（apps\captive\certs）
if not exist "%CAPTIVE%\certs\cert.pem" (
  echo   [失败] 未找到 cert.pem
  echo          处理: 双击 5-captive热点劫持-启动.bat，会自动生成证书
  set /a CNT+=1
) else (
  "%NODE%" "%ROOT%scripts\check-cert.js" "%CAPTIVE%\certs"
  if errorlevel 1 set /a CNT+=1
)
echo.

rem ================= [3] UDP 端口 53 占用 =================
echo [3] UDP 端口 53（DNS 劫持必需）
set "U53="
netstat -ano -p udp 2>nul | findstr /c:":53 " > "%TEMP%\ci_u53.txt" 2>nul
if exist "%TEMP%\ci_u53.txt" (
  for /f "usebackq tokens=4" %%p in ("%TEMP%\ci_u53.txt") do set "U53=!U53! %%p"
)
if not defined U53 (
  echo   [OK] 53 端口空闲，captive 可直接绑定
) else (
  echo   [警告] 53 被占用 —— captive 的 DNS 拦截将不生效，占用者：
  for %%p in (!U53!) do call :SHOW_OCCUPIER %%p 53 UDP
)
echo.

rem ================= [4] TCP 端口 443 占用 =================
echo [4] TCP 端口 443（HTTPS 反代必需）
set "T443="
set "LASTQ="
netstat -ano -p tcp 2>nul | findstr "LISTENING" | findstr /c:":443 " > "%TEMP%\ci_t443.txt" 2>nul
if exist "%TEMP%\ci_t443.txt" (
  for /f "usebackq tokens=5" %%p in ("%TEMP%\ci_t443.txt") do set "T443=!T443! %%p"
)
if not defined T443 (
  echo   [OK] 443 端口空闲，captive 可直接绑定
) else (
  echo   [警告] 443 被占用，占用者：
  for %%p in (!T443!) do call :SHOW_OCCUPIER %%p 443 TCP
)
echo.

rem ================= [5] Captive 运行状态判定 =================
echo [5] Captive 运行状态
if not defined WHO53 if not defined WHO443 goto :S5_none
if defined WHO53 if defined WHO443 goto :S5_both
if defined WHO53 goto :S5_only53
goto :S5_only443

:S5_none
echo   [提示] captive 未运行（端口均空闲），可直接双击 5 启动
goto :S5_done
:S5_both
if /i "!WHO53!"=="node.exe" if /i "!WHO443!"=="node.exe" (
  echo   [OK] captive 正在运行（PID 53=!PID53! 443=!PID443!）
  echo        若劫持不生效，多半是热点问题，见下方 [6]
) else (
  echo   [失败] 53 与 443 被不同程序占用，captive 无法完整工作
)
goto :S5_done
:S5_only53
echo   [注意] 只有 DNS(53) 被占用 —— 具体占用者见上方 [3]
goto :S5_done
:S5_only443
if /i "!WHO443!"=="node.exe" (
  echo   [警示] HTTPS（443） 在工作但 DNS（53） 未绑定 —— 劫持无效！
  echo          原因通常是 53 被系统服务抢走，见上方 [3] 处理
)
:S5_done
echo.

rem ================= [6] 移动热点 =================
echo [6] 移动热点 / ICS
set "SSTATE="
for /f "tokens=4" %%s in ('sc query SharedAccess 2^>nul ^| findstr /i "STATE"') do set "SSTATE=%%s"
if /i "!SSTATE!"=="RUNNING" (
  echo   [OK] ICS 服务运行中（热点底层服务正常）
) else (
  echo   [注意] ICS 服务当前状态: !SSTATE!
  echo          captive 运行期间会主动停止它（属预期）；
  echo          若 captive 没在跑且热点打不开，请手动开一次移动热点
)
ping -n 1 -w 800 192.168.137.1 >nul 2>&1
if errorlevel 1 (
  echo   [失败] 热点网关 192.168.137.1 ping 不通
  echo          处理: 设置 → 网络和 Internet → 移动热点 打开
  echo                若热点网段不是 192.168.137.x，需同步改
  echo                apps\captive\hotspot-redirect.js 的 hotspotIP
  set /a CNT+=1
) else (
  echo   [OK] 热点网关 192.168.137.1 可达，热点已生效
)
echo.

rem ================= [7] ClassIntra 后端 =================
echo [7] ClassIntra 后端（反代目标 9001）
netstat -ano -p tcp 2>nul | findstr "LISTENING" | findstr /c:":9001 " >nul 2>&1
if errorlevel 1 (
  echo   [失败] 9001 未监听 —— 学生设备访问会被 captive 回 502
  echo          处理: 先双击 2-启动ClassIntra.bat 启动后端
  set /a CNT+=1
) else (
  echo   [OK] ClassIntra 9001 在监听
)
echo.

rem ================= [8] 历史日志 =================
echo [8] 静默模式日志（logs\service.log）
if exist "%CAPTIVE%\logs\service.log" (
  echo   --- 日志内容（末尾为最近一次运行）---
  type "%CAPTIVE%\logs\service.log" 2>nul
  echo   --- 日志结束 ---
) else (
  echo   [提示] 无日志文件 —— 尚未用过静默/看门狗模式，或日志已清理
)
echo.

rem ================= 汇总 =================
echo ============================================================
if !CNT! equ 0 (
  echo 检查完毕：未发现明显故障点。
  echo.
  echo 若 captive 仍然失败，把 5 号脚本窗口关闭前最后的
  echo 英文报错发出来，常见报错对照：
  echo   EADDRINUSE  → 端口被占（见上方 [3][4]）
  echo   EACCES      → 权限不足（本工具已确认你有管理员权限）
  echo   Failed to load certificate → 证书问题（见 [2]）
  echo   Failed to start mobile hotspot → 热点开不起来（见 [6]）
  echo   Backend unreachable → ClassIntra 没启动（见 [7]）
) else (
  echo 发现 !CNT! 处问题，请按上方 [失败] 标注的"处理"逐条
  echo 操作后再重试启动。
)
echo ============================================================
echo.
pause
exit /b

rem ============================================================
rem  子过程：查占用 PID 的进程与服务，给出针对性处理
rem  参数: %1=PID  %2=端口  %3=UDP/TCP
rem ============================================================
:SHOW_OCCUPIER
if "%~1"=="" goto :eof
if "%~1"=="%LASTQ%" goto :eof
set "LASTQ=%~1"
set "IMG="
set "SVC="
for /f "usebackq tokens=1 delims=," %%a in (`tasklist /FI "PID eq %~1" /NH /FO CSV 2^>nul`) do set "IMG=%%~a"
if not defined IMG (
  echo      PID %~1 已退出（残留监听，稍等自动消失）
  goto :eof
)
if /i "!IMG!"=="svchost.exe" (
  for /f "usebackq tokens=3 delims=," %%c in (`tasklist /svc /FI "PID eq %~1" /NH /FO CSV 2^>nul`) do set "SVC=%%~c"
)
echo      -> 进程: !IMG!  PID=%~1  %~3端口%~2
if /i "!IMG!"=="node.exe" (
  echo         [OK] 是 node —— captive/ClassIntra 自己占用，属正常运行
  if /i "%~3"=="UDP" set "WHO53=node.exe" & set "PID53=%~1"
  if /i "%~3"=="TCP" set "WHO443=node.exe" & set "PID443=%~1"
  goto :eof
)
if /i "!IMG!"=="svchost.exe" (
  if defined SVC (
    echo         所属服务: !SVC!
    if not "!SVC:SharedAccess=!"=="!SVC!" (
      echo         [失败] 这是 Windows 热点/共享服务（SharedAccess）占用
      echo                处理: 双击 5-captive热点劫持-启动.bat
      echo                （脚本会自动停 SharedAccess 释放 53）
      set /a CNT+=1
    ) else (
      echo         [失败] 系统服务占用了端口
      echo                处理: 在"服务"管理里停掉对应服务后重试
      set /a CNT+=1
    )
  ) else (
    echo         [失败] Windows 系统服务占用，无法读取服务名
    echo                处理: 命令提示符（管理员）执行 tasklist /svc 查看
    set /a CNT+=1
  )
) else if /i "!IMG!"=="System" (
  echo         [失败] 系统内核（netio/http.sys）占用 443 —— 常有 IIS/其他服务
  echo                处理: netsh http show servicestate 查看是谁注册的
  set /a CNT+=1
) else (
  echo         [失败] 第三方程序占用了端口！需先关闭它
  echo                处理: 结束该程序，或用 6-停止Captive.bat 停止冲突服务
  set /a CNT+=1
)
if /i "%~3"=="UDP" set "WHO53=!IMG!" & set "PID53=%~1"
if /i "%~3"=="TCP" set "WHO443=!IMG!" & set "PID443=%~1"
goto :eof
