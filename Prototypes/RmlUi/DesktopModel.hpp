#pragma once

#include <RmlUi/Core.h>

#include <chrono>

namespace mixtar::ui {

class DesktopModel final {
public:
    bool Bind(Rml::Context& context);
    void UpdateClock();

private:
    void SetStartMenuOpen(bool open);
    static Rml::String CurrentClock();

    Rml::DataModelHandle model_;
    Rml::String clock_;
    Rml::String focused_window_{"terminal"};
    Rml::String start_menu_class_{"start-menu"};
    bool start_menu_open_ = false;
    std::chrono::steady_clock::time_point next_clock_update_{};
};

} // namespace mixtar::ui
