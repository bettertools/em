@REM This batch file is a neccessary evil.  The only way to modify the parent shells
@REM environment variables is inside a BATCH script, you can't do it inside an executable.
@REM So to solve this, the pm program is a batch script, which calls the pmExe.exe program
@REM which in turn outputs all it's operations as BATCH commands which are executed by
@REM this script.
@for /f "delims=" %%p in ('%~dp0\pmExe.exe batch %*') do @%%p