@echo off
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py) || (set PY=python)
%PY% -m pip install --upgrade pip
%PY% -m pip install -r requirements.txt
echo.
echo Pronto! Agora rode o 1_calibrar.bat
pause
