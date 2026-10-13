# GargosyUpdate.exe (issue #16): swaps Gargosy's app files after it exits.
# Plain Win32, the C runtime linked in (no VC++ redistributable), installed
# beside Gargosy.exe. Also builds on its own for tool/test_updater.ps1:
#   cmake -S windows/updater -B build/updater && cmake --build build/updater --config Release
cmake_minimum_required(VERSION 3.15)
project(gargosy_update LANGUAGES CXX)

add_executable(GargosyUpdate WIN32 main.cpp updater.cpp updater.rc)
target_compile_features(GargosyUpdate PRIVATE cxx_std_17)
target_compile_definitions(GargosyUpdate PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
if(MSVC)
  target_compile_options(GargosyUpdate PRIVATE /W4 /EHsc /utf-8)
  # The static C runtime: the copy that runs from userdata\app\update has no
  # VC++ DLLs beside it. Flutter's project enables C++ before policy CMP0091,
  # so its /MD is already in the flags and the property alone isn't enough:
  # /MT after it wins (warning D9025, harmless).
  set_property(TARGET GargosyUpdate PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  target_compile_options(GargosyUpdate PRIVATE $<$<CONFIG:Debug>:/MTd> $<$<NOT:$<CONFIG:Debug>>:/MT>)
else()
  target_link_options(GargosyUpdate PRIVATE -municode -static)
endif()
target_link_libraries(GargosyUpdate PRIVATE comctl32 shell32)
