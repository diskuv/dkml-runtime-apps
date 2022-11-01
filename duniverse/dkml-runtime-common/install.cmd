SETLOCAL ENABLEEXTENSIONS

@ECHO ---------------------
@ECHO Arguments:
@ECHO   Target directory = %1
@ECHO ---------------------
SET TARGETDIR=%1

@REM Create unix/ subdirectory including any parent directories (extensions are enabled)
MKDIR %TARGETDIR%\unix

@REM Create all/emptytop/ subdirectory including any parent directories (extensions are enabled)
MKDIR %TARGETDIR%\all\emptytop

@REM Copy in binary mode so that CRLF is not added
COPY /Y /B META                             %TARGETDIR%
@REM   Since .template.dkmlroot goes into library, we drop the leading dot to avoid any future findlib problems
COPY /Y /B .template.dkmlroot               %TARGETDIR%\template.dkmlroot
COPY /Y /B unix\_common_tool.sh             %TARGETDIR%\unix
COPY /Y /B unix\_within_dev.sh              %TARGETDIR%\unix
COPY /Y /B unix\crossplatform-functions.sh  %TARGETDIR%\unix
COPY /Y /B all\emptytop\dune-project        %TARGETDIR%\all\emptytop
