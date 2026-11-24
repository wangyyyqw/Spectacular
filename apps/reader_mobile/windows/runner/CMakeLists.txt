cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 定义应用目标。更名应修改顶层 CMakeLists.txt 中的 BINARY_NAME，
# 请勿修改此处的值，否则 flutter run 将无法正常运行。
#
# 应用新增的源码文件均应加入此处。
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 应用标准构建设置；需要其他构建设置的应用可移除此调用。
apply_standard_settings(${BINARY_NAME})

# 添加构建版本的预处理器定义。
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# 禁用与 C++ 标准库函数冲突的 Windows 宏。
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 添加依赖库和头文件目录；应用专用依赖也应加入此处。
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# 执行 Flutter 工具负责的构建步骤，不可移除。
add_dependencies(${BINARY_NAME} flutter_assemble)
