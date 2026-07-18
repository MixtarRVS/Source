cmake_minimum_required(VERSION 3.24)

project(MixtarRmlUiDesktop VERSION 0.1.0 LANGUAGES C CXX)

include(FetchContent)

# Source refs are cache entries on purpose. SDL follows its stable release
# channel, while projects without a stable channel use a reviewed release tag.
set(MIXTAR_RMLUI_REF "6.2" CACHE STRING "RmlUi release used by the desktop host")
set(MIXTAR_SDL_REF "release-3.4.x" CACHE STRING "SDL stable release channel")
set(MIXTAR_SDL_IMAGE_REF "release-3.4.x" CACHE STRING "SDL_image stable release channel")
set(MIXTAR_FREETYPE_REF "VER-2-13-3" CACHE STRING "FreeType release used by RmlUi")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build a self-contained executable" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# FreeType: only TrueType/OpenType loading is needed by this prototype.
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
FetchContent_Declare(
    freetype
    GIT_REPOSITORY https://github.com/freetype/freetype.git
    GIT_TAG ${MIXTAR_FREETYPE_REF}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(freetype)

if(NOT TARGET Freetype::Freetype)
    if(TARGET freetype)
        add_library(Freetype::Freetype ALIAS freetype)
    else()
        message(FATAL_ERROR "FreeType did not provide a usable CMake target")
    endif()
endif()

# SDL is only the portable window/input bridge. It is not the Mixtar UI API.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    sdl
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG ${MIXTAR_SDL_REF}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(sdl)

# RmlUi's reference SDL/OpenGL backend uses SDL_image for optional textures.
# The current desktop has no bitmap textures, so costly external codecs stay off.
set(SDLIMAGE_SHARED OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_STATIC ON CACHE BOOL "" FORCE)
set(SDLIMAGE_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_TESTS OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_INSTALL OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_VENDORED OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_DEPS_SHARED OFF CACHE BOOL "" FORCE)
foreach(codec AVIF JPG JXL PNG SVG TIF WEBP)
    set(SDLIMAGE_${codec} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(
    sdl_image
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_image.git
    GIT_TAG ${MIXTAR_SDL_IMAGE_REF}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
    GIT_SUBMODULES ""
)
FetchContent_MakeAvailable(sdl_image)

# RmlUi creates its SDL::SDL and SDL_image::SDL_image compatibility targets
# from the SDL3 targets provided above.

set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
set(RMLUI_SHELL ON)
set(RMLUI_BACKEND "SDL_GL3" CACHE STRING "" FORCE)
set(RMLUI_FONT_ENGINE "freetype" CACHE STRING "" FORCE)
set(RMLUI_LUA_BINDINGS OFF CACHE BOOL "" FORCE)
set(RMLUI_LOTTIE_PLUGIN OFF CACHE BOOL "" FORCE)
set(RMLUI_SVG_PLUGIN OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    rmlui
    GIT_REPOSITORY https://github.com/mikke89/RmlUi.git
    GIT_TAG ${MIXTAR_RMLUI_REF}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(rmlui)

add_executable(
    mixtar_rmlui
    main.cpp
    DesktopHost.cpp
    DesktopHost.hpp
    DesktopModel.cpp
    DesktopModel.hpp
)

target_compile_features(mixtar_rmlui PRIVATE cxx_std_20)
target_link_libraries(
    mixtar_rmlui
    PRIVATE
        RmlUi::RmlUi
        rmlui_backend_SDL_GL3
)

if(MSVC)
    target_compile_options(mixtar_rmlui PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(mixtar_rmlui PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(MINGW)
    target_link_options(mixtar_rmlui PRIVATE -municode -static-libgcc -static-libstdc++)
endif()

set_target_properties(
    mixtar_rmlui
    PROPERTIES
        OUTPUT_NAME "MixtarRVS"
        WIN32_EXECUTABLE "${WIN32}"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

foreach(configuration Debug Release RelWithDebInfo MinSizeRel)
    string(TOUPPER "${configuration}" configuration_upper)
    set_target_properties(
        mixtar_rmlui
        PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${configuration_upper} "${CMAKE_BINARY_DIR}/bin"
    )
endforeach()

set(MIXTAR_RESOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/Desktop.rml"
    "${CMAKE_CURRENT_SOURCE_DIR}/Desktop.rcss"
    "${rmlui_SOURCE_DIR}/Samples/assets/LatoLatin-Regular.ttf"
)

add_custom_command(
    TARGET mixtar_rmlui
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:mixtar_rmlui>/Resources"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${MIXTAR_RESOURCES} "$<TARGET_FILE_DIR:mixtar_rmlui>/Resources"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${rmlui_SOURCE_DIR}/LICENSE.txt" "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses/RmlUi.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${rmlui_SOURCE_DIR}/Samples/assets/LICENSE.txt" "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses/RmlUi-Sample-Assets.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${sdl_SOURCE_DIR}/LICENSE.txt" "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses/SDL.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${sdl_image_SOURCE_DIR}/LICENSE.txt" "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses/SDL_image.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${freetype_SOURCE_DIR}/LICENSE.TXT" "$<TARGET_FILE_DIR:mixtar_rmlui>/Licenses/FreeType.txt"
    VERBATIM
)

install(TARGETS mixtar_rmlui RUNTIME DESTINATION . COMPONENT Runtime)
install(FILES ${MIXTAR_RESOURCES} DESTINATION Resources COMPONENT Runtime)
