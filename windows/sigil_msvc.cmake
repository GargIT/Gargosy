# MSVC's optimizer turns argosy-sigil v1.0.0's sigil_ps2_verify into "not
# found" (at /O1 and /O2, VS 2022 and VS 18): every PS2 memory card restore
# then fails its own read-back with "I/O error". card_ps2.c is compiled
# unoptimized until that's fixed upstream. Used by windows/CMakeLists.txt and
# tool/sigil/CMakeLists.txt (tool/build_sigil.ps1).
if(MSVC)
  set_source_files_properties("${SIGIL_SOURCE_DIR}/src/card_ps2.c"
    DIRECTORY "${SIGIL_SOURCE_DIR}"
    PROPERTIES COMPILE_OPTIONS "/Od")
endif()
