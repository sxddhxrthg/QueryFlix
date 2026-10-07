@echo off
rem ============================================================
rem QueryFlix : build the full database on Windows (Command Prompt)
rem Run from anywhere:   database\import.bat
rem Same steps as database/import.sh. Needs mysql.exe on PATH.
rem ============================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0.."

rem check by actually running mysql (the "where" command misreads some PATH entries)
mysql --version >nul 2>nul
if errorlevel 1 (
  echo.
  echo  mysql.exe was not found.
  echo  Add "C:\Program Files\MySQL\MySQL Server 8.0\bin" ^(or 8.4 / 9.x^) to PATH,
  echo  then open a NEW Command Prompt and run this again.
  exit /b 1
)

if "%MYSQL_USER%"=="" set "MYSQL_USER=root"
if "%MYSQL_HOST%"=="" set "MYSQL_HOST=127.0.0.1"
if "%MYSQL_PORT%"=="" set "MYSQL_PORT=3306"

set "PW="
set /p "PW=MySQL password for %MYSQL_USER% (press Enter if none): "

rem password goes in a temporary option file, deleted at the end
set "CNF=database\.mysql_import.cnf"
> "%CNF%" echo [client]
>> "%CNF%" echo password="!PW!"
set "PW="

set MYSQL=mysql --defaults-extra-file=%CNF% --local-infile=1 --default-character-set=utf8mb4 -h %MYSQL_HOST% -P %MYSQL_PORT% -u %MYSQL_USER%

echo [1/8] Enabling local_infile (needed by LOAD DATA LOCAL INFILE)...
%MYSQL% -e "SET GLOBAL local_infile = 1;" || goto :fail

echo [2/8] Netflix schema + 32,000 rows...
%MYSQL% < database\schema.sql || goto :fail
%MYSQL% queryflix < database\seed.sql || goto :fail

echo [3/8] Unified schema (tables, foreign keys, helper functions)...
%MYSQL% queryflix < database\unified_schema.sql || goto :fail

echo [4/8] Normalising Netflix into titles / people / genres / countries (about 30 s)...
%MYSQL% queryflix < database\build_catalog.sql || goto :fail

echo [5/8] Loading MovieLens (movies, links, ratings, tags)...
%MYSQL% queryflix < database\load_movielens.sql || goto :fail

echo [6/8] Building the title mapping layer...
%MYSQL% queryflix < database\build_mapping.sql || goto :fail

echo [6b] Loading runtimes ^(bundled 2017 TMDB snapshot^)...
%MYSQL% queryflix < database\load_runtime.sql || goto :fail
if exist database\enrichment\tmdb_runtime.csv (
  echo [6c] Loading runtimes fetched from the TMDB API...
  %MYSQL% queryflix < database\load_runtime_api.sql || goto :fail
) else (
  echo [6c] Optional live TMDB file not found - using the snapshot only.
)

echo [7/8] Creating analytical views...
%MYSQL% queryflix < database\views.sql || goto :fail

echo [8/8] Validation report...
%MYSQL% -t queryflix < database\validation.sql > database\validation_report.txt || goto :fail
type database\validation_report.txt

echo Creating the app user queryflix / change_me (matches backend\.env.example)...
%MYSQL% -e "CREATE USER IF NOT EXISTS 'queryflix'@'localhost' IDENTIFIED BY 'change_me'; CREATE USER IF NOT EXISTS 'queryflix'@'127.0.0.1' IDENTIFIED BY 'change_me'; GRANT ALL PRIVILEGES ON queryflix.* TO 'queryflix'@'localhost'; GRANT ALL PRIVILEGES ON queryflix.* TO 'queryflix'@'127.0.0.1'; FLUSH PRIVILEGES;" || goto :fail

del "%CNF%" >nul 2>nul
echo.
echo Done. Check above: the validation table should show PASS and no FAIL.
exit /b 0

:fail
del "%CNF%" >nul 2>nul
echo.
echo  A step failed - read the MySQL error message just above.
echo  Common fixes are in RUN_ON_WINDOWS.md.
exit /b 1
