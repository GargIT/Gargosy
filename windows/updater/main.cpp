// GargosyUpdate.exe: started by Gargosy (a copy in userdata\app\update\) to
// swap its app files once it has exited, then start it again (issue #16).
//
//   GargosyUpdate.exe --pid <pid> --root <Gargosy folder> --from <unpacked update>
//                     --version <new> --old-version <old> -- <Gargosy's arguments>
//
// Exit codes: 0 updated, 1 failed and rolled back, 2 Gargosy didn't exit
// (nothing changed, nothing started), 3 bad arguments, 4 refused (nothing moved).
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "updater.h"

using namespace gargosy_update;

namespace {

constexpr UINT kProgressMessage = WM_APP + 1;  // wParam done, lParam total
constexpr UINT kDoneMessage = WM_APP + 2;      // wParam exit code
constexpr wchar_t kTitle[] = L"Gargosy update";
constexpr wchar_t kClassName[] = L"GargosyUpdateWindow";

// Gargosy's dark theme (lib/ui/theme/tokens.dart).
constexpr COLORREF kBackground = RGB(0x10, 0x0C, 0x1C);
constexpr COLORREF kText = RGB(0xFF, 0xFF, 0xFF);
constexpr COLORREF kBar = RGB(0x8B, 0x74, 0xE8);

struct Window {
  HWND hwnd = nullptr;
  HWND label = nullptr;
  HWND bar = nullptr;
  HBRUSH background = nullptr;
  HFONT font = nullptr;
};

Window g_window;
Args g_args;
std::wstring g_error;

std::wstring LogPath(const std::wstring& root) { return root + L"\\userdata\\app\\update\\update.log"; }

// The whole update, on a worker thread when there is a window. Returns the exit code.
int Run(HWND notify) {
  const Log log(LogPath(g_args.root));
  log.Line(L"Updating Gargosy from " + g_args.old_version + L" to " + g_args.version + L" (in progress).");
  log.Line(L"Waiting for Gargosy (process " + std::to_wstring(g_args.pid) + L") to close.");
  if (!WaitForGargosy(g_args)) {
    g_error = L"Gargosy didn't close within " + std::to_wstring(g_args.wait_seconds) + L" seconds. Nothing was changed.";
    log.Line(L"Stopped: " + g_error);
    return 2;
  }
  const Progress progress = [notify](size_t done, size_t total, const std::wstring&) {
    if (notify) PostMessageW(notify, kProgressMessage, static_cast<WPARAM>(done), static_cast<LPARAM>(total));
  };
  switch (Apply(g_args, log, progress, g_error)) {
    case Outcome::kUpdated:
      return 0;
    case Outcome::kRefused:
      log.Line(L"Failed: " + g_error + L" Nothing was changed.");
      return 4;
    case Outcome::kRolledBack:
      return 1;
  }
  return 1;
}

// After the work: start Gargosy again (the new one, or the old one saying
// the update failed), unless it never closed.
int Finish(int code) {
  const Log log(LogPath(g_args.root));
  if (code == 0) {
    if (!StartGargosy(g_args, L"--updated-from=" + g_args.old_version)) log.Line(L"Couldn't start the new Gargosy.exe.");
    return 0;
  }
  if (code == 2) {
    if (!g_args.silent) MessageBoxW(g_window.hwnd, g_error.c_str(), kTitle, MB_OK | MB_ICONWARNING);
    return code;
  }
  if (!g_args.silent) {
    const std::wstring text = L"The update couldn't be installed.\n\n" + g_error +
                              L"\n\nGargosy starts again in the version you had. "
                              L"The details are in userdata\\app\\update\\update.log.";
    MessageBoxW(g_window.hwnd, text.c_str(), kTitle, MB_OK | MB_ICONERROR);
  }
  if (!StartGargosy(g_args, L"--update-failed")) log.Line(L"Couldn't start Gargosy.exe again.");
  return code;
}

DWORD WINAPI Worker(LPVOID) {
  const int code = Run(g_window.hwnd);
  PostMessageW(g_window.hwnd, kDoneMessage, static_cast<WPARAM>(code), 0);
  return 0;
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case kProgressMessage:
      SendMessageW(g_window.bar, PBM_SETRANGE32, 0, lparam);
      SendMessageW(g_window.bar, PBM_SETPOS, wparam, 0);
      return 0;
    case kDoneMessage:
      PostQuitMessage(Finish(static_cast<int>(wparam)));
      return 0;
    case WM_CTLCOLORSTATIC:
      SetTextColor(reinterpret_cast<HDC>(wparam), kText);
      SetBkColor(reinterpret_cast<HDC>(wparam), kBackground);
      return reinterpret_cast<LRESULT>(g_window.background);
    case WM_CLOSE:
      return 0;  // the update can't be stopped half way
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

bool CreateUpdateWindow(HINSTANCE instance) {
  INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_PROGRESS_CLASS};
  InitCommonControlsEx(&controls);
  g_window.background = CreateSolidBrush(kBackground);

  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.hbrBackground = g_window.background;
  wc.lpszClassName = kClassName;
  wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
  if (!RegisterClassExW(&wc)) return false;

  constexpr int kWidth = 440, kHeight = 150;
  RECT area = {0, 0, kWidth, kHeight};
  const DWORD style = WS_CAPTION | WS_SYSMENU;
  AdjustWindowRect(&area, style, FALSE);
  const int w = area.right - area.left, h = area.bottom - area.top;
  const int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2, y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;
  g_window.hwnd = CreateWindowExW(WS_EX_TOPMOST, kClassName, kTitle, style, x, y, w, h, nullptr, nullptr, instance, nullptr);
  if (!g_window.hwnd) return false;

  NONCLIENTMETRICSW metrics = {};
  metrics.cbSize = sizeof(metrics);
  SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0);
  metrics.lfMessageFont.lfHeight = -18;
  g_window.font = CreateFontIndirectW(&metrics.lfMessageFont);

  const std::wstring text = L"Updating Gargosy to " + (g_args.version.empty() ? std::wstring(L"the new version") : g_args.version) + L"…";
  g_window.label = CreateWindowExW(0, L"STATIC", text.c_str(), WS_CHILD | WS_VISIBLE, 24, 30, kWidth - 48, 28,
                                   g_window.hwnd, nullptr, instance, nullptr);
  g_window.bar = CreateWindowExW(0, PROGRESS_CLASSW, nullptr, WS_CHILD | WS_VISIBLE | PBS_SMOOTH, 24, 80, kWidth - 48, 18,
                                 g_window.hwnd, nullptr, instance, nullptr);
  SendMessageW(g_window.label, WM_SETFONT, reinterpret_cast<WPARAM>(g_window.font), TRUE);
  SendMessageW(g_window.bar, PBM_SETBARCOLOR, 0, kBar);
  SendMessageW(g_window.bar, PBM_SETBKCOLOR, 0, RGB(0x2A, 0x2A, 0x40));
  ShowWindow(g_window.hwnd, SW_SHOWNORMAL);
  UpdateWindow(g_window.hwnd);
  return true;
}

std::vector<std::wstring> CommandLineArgs() {
  std::vector<std::wstring> out;
  int count = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!argv) return out;
  for (int i = 0; i < count; ++i) out.emplace_back(argv[i]);
  LocalFree(argv);
  return out;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  std::wstring error;
  if (!ParseArgs(CommandLineArgs(), g_args, error)) {
    if (!g_args.silent) MessageBoxW(nullptr, error.c_str(), kTitle, MB_OK | MB_ICONERROR);
    return 3;
  }

  if (g_args.silent || !CreateUpdateWindow(instance)) {
    g_window.hwnd = nullptr;
    return Finish(Run(nullptr));
  }

  HANDLE worker = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
  if (!worker) return Finish(Run(nullptr));
  CloseHandle(worker);

  MSG msg;
  int code = 1;
  while (true) {
    const BOOL got = GetMessageW(&msg, nullptr, 0, 0);
    if (got == 0) {
      code = static_cast<int>(msg.wParam);
      break;
    }
    if (got == -1) break;
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  DestroyWindow(g_window.hwnd);
  if (g_window.font) DeleteObject(g_window.font);
  if (g_window.background) DeleteObject(g_window.background);
  return code;
}
