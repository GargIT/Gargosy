#include "updater.h"

#include <algorithm>
#include <cwctype>
#include <set>

namespace gargosy_update {
namespace {

const wchar_t* const kProtected[] = {L"roms", L"emulators", L"bios", L"userdata"};

std::wstring Lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return s;
}

std::vector<std::wstring> SplitPath(const std::wstring& rel) {
  std::vector<std::wstring> parts;
  std::wstring part;
  for (wchar_t c : rel) {
    if (c == L'\\' || c == L'/') {
      parts.push_back(part);
      part.clear();
    } else {
      part.push_back(c);
    }
  }
  parts.push_back(part);
  return parts;
}

std::wstring Join(const std::wstring& dir, const std::wstring& rel) {
  if (dir.empty()) return rel;
  const wchar_t last = dir.back();
  return (last == L'\\' || last == L'/') ? dir + rel : dir + L"\\" + rel;
}

std::wstring Parent(const std::wstring& path) {
  const size_t i = path.find_last_of(L"\\/");
  return i == std::wstring::npos ? std::wstring() : path.substr(0, i);
}

bool IsFile(const std::wstring& path) {
  const DWORD a = GetFileAttributesW(path.c_str());
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

bool IsDir(const std::wstring& path) {
  const DWORD a = GetFileAttributesW(path.c_str());
  return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}

bool MakeDirs(const std::wstring& dir) {
  if (dir.empty() || IsDir(dir)) return true;
  if (!MakeDirs(Parent(dir))) return false;
  return CreateDirectoryW(dir.c_str(), nullptr) || GetLastError() == ERROR_ALREADY_EXISTS;
}

void DeleteTree(const std::wstring& dir) {
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW(Join(dir, L"*").c_str(), &data);
  if (find != INVALID_HANDLE_VALUE) {
    do {
      const std::wstring name = data.cFileName;
      if (name == L"." || name == L"..") continue;
      const std::wstring path = Join(dir, name);
      if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        DeleteTree(path);
      } else {
        SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(path.c_str());
      }
    } while (FindNextFileW(find, &data));
    FindClose(find);
  }
  RemoveDirectoryW(dir.c_str());
}

// Removes [dir] and its parents up to (not including) [stop] while they're empty.
void RemoveEmptyDirs(std::wstring dir, const std::wstring& stop) {
  const std::wstring stop_lower = Lower(stop);
  while (!dir.empty() && Lower(dir) != stop_lower && dir.size() > stop.size()) {
    if (!RemoveDirectoryW(dir.c_str())) return;  // not empty, or gone
    dir = Parent(dir);
  }
}

std::wstring Win32Message(DWORD code) {
  wchar_t* buffer = nullptr;
  const DWORD n = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                 nullptr, code, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  std::wstring text = n ? std::wstring(buffer, n) : L"error " + std::to_wstring(code);
  if (buffer) LocalFree(buffer);
  while (!text.empty() && (text.back() == L'\r' || text.back() == L'\n' || text.back() == L' ' || text.back() == L'.')) {
    text.pop_back();
  }
  return text;
}

bool Retryable(DWORD code) {
  return code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION || code == ERROR_ACCESS_DENIED;
}

// Runs [step] until it succeeds, retrying a locked file for about 5 s.
// On failure [code] holds the last error.
template <typename Step>
bool WithRetry(Step step, DWORD& code) {
  for (int attempt = 0;; ++attempt) {
    if (step()) return true;
    code = GetLastError();
    if (!Retryable(code) || attempt >= 20) return false;
    Sleep(250);
  }
}

bool MoveFile(const std::wstring& from, const std::wstring& to, DWORD& code) {
  return WithRetry([&] { return MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING) != 0; }, code);
}

bool CopyOne(const std::wstring& from, const std::wstring& to, DWORD& code) {
  return WithRetry([&] { return CopyFileW(from.c_str(), to.c_str(), FALSE) != 0; }, code);
}

bool DeleteOne(const std::wstring& path, DWORD& code) {
  return WithRetry([&] { return DeleteFileW(path.c_str()) != 0; }, code);
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return std::string();
  const int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n, nullptr, nullptr);
  return out;
}

}  // namespace

bool ParseArgs(const std::vector<std::wstring>& argv, Args& out, std::wstring& error) {
  for (size_t i = 1; i < argv.size(); ++i) {
    const std::wstring& a = argv[i];
    auto value = [&](std::wstring& into) {
      if (i + 1 >= argv.size()) return false;
      into = argv[++i];
      return true;
    };
    std::wstring v;
    if (a == L"--") {
      out.pass_on.assign(argv.begin() + static_cast<std::ptrdiff_t>(i) + 1, argv.end());
      break;
    } else if (a == L"--silent") {
      out.silent = true;
    } else if (a == L"--pid" && value(v)) {
      out.pid = static_cast<DWORD>(wcstoul(v.c_str(), nullptr, 10));
    } else if (a == L"--wait-seconds" && value(v)) {
      out.wait_seconds = static_cast<DWORD>(wcstoul(v.c_str(), nullptr, 10));
    } else if (a == L"--root" && value(v)) {
      out.root = v;
    } else if (a == L"--from" && value(v)) {
      out.from = v;
    } else if (a == L"--version" && value(v)) {
      out.version = v;
    } else if (a == L"--old-version" && value(v)) {
      out.old_version = v;
    } else {
      error = L"Unknown or incomplete argument: " + a;
      return false;
    }
  }
  if (out.pid == 0 || out.root.empty() || out.from.empty()) {
    error = L"Usage: GargosyUpdate.exe --pid <pid> --root <Gargosy folder> --from <unpacked update> "
            L"[--version <v>] [--old-version <v>] [--wait-seconds <s>] [--silent] -- <Gargosy's arguments>";
    return false;
  }
  while (out.root.size() > 3 && (out.root.back() == L'\\' || out.root.back() == L'/')) out.root.pop_back();
  return true;
}

bool IsSafeRelative(const std::wstring& rel) {
  if (rel.empty() || rel.front() == L'\\' || rel.front() == L'/') return false;
  if (rel.find_first_of(L":*?\"<>|") != std::wstring::npos) return false;
  const std::vector<std::wstring> parts = SplitPath(rel);
  for (const std::wstring& part : parts) {
    if (part.empty() || part == L"." || part == L"..") return false;
    if (part.back() == L'.' || part.back() == L' ') return false;  // Windows drops them: "userdata." is userdata
  }
  const std::wstring first = Lower(parts.front());
  if (first.find(L'~') != std::wstring::npos) return false;  // an 8.3 name could be one of the folders below
  for (const wchar_t* folder : kProtected) {
    if (first == folder) return false;
  }
  return true;
}

bool ReadAppFiles(const std::wstring& path, std::vector<std::wstring>& out, std::wstring& error) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    error = L"Can't read " + path + L": " + Win32Message(GetLastError());
    return false;
  }
  std::string bytes;
  char buffer[64 * 1024];
  DWORD read = 0;
  while (ReadFile(file, buffer, sizeof(buffer), &read, nullptr) && read > 0) bytes.append(buffer, read);
  CloseHandle(file);
  if (bytes.size() >= 3 && bytes.compare(0, 3, "\xEF\xBB\xBF") == 0) bytes.erase(0, 3);

  out.clear();
  std::set<std::wstring> seen;
  const std::wstring text = Utf8ToWide(bytes);
  size_t start = 0;
  while (start <= text.size()) {
    size_t end = text.find(L'\n', start);
    if (end == std::wstring::npos) end = text.size();
    std::wstring line = text.substr(start, end - start);
    start = end + 1;
    while (!line.empty() && (line.back() == L'\r' || line.back() == L' ' || line.back() == L'\t')) line.pop_back();
    size_t lead = 0;
    while (lead < line.size() && (line[lead] == L' ' || line[lead] == L'\t')) ++lead;
    line.erase(0, lead);
    if (line.empty()) continue;
    std::replace(line.begin(), line.end(), L'/', L'\\');
    if (!IsSafeRelative(line)) {
      error = L"app-files.txt names a path that isn't allowed: " + line;
      return false;
    }
    if (seen.insert(Lower(line)).second) out.push_back(line);
  }
  if (out.empty()) {
    error = L"app-files.txt is empty: " + path;
    return false;
  }
  return true;
}

std::wstring QuoteArg(const std::wstring& arg) {
  if (!arg.empty() && arg.find_first_of(L" \t\n\v\"") == std::wstring::npos) return arg;
  std::wstring out = L"\"";
  for (size_t i = 0;; ++i) {
    size_t slashes = 0;
    while (i < arg.size() && arg[i] == L'\\') {
      ++slashes;
      ++i;
    }
    if (i == arg.size()) {
      out.append(slashes * 2, L'\\');  // they come before the closing quote
      break;
    }
    if (arg[i] == L'"') {
      out.append(slashes * 2 + 1, L'\\');
    } else {
      out.append(slashes, L'\\');
    }
    out.push_back(arg[i]);
  }
  out.push_back(L'"');
  return out;
}

void Log::Line(const std::wstring& text) const {
  SYSTEMTIME t;
  GetLocalTime(&t);
  wchar_t stamp[32];
  swprintf_s(stamp, L"%04u-%02u-%02u %02u:%02u:%02u  ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
  MakeDirs(Parent(path_));
  HANDLE file = CreateFileW(path_.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  const std::string line = WideToUtf8(std::wstring(stamp) + text) + "\r\n";
  DWORD written = 0;
  WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written, nullptr);
  CloseHandle(file);
}

bool WaitForGargosy(const Args& args) {
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, args.pid);
  // No such process: it's gone. Anything else (access denied: Gargosy runs
  // elevated) means it can't be waited for, and nothing may be swapped yet.
  if (!process) return GetLastError() == ERROR_INVALID_PARAMETER;
  const DWORD result = WaitForSingleObject(process, args.wait_seconds * 1000);
  CloseHandle(process);
  return result == WAIT_OBJECT_0;
}

bool StartGargosy(const Args& args, const std::wstring& extra) {
  const std::wstring exe = Join(args.root, L"Gargosy.exe");
  std::wstring command = QuoteArg(exe);
  for (const std::wstring& a : args.pass_on) command += L" " + QuoteArg(a);
  if (!extra.empty()) command += L" " + QuoteArg(extra);
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION info = {};
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr, args.root.c_str(), &startup, &info)) {
    return false;
  }
  CloseHandle(info.hThread);
  CloseHandle(info.hProcess);
  return true;
}

Outcome Apply(const Args& args, const Log& log, const Progress& progress, std::wstring& error) {
  const std::wstring& root = args.root;
  const std::wstring previous = Join(root, L"userdata\\app\\update\\previous");

  // 1. Both lists, checked before anything moves.
  std::vector<std::wstring> fresh;
  if (!ReadAppFiles(Join(args.from, L"app-files.txt"), fresh, error)) return Outcome::kRefused;
  if (std::none_of(fresh.begin(), fresh.end(), [](const std::wstring& f) { return Lower(f) == L"gargosy.exe"; })) {
    error = L"The new app-files.txt doesn't list Gargosy.exe.";
    return Outcome::kRefused;
  }
  for (const std::wstring& f : fresh) {
    if (!IsFile(Join(args.from, f))) {
      error = L"The update has no " + f + L".";
      return Outcome::kRefused;
    }
  }
  std::vector<std::wstring> current;
  const std::wstring current_list = Join(root, L"app-files.txt");
  if (IsFile(current_list)) {
    if (!ReadAppFiles(current_list, current, error)) return Outcome::kRefused;
  } else {
    log.Line(L"No app-files.txt in the Gargosy folder: only files the new version lists are replaced.");
  }

  std::vector<std::wstring> all = current;
  {
    std::set<std::wstring> seen;
    for (const std::wstring& f : current) seen.insert(Lower(f));
    for (const std::wstring& f : fresh) {
      if (seen.insert(Lower(f)).second) all.push_back(f);
    }
  }

  // An earlier update that couldn't put every old file back left them in
  // previous\ with a marker: they're the only copy, so nothing goes on.
  const std::wstring stuck = Join(previous, L".gargosy-incomplete");
  if (IsFile(stuck)) {
    error = L"An earlier update couldn't put every old file back: they are in userdata\\app\\update\\previous. "
            L"Copy them into the Gargosy folder and delete that folder, then update again.";
    return Outcome::kRefused;
  }
  if (IsDir(previous)) DeleteTree(previous);
  const size_t total = all.size() + fresh.size();
  size_t done = 0;

  std::vector<std::wstring> moved;
  std::vector<std::wstring> copied;
  auto roll_back = [&](const std::wstring& why) {
    error = why;
    log.Line(L"Failed: " + why + L" Putting the old version back.");
    DWORD code = 0;
    for (auto it = copied.rbegin(); it != copied.rend(); ++it) {
      if (!DeleteOne(Join(root, *it), code)) log.Line(L"Couldn't remove the new " + *it + L": " + Win32Message(code));
    }
    bool all_back = true;
    for (auto it = moved.rbegin(); it != moved.rend(); ++it) {
      const std::wstring to = Join(root, *it);
      MakeDirs(Parent(to));
      if (!MoveFile(Join(previous, *it), to, code)) {
        all_back = false;
        log.Line(L"Couldn't put back " + *it + L" (it is in userdata\\app\\update\\previous): " + Win32Message(code));
      }
    }
    if (!all_back) {
      // The next update must not delete them (see the start of Apply).
      HANDLE marker = CreateFileW(Join(previous, L".gargosy-incomplete").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
      if (marker != INVALID_HANDLE_VALUE) CloseHandle(marker);
    }
    log.Line(all_back ? L"Failed: " + why + L" The old version is back."
                      : L"Failed: " + why + L" Some old files are still in userdata\\app\\update\\previous: copy them back by hand.");
    return Outcome::kRolledBack;
  };

  // 2. The current app files go aside, so a failure can put them back.
  log.Line(L"Moving the current files aside (" + std::to_wstring(all.size()) + L").");
  for (const std::wstring& f : all) {
    progress(++done, total, f);
    const std::wstring from = Join(root, f);
    if (!IsFile(from)) continue;
    const std::wstring to = Join(previous, f);
    DWORD code = 0;
    if (!MakeDirs(Parent(to)) || !MoveFile(from, to, code)) {
      return roll_back(f + L" couldn't be moved: " + Win32Message(code ? code : GetLastError()) + L".");
    }
    moved.push_back(f);
  }

  // 3. The new files in.
  log.Line(L"Copying the new files (" + std::to_wstring(fresh.size()) + L").");
  for (const std::wstring& f : fresh) {
    progress(++done, total, f);
    const std::wstring to = Join(root, f);
    DWORD code = 0;
    if (!MakeDirs(Parent(to)) || !CopyOne(Join(args.from, f), to, code)) {
      const DWORD failed = code ? code : GetLastError();
      // A half-written file isn't in `copied` yet: it goes before the rollback.
      DWORD ignored = 0;
      if (IsFile(to)) DeleteOne(to, ignored);
      return roll_back(f + L" couldn't be written: " + Win32Message(failed) + L".");
    }
    copied.push_back(f);
  }

  // 4. Folders left empty by files the new version dropped.
  {
    std::set<std::wstring> kept;
    for (const std::wstring& f : fresh) kept.insert(Lower(f));
    for (const std::wstring& f : current) {
      if (kept.count(Lower(f))) continue;
      const std::wstring dir = Parent(Join(root, f));
      if (Lower(dir) != Lower(root)) RemoveEmptyDirs(dir, root);
    }
  }
  log.Line(L"Updated to " + args.version + L".");
  return Outcome::kUpdated;
}

}  // namespace gargosy_update
