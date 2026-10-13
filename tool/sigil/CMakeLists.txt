# sigil.dll for the tests (tool/build_sigil.ps1): argosy-sigil as the app
# builds it, with windows/sigil_msvc.cmake's fix, into build\sigil\Release.
cmake_minimum_required(VERSION 3.18)
project(gargosy_sigil C)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
set(SIGIL_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/argosy-sigil")
set(SIGIL_BUILD_SHARED ON CACHE BOOL "" FORCE)
set(SIGIL_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(SIGIL_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${SIGIL_SOURCE_DIR}" sigil)
include("${CMAKE_CURRENT_SOURCE_DIR}/../../windows/sigil_msvc.cmake")
