#include <cstdlib>
#include <cstring>
#include <unordered_map>

#include "Config.hpp"
#include "Converter.hpp"
#include "Exception.hpp"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/writer.h"

#if defined(_WIN32)
#define READER_EXPORT __declspec(dllexport)
#else
#define READER_EXPORT __attribute__((visibility("default")))
#endif

using JsonWriter = rapidjson::Writer<rapidjson::StringBuffer>;
using Lengths = std::vector<size_t>;
using Spans = std::vector<std::pair<size_t, size_t>>;

// 准备任务各自运行在独立 isolate 线程，且可能被随时取消；转换器按线程
// 缓存，避免跨线程共享导致的阻塞，也不依赖会被中断的全局锁。
static opencc::ConverterPtr ConverterFor(const std::string& path) {
  thread_local std::unordered_map<std::string, opencc::ConverterPtr> converters;
  auto found = converters.find(path);
  if (found != converters.end()) return found->second;
  auto converter = opencc::Config().NewFromFile(path);
  converters.emplace(path, converter);
  return converter;
}

static Lengths Utf16Widths(const std::string& text) {
  Lengths widths;
  for (size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<unsigned char>(text[offset]);
    const size_t bytes = first < 0x80 ? 1 : first < 0xe0 ? 2 : first < 0xf0 ? 3 : 4;
    widths.push_back(bytes == 4 ? 2 : 1);
    offset += bytes;
  }
  return widths;
}

static void AddSpan(Spans& spans, size_t input, size_t output) {
  if (!spans.empty() && input == output &&
      spans.back().first == spans.back().second) {
    spans.back().first += input;
    spans.back().second += output;
  } else {
    spans.emplace_back(input, output);
  }
}

static void MapSegment(Spans& spans, const std::string& input,
                       const std::string& output) {
  const auto from = Utf16Widths(input);
  const auto to = Utf16Widths(output);
  if (from.size() == to.size()) {
    for (size_t index = 0; index < from.size(); ++index) {
      AddSpan(spans, from[index], to[index]);
    }
  } else {
    size_t a = 0, b = 0;
    for (const auto width : from) a += width;
    for (const auto width : to) b += width;
    AddSpan(spans, a, b);
  }
}

static void WriteStages(JsonWriter& writer,
                        const opencc::ConversionInspectionResult& result) {
  if (!result.pipelineStages.empty()) {
    for (const auto& stage : result.pipelineStages) WriteStages(writer, stage);
    return;
  }
  const auto* previous = &result.segments;
  for (const auto& stage : result.stages) {
    Spans spans;
    for (size_t index = 0; index < previous->size(); ++index) {
      MapSegment(spans, previous->at(index), stage.segments.at(index));
    }
    writer.StartArray();
    for (const auto& span : spans) {
      writer.StartArray();
      writer.Uint64(span.first);
      writer.Uint64(span.second);
      writer.EndArray();
    }
    writer.EndArray();
    previous = &stage.segments;
  }
}

extern "C" READER_EXPORT char* spectacular_opencc_convert(
    const char* config, const char* text) {
  rapidjson::StringBuffer buffer;
  JsonWriter writer(buffer);
  try {
    const auto result = ConverterFor(config)->Inspect(text);
    writer.StartArray();
    writer.String(result.output.data(), result.output.size());
    writer.StartArray();
    WriteStages(writer, result);
    writer.EndArray();
    writer.EndArray();
  } catch (const opencc::Exception& error) {
    // 上游异常不继承 std::exception，必须单独捕获，不能越过 C 边界。
    buffer.Clear();
    JsonWriter failure(buffer);
    failure.StartObject();
    failure.Key("error");
    failure.String(error.what());
    failure.EndObject();
  } catch (const std::exception& error) {
    buffer.Clear();
    JsonWriter failure(buffer);
    failure.StartObject();
    failure.Key("error");
    failure.String(error.what());
    failure.EndObject();
  } catch (...) {
    buffer.Clear();
    JsonWriter failure(buffer);
    failure.StartObject();
    failure.Key("error");
    failure.String("OpenCC 未知错误");
    failure.EndObject();
  }
  auto* output = static_cast<char*>(std::malloc(buffer.GetSize() + 1));
  if (output != nullptr) std::memcpy(output, buffer.GetString(), buffer.GetSize() + 1);
  return output;
}

extern "C" READER_EXPORT void spectacular_opencc_free(char* text) {
  std::free(text);
}
