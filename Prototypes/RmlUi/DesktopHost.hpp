#pragma once

#include <filesystem>

namespace mixtar::ui {

// Starts the native RmlUi desktop and blocks until its window is closed.
// The returned value is zero on a clean shutdown and otherwise identifies the
// initialization stage that failed.
int RunDesktop(const std::filesystem::path& resource_directory);

} // namespace mixtar::ui
