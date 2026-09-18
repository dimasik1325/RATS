@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "GAME_DIR=%~dp0"
set "GAME_FILE=index.html"
set "PORT=4173"
set "PYTHON="
set "PY_ARGS="

rem Make sure the game files are next to this BAT file.
if not exist "%GAME_DIR%index.html" (
    if exist "%GAME_DIR%rats.html" (
        set "GAME_FILE=rats.html"
    ) else (
        echo.
        echo [ERROR] index.html was not found next to this BAT file.
        echo Put start_game.bat in the same folder as index.html and three.module.js.
        echo Current folder:
        echo %GAME_DIR%
        echo.
        dir /b "%GAME_DIR%"
        pause
        exit /b 2
    )
)

call :find_python
if defined PYTHON goto :find_game_port

call :install_python
call :find_python
if defined PYTHON goto :find_game_port

echo.
echo [ERROR] Python could not be installed automatically.
echo Install Python from https://www.python.org/downloads/windows/
echo Then run this file again.
pause
exit /b 1

:find_python
where py >nul 2>&1
if not errorlevel 1 (
    py -3 --version >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON=py"
        set "PY_ARGS=-3"
        exit /b 0
    )
)
where python >nul 2>&1
if not errorlevel 1 (
    python --version >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON=python"
        set "PY_ARGS="
        exit /b 0
    )
)
exit /b 0

:install_python
echo Python was not found. Installing it now...
echo.

where winget >nul 2>&1
if not errorlevel 1 (
    echo Installing Python with winget...
    winget install --id Python.Python.3.13 -e --scope user --silent --accept-package-agreements --accept-source-agreements
    call :find_python
    if defined PYTHON exit /b 0
)

echo Downloading the official Python installer...
set "PY_INSTALLER=%TEMP%\python-installer-3.13.7-amd64.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://www.python.org/ftp/python/3.13.7/python-3.13.7-amd64.exe'; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $env:PY_INSTALLER"
if not exist "%PY_INSTALLER%" exit /b 1
start "Python setup" /wait "%PY_INSTALLER%" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
del /q "%PY_INSTALLER%" >nul 2>&1
set "PATH=%LocalAppData%\Programs\Python\Python313;%LocalAppData%\Programs\Python\Python313\Scripts;%PATH%"
exit /b 0

:find_game_port
rem Reuse our existing game server when possible.
rem If another program occupies the port, move to the next free port.
:check_port
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='http://127.0.0.1:%PORT%/__rats_alive'; try { $r=Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 1; if($r.StatusCode -eq 204){ exit 0 } } catch {}; exit 1" >nul 2>&1
if not errorlevel 1 goto :open_game

netstat -ano | findstr /R /C:":%PORT% .*LISTENING" >nul 2>&1
if errorlevel 1 goto :start_server

set /a PORT+=1
if %PORT% GTR 4199 (
    echo [ERROR] No free port was found between 4173 and 4199.
    pause
    exit /b 3
)
goto :check_port

:start_server
echo Starting the game server on port %PORT%...
rem Start the lifecycle-aware server. It stops when the game page is closed.
if not exist "%GAME_DIR%game_server.py" (
    echo [ERROR] game_server.py was not found next to this BAT file.
    pause
    exit /b 5
)
start "Rats game server" /b /d "%GAME_DIR%" %PYTHON% %PY_ARGS% "%GAME_DIR%game_server.py" %PORT% "%GAME_DIR%."

set /a WAIT=0
:wait_server
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='http://127.0.0.1:%PORT%/%GAME_FILE%'; try { $r=Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 1; if($r.StatusCode -eq 200 -and $r.Content -match 'RATS_GAME_MARKER'){ exit 0 } } catch {}; exit 1" >nul 2>&1
if not errorlevel 1 goto :open_game
set /a WAIT+=1
if %WAIT% GEQ 8 goto :server_error
timeout /t 1 /nobreak >nul
goto :wait_server

:server_error
echo.
echo [ERROR] The server started, but the game file was not found.
echo Folder used by the server:
echo %GAME_DIR%
echo Files in that folder:
dir /b "%GAME_DIR%"
pause
exit /b 4

:open_game
call :find_browser
if defined BROWSER goto :open_app_window

rem Fallback for systems without Chrome or Edge. The page still monitors the server.
start "" "http://127.0.0.1:%PORT%/%GAME_FILE%"
echo The game is open in your browser.
exit /b 0

:find_browser
set "BROWSER="
rem Prefer Google Chrome; use Edge only as a fallback.
for %%P in (
    "%ProgramFiles%\Google\Chrome\Application\chrome.exe"
    "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
    "%LocalAppData%\Google\Chrome\Application\chrome.exe"
) do if not defined BROWSER if exist "%%~P" set "BROWSER=%%~P"
if not defined BROWSER for /f "delims=" %%P in ('where chrome.exe 2^>nul') do if not defined BROWSER set "BROWSER=%%P"
if defined BROWSER exit /b 0
for %%P in (
    "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
    "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
    "%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
) do if not defined BROWSER if exist "%%~P" set "BROWSER=%%~P"
if not defined BROWSER for /f "delims=" %%P in ('where msedge.exe 2^>nul') do if not defined BROWSER set "BROWSER=%%P"
exit /b 0

:open_app_window
set "APP_PROFILE=%TEMP%\RatsGameProfile_%RANDOM%_%RANDOM%"
echo The game is open in a dedicated browser window.
start "Rats game window" /wait "%BROWSER%" --app="http://127.0.0.1:%PORT%/%GAME_FILE%" --user-data-dir="%APP_PROFILE%" --no-first-run --disable-session-crashed-bubble
rem If the browser closed first, also ask the server to close.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='http://127.0.0.1:%PORT%/__rats_close'; try { Invoke-WebRequest -UseBasicParsing -Method Post -Uri $u -TimeoutSec 1 | Out-Null } catch {}" >nul 2>&1
exit /b 0
