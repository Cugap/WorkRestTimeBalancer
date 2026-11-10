#include "notification_shortcut.h"

#include <windows.h>

#include <objidl.h>
#include <propkey.h>
#include <propsys.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <string>

namespace {

// Должен совпадать с WindowsInitializationSettings.appUserModelId в
// app/lib/src/notifications/rest_notifications.dart.
constexpr wchar_t kAppUserModelId[] = L"Com.Cugap.WorkRestTimeBalancer";
constexpr wchar_t kShortcutName[] = L"WorkRestTimeBalancer.lnk";

std::wstring StartMenuShortcutPath() {
  PWSTR programs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs))) {
    return std::wstring();
  }
  std::wstring path(programs);
  ::CoTaskMemFree(programs);
  path += L"\\";
  path += kShortcutName;
  return path;
}

// Windows отбрасывает запланированные toast'ы приложения без MSIX-идентичности,
// если у него нет ярлыка в меню «Пуск» с System.AppUserModel.ID: немедленные
// уведомления показываются, а плановые молча теряются. Ярлык обычно создаёт
// установщик, у debug-сборки его нет, поэтому раннер создаёт ярлык сам.
void SetShortcutProperties(IShellLinkW* link) {
  wchar_t exe_path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }
  link->SetPath(exe_path);
  std::wstring directory(exe_path);
  const std::wstring::size_type separator = directory.find_last_of(L"\\/");
  if (separator != std::wstring::npos) {
    link->SetWorkingDirectory(directory.substr(0, separator).c_str());
  }

  IPropertyStore* store = nullptr;
  if (FAILED(link->QueryInterface(IID_IPropertyStore,
                                  reinterpret_cast<void**>(&store)))) {
    return;
  }
  PROPVARIANT value;
  ::PropVariantInit(&value);
  if (SUCCEEDED(::InitPropVariantFromString(kAppUserModelId, &value))) {
    PROPERTYKEY key = PKEY_AppUserModel_ID;
    store->SetValue(key, value);
    store->Commit();
  }
  ::PropVariantClear(&value);
  store->Release();
}

}  // namespace

void EnsureNotificationShortcut() {
  const std::wstring shortcut_path = StartMenuShortcutPath();
  if (shortcut_path.empty()) {
    return;
  }

  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IShellLinkW,
                                reinterpret_cast<void**>(&link)))) {
    return;
  }
  SetShortcutProperties(link);

  IPersistFile* file = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_IPersistFile,
                                     reinterpret_cast<void**>(&file)))) {
    file->Save(shortcut_path.c_str(), TRUE);
    file->Release();
  }
  link->Release();
}
