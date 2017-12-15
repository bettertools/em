dmd -ofpmExe pm.d common.d
@if errorlevel 1 (
  echo Failed to build pmExe
  goto EXIT
)

dmd -ofemExe em.d common.d
@if errorlevel 1 (
  echo Failed to build emExe
  goto EXIT
)

:EXIT