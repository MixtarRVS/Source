#include "DesktopHost.hpp"

#include "DesktopModel.hpp"

#include <RmlUi/Core.h>
#include <RmlUi_Backend.h>

namespace mixtar::ui {
namespace {

const Rml::Vector2i kInitialWindowSize{1600, 900};

bool HandleGlobalKey(
    Rml::Context*,
    Rml::Input::KeyIdentifier key,
    int,
    float,
    bool priority
) {
    if (priority && key == Rml::Input::KI_ESCAPE) {
        Backend::RequestExit();
        return false;
    }

    return true;
}

} // namespace

int RunDesktop(const std::filesystem::path& resource_directory) {
    if (!Backend::Initialize("MixtarRVS", kInitialWindowSize.x, kInitialWindowSize.y, true)) {
        return 1;
    }

    Rml::SetSystemInterface(Backend::GetSystemInterface());
    Rml::SetRenderInterface(Backend::GetRenderInterface());

    if (!Rml::Initialise()) {
        Backend::Shutdown();
        return 2;
    }

    Rml::Context* context = Rml::CreateContext("mixtar-desktop", kInitialWindowSize);
    if (!context) {
        Rml::Shutdown();
        Backend::Shutdown();
        return 3;
    }

    const std::filesystem::path font_path = resource_directory / "LatoLatin-Regular.ttf";
    if (!Rml::LoadFontFace(font_path.string())) {
        Rml::Shutdown();
        Backend::Shutdown();
        return 4;
    }

    int result = 0;
    {
        DesktopModel model;
        if (!model.Bind(*context)) {
            result = 5;
        } else {
            const std::filesystem::path document_path = resource_directory / "Desktop.rml";
            Rml::ElementDocument* document = context->LoadDocument(document_path.string());
            if (!document) {
                result = 6;
            } else {
                document->Show();

                constexpr double clock_tick_seconds = 1.0;
                while (Backend::ProcessEvents(context, HandleGlobalKey, true)) {
                    model.UpdateClock();
                    context->Update();
                    context->RequestNextUpdate(clock_tick_seconds);

                    Backend::BeginFrame();
                    context->Render();
                    Backend::PresentFrame();
                }

                document->Close();
            }
        }
    }

    Rml::Shutdown();
    Backend::Shutdown();
    return result;
}

} // namespace mixtar::ui
