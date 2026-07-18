#include "DesktopHost.hpp"

#include <filesystem>
#include <string>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace {

std::filesystem::path ResourceDirectory() {
    wchar_t executable_path[32768]{};
    const DWORD length = GetModuleFileNameW(
        nullptr,
        executable_path,
        static_cast<DWORD>(sizeof(executable_path) / sizeof(executable_path[0]))
    );

    if (length == 0 || length == sizeof(executable_path) / sizeof(executable_path[0])) {
        return std::filesystem::current_path() / "Resources";
    }

    return std::filesystem::path(std::wstring(executable_path, length)).parent_path() / "Resources";
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    const int result = mixtar::ui::RunDesktop(ResourceDirectory());
    if (result != 0) {
        const std::wstring message =
            L"MixtarRVS could not start. Initialization stage: " + std::to_wstring(result) + L".";
        MessageBoxW(nullptr, message.c_str(), L"MixtarRVS", MB_OK | MB_ICONERROR);
    }

    return result;
}

#else

int main(int argc, char** argv) {
    const std::filesystem::path executable =
        argc > 0 ? std::filesystem::absolute(argv[0]) : std::filesystem::current_path() / "MixtarRVS";
    return mixtar::ui::RunDesktop(executable.parent_path() / "Resources");
}

#endif
