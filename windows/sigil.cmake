# argosy-sigil (third_party, pinned): game ids and save units, as sigil.dll.
# One definition for both builds that make it: the app (windows/CMakeLists.txt)
# and the tests' copy (tool/sigil/CMakeLists.txt, run by tool/build_sigil.ps1).
# Set SIGIL_BINARY_DIR before including.
set(SIGIL_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/argosy-sigil")
set(SIGIL_BUILD_SHARED ON CACHE BOOL "" FORCE)
set(SIGIL_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(SIGIL_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${SIGIL_SOURCE_DIR}" "${SIGIL_BINARY_DIR}")

# MSVC's optimizer turns sigil v1.0.0's sigil_ps2_verify into "not found"
# (at /O1 and /O2, VS 2022 and VS 18): every PS2 memory card restore then
# fails its own read-back with "I/O error". card_ps2.c is compiled
# unoptimized until that's fixed upstream; check again when the submodule
# moves (test/unit/sigil_ps2_card_restore_test.dart fails without this).
# MSVC warns D9025 (/Od overrides /O2) for that one file.
if(MSVC)
  set_source_files_properties("${SIGIL_SOURCE_DIR}/src/card_ps2.c"
    DIRECTORY "${SIGIL_SOURCE_DIR}"
    PROPERTIES COMPILE_OPTIONS "/Od")
endif()
