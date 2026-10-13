// GargosyUpdate.exe (issue #16): replaces Gargosy's app files after it exits.
//
// The rules, the same as Gargosy's own check (lib/update/app_files.dart):
// only the files listed in app-files.txt are ever moved or written; a list
// with an absolute path, a ".." or a path in roms\, emulators\, bios\ or
// userdata\ is refused before anything moves; a failure puts every file back.
#pragma once

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

namespace gargosy_update {

struct Args {
  DWORD pid = 0;
  std::wstring root;         // the Gargosy folder
  std::wstring from;         // the unpacked new version (userdata\app\update\Gargosy)
  std::wstring version;      // the new version, for the window
  std::wstring old_version;  // passed back as --updated-from=
  std::vector<std::wstring> pass_on;  // Gargosy's own arguments, after "--"
  DWORD wait_seconds = 60;
  bool silent = false;  // no window and no message box (tests)
};

// Parses GargosyUpdate.exe's command line (argv[0] is the exe). False with
// [error] set when something required is missing.
bool ParseArgs(const std::vector<std::wstring>& argv, Args& out, std::wstring& error);

// Whether [rel] may be on the list: relative, no "." or "..", no drive or
// stream (':'), no trailing dot or space, and not in the user's folders
// (also not through an 8.3 name such as USERDA~1).
bool IsSafeRelative(const std::wstring& rel);

// Reads app-files.txt (UTF-8, CRLF or LF). False with [error] when it can't
// be read or a line isn't safe. A missing file is an error too; the caller
// decides whether that matters.
bool ReadAppFiles(const std::wstring& path, std::vector<std::wstring>& out, std::wstring& error);

// [arg] quoted for a Windows command line (CommandLineToArgvW's rules).
std::wstring QuoteArg(const std::wstring& arg);

// Appends timestamped UTF-8 lines to userdata\app\update\update.log.
class Log {
 public:
  explicit Log(std::wstring path) : path_(std::move(path)) {}
  void Line(const std::wstring& text) const;

 private:
  std::wstring path_;
};

enum class Outcome {
  kUpdated,     // the new files are in place
  kRefused,     // a list or the download is wrong: nothing was moved
  kRolledBack,  // something failed half way: the old files are back
};

using Progress = std::function<void(size_t done, size_t total, const std::wstring& what)>;

// Moves the current app files into userdata\app\update\previous\ and copies
// the new ones in, putting everything back when a step fails. [error] says
// why when the outcome isn't kUpdated.
Outcome Apply(const Args& args, const Log& log, const Progress& progress, std::wstring& error);

// Waits for Gargosy (args.pid) to exit. False when it's still running after
// args.wait_seconds.
bool WaitForGargosy(const Args& args);

// Starts root\Gargosy.exe with [extra] after the passed-on arguments.
bool StartGargosy(const Args& args, const std::wstring& extra);

}  // namespace gargosy_update
