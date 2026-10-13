# sigil.dll for the tests (tool/build_sigil.ps1), built as the app builds it
# (windows/sigil.cmake), into build\sigil\Release.
cmake_minimum_required(VERSION 3.18)
project(gargosy_sigil C)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
set(SIGIL_BINARY_DIR "${CMAKE_BINARY_DIR}/sigil")
include("${CMAKE_CURRENT_SOURCE_DIR}/../../windows/sigil.cmake")
