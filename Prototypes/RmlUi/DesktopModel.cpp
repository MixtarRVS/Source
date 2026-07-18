#include "DesktopModel.hpp"

#include <array>
#include <ctime>
#include <utility>

namespace mixtar::ui {

bool DesktopModel::Bind(Rml::Context& context) {
    clock_ = CurrentClock();

    Rml::DataModelConstructor constructor = context.CreateDataModel("desktop");
    if (!constructor) {
        return false;
    }

    constructor.Bind("clock", &clock_);
    constructor.Bind("time", &clock_);
    constructor.Bind("focused_window", &focused_window_);
    constructor.Bind("active_window", &focused_window_);
    constructor.Bind("start_open", &start_menu_open_);
    constructor.Bind("start_menu_open", &start_menu_open_);
    constructor.Bind("start_menu_visible", &start_menu_open_);
    constructor.Bind("start_menu_class", &start_menu_class_);
    constructor.Bind("start_state", &start_menu_class_);

    const auto dismiss_start = [this](
                                   Rml::DataModelHandle,
                                   Rml::Event&,
                                   const Rml::VariantList&
                               ) { SetStartMenuOpen(false); };

    const auto toggle_start = [this](
                                  Rml::DataModelHandle,
                                  Rml::Event&,
                                  const Rml::VariantList&
                              ) { SetStartMenuOpen(!start_menu_open_); };

    constructor.BindEventCallback("toggle_start", toggle_start);
    constructor.BindEventCallback("toggle_start_menu", toggle_start);
    constructor.BindEventCallback("focus", dismiss_start);
    constructor.BindEventCallback("focus_window", dismiss_start);
    constructor.BindEventCallback("activate", dismiss_start);
    constructor.BindEventCallback("activate_window", dismiss_start);
    constructor.BindEventCallback("minimize", dismiss_start);
    constructor.BindEventCallback("minimize_window", dismiss_start);
    constructor.BindEventCallback("maximize", dismiss_start);
    constructor.BindEventCallback("maximize_window", dismiss_start);
    constructor.BindEventCallback("close", dismiss_start);
    constructor.BindEventCallback("close_window", dismiss_start);

    model_ = constructor.GetModelHandle();
    next_clock_update_ = std::chrono::steady_clock::now();
    return true;
}

void DesktopModel::UpdateClock() {
    const auto now = std::chrono::steady_clock::now();
    if (now < next_clock_update_) {
        return;
    }

    next_clock_update_ = now + std::chrono::milliseconds(200);
    Rml::String new_clock = CurrentClock();
    if (new_clock == clock_) {
        return;
    }

    clock_ = std::move(new_clock);
    model_.DirtyVariable("clock");
    model_.DirtyVariable("time");
}

void DesktopModel::SetStartMenuOpen(bool open) {
    if (start_menu_open_ == open) {
        return;
    }

    start_menu_open_ = open;
    start_menu_class_ = open ? "start-menu open" : "start-menu";

    model_.DirtyVariable("start_open");
    model_.DirtyVariable("start_menu_open");
    model_.DirtyVariable("start_menu_visible");
    model_.DirtyVariable("start_menu_class");
    model_.DirtyVariable("start_state");
}

Rml::String DesktopModel::CurrentClock() {
    const std::time_t timestamp = std::time(nullptr);
    const std::tm* local_time = std::localtime(&timestamp);
    if (!local_time) {
        return "--:--:--";
    }

    std::array<char, 9> text{};
    if (std::strftime(text.data(), text.size(), "%H:%M:%S", local_time) == 0) {
        return "--:--:--";
    }

    return text.data();
}

} // namespace mixtar::ui
