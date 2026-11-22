#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// 为进程创建控制台，并将宿主程序和 Flutter 库的 stdout、stderr 重定向到控制台。
void CreateAndAttachConsole();

// 将以空字符结尾的 UTF-16 wchar_t* 转为 UTF-8 std::string，失败时返回空字符串。
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// 以 UTF-8 std::vector<std::string> 返回命令行参数，失败时返回空列表。
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
