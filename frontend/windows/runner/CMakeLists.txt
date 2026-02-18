cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

<<<<<<< HEAD
# logic to determine if we are in debug or release mode for rust
string(TOLOWER "${CMAKE_BUILD_TYPE}" CMAKE_BUILD_TYPE_LOWER)
if (CMAKE_BUILD_TYPE_LOWER MATCHES "release" OR CMAKE_BUILD_TYPE_LOWER MATCHES "relwithdebinfo" OR CMAKE_BUILD_TYPE_LOWER MATCHES "minsizerel")
    set(RUST_BUILD_MODE "release")
else()
    set(RUST_BUILD_MODE "debug")
endif()

# Copy the Rust DLL to the executable directory
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${CMAKE_SOURCE_DIR}/../../target/${RUST_BUILD_MODE}/areyoughost_core.dll"
  "$<TARGET_FILE_DIR:${BINARY_NAME}>/areyoughost_core.dll"
)
=======
# --- ADDED BY ANTIGRAVITY ---
# Copy the Rust DLL to the build directory
set(RUST_LIB_NAME "areyoughost_core.dll")
# Assuming CMake is run from frontend/windows
# Core is part of a workspace, so artifacts are in root/target, not core/target
# CMAKE_SOURCE_DIR = frontend/windows, so ../../target = areyoughost/target
set(RUST_BUILD_DIR "${CMAKE_SOURCE_DIR}/../../target")

# Use generator expression to handle Multi-Config generators (VS)
# Rust uses lowercase 'debug'/'release', VS uses 'Debug'/'Release'
set(RUST_LIB_SOURCE "${RUST_BUILD_DIR}/$<LOWER_CASE:$<CONFIG>>/${RUST_LIB_NAME}")

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${RUST_LIB_SOURCE}"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/${RUST_LIB_NAME}"
    COMMENT "Copying ${RUST_LIB_NAME} to output directory"
)
# ----------------------------
>>>>>>> fdf07d5336be107759e9db9c0ba7786f6ecc00c9
