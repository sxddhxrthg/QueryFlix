# Running QueryFlix on Windows

Tested steps for Windows 10/11. Use **Command Prompt** (cmd) for everything below
(Start menu → type `cmd`). PowerShell also works, but see the npm note.

## 1. Install the tools (once)

| Tool | Where | Notes |
|---|---|---|
| MySQL Community Server 8.0 / 8.4 LTS | dev.mysql.com/downloads/mysql → Windows MSI | During setup: set a **root password** (remember it), keep port **3306**, keep "Start MySQL at system startup" ticked. |
| Node.js 22 LTS | nodejs.org | Needs 20.19+ or 22.12+. Tick "Add to PATH". |
| Python 3 (optional) | python.org | Only for the duration step. Tick "Add python.exe to PATH". |

**Put `mysql.exe` on PATH:** Start → "Edit the system environment variables" →
Environment Variables → *Path* → Edit → New →
`C:\Program Files\MySQL\MySQL Server 8.4\bin` (use 8.0 if that's what you installed) → OK.
**Close and reopen** Command Prompt, then check:

```bat
mysql --version
node -v
```

## 2. Build the database

Unzip QueryFlix (for example to `C:\QueryFlix`), then:

```bat
cd C:\QueryFlix
database\import.bat
```

Type the MySQL root password when asked. It takes about 35–60 seconds and ends
with a validation table: every row should be PASS or INFO, **no FAIL**.

## 3. Start the backend (Command Prompt window 1)

```bat
cd C:\QueryFlix\backend
copy .env.example .env
npm install
npm run dev
```

Keep this window open. Check http://localhost:4000/api/health in a browser →
`"mysqlConnected": true`.

## 4. Start the frontend (Command Prompt window 2)

```bat
cd C:\QueryFlix\frontend
copy .env.example .env
npm install
npm run dev
```

Open **http://localhost:5173**.

## 5. Optional: newer runtimes from TMDB

Duration personalisation already works: the build loads a bundled runtime
snapshot covering 99% of MovieLens ratings and the 2010–2017 Netflix movies.
Only if you also want 2018–2025 movies and TV shows (free TMDB key, ~15 min):

```bat
cd C:\QueryFlix
set TMDB_API_KEY=your_key_here
py database\enrichment\fetch_tmdb_runtime.py
database\import.bat
```

Then stop the backend (Ctrl+C) and run `npm run dev` again.

## Every time after that

MySQL starts with Windows automatically, so you only need steps 3 and 4
(`npm run dev` in backend and in frontend). No need to rebuild the database.

## Troubleshooting

| Problem | Fix |
|---|---|
| `'mysql' is not recognized` | PATH not set, or you didn't reopen Command Prompt (step 1). |
| `Can't connect to MySQL server on '127.0.0.1'` | MySQL service stopped: Win+R → `services.msc` → **MySQL80**/**MySQL84** → Start. |
| `Access denied for user 'root'` | Wrong root password; run import.bat again. |
| `Loading local data is disabled` | Run `mysql -u root -p -e "SET GLOBAL local_infile=1;"` then import.bat again. |
| PowerShell: `npm.ps1 cannot be loaded because running scripts is disabled` | Use Command Prompt instead, or run once in PowerShell: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. |
| Backend: `Access denied for user 'queryflix'` | `backend\.env` must contain `DB_USER=queryflix` and `DB_PASSWORD=change_me`. Re-run import.bat (it creates the user). |
| Browser: "Could not reach the QueryFlix API" | Backend window closed or crashed; run step 3 again. |
| `EADDRINUSE` port 4000/5173 | Something is already running there. Close the old window, or restart the PC. |
| Personalisation page very slow | Re-run `database\import.bat` (it refreshes MySQL's statistics at the end). |
| Git Bash users | `bash database/import.sh` also works. First add MySQL to Git Bash's path: `export PATH="$PATH:/c/Program Files/MySQL/MySQL Server 8.4/bin"`. |
| Cloned from GitHub and loads look wrong | Keep the `.gitattributes` file; it stops Git adding Windows line endings to the CSV files. |
