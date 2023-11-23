/* Give back a directory for DkML configuration files that is writable only
   by a system administrator.
   
   This executable provides a little bit of safety as a staging-files
   executable during an installation. It doesn't rely on environment
   variables that actors can insert during the installer. However, if
   an actor has access to a Windows user account, there is nothing
   that can safely figure out the location or contents of
   administrator-created configuration. */

#include <stdlib.h>

#ifdef _WIN32

#include <wchar.h>
#include <Windows.h>
#include <Knownfolders.h>
#include <Shlobj.h>

int main()
{
	HRESULT hr;
	PWSTR path = NULL;
	hr = SHGetKnownFolderPath(&FOLDERID_ProgramData, 0, NULL, &path);
	CoTaskMemFree(path);

	if (SUCCEEDED(hr)) {
		wprintf_s(L"%s\\DiskuvOCaml\\conf\n", path);
	} else {
		fwprintf_s(stderr, L"FATAL: Failed to find the Windows known folder ProgramData\n");
		exit(7);
	}
	return 0;
}

#else

#include <stdio.h>

int main()
{
	printf("/etc/diskuv-ocaml\n");
	return 0;
}

#endif /* _WIN32 */
