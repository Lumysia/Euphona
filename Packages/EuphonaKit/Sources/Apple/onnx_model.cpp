#include "euphona_apple.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include <onnxruntime/onnxruntime_cxx_api.h>

struct pa_model {
    Ort::Session session;
    Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
};

namespace {

// One environment for the process. The Apple build of ONNX Runtime ships Microsoft's telemetry
// client; it is switched off before any model loads, so Euphona sends nothing anywhere.
Ort::Env& environment() {
    static Ort::Env* env = [] {
        auto* created = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "Euphona");
        created->DisableTelemetryEvents();
        return created;
    }();
    return *env;
}

void write_error(char* error, size_t capacity, const char* message) {
    if (error && capacity > 0) std::snprintf(error, capacity, "%s", message);
}

}  // namespace

extern "C" pa_model* pa_model_create(const char* path, int32_t threads, char* error, size_t error_capacity) {
    try {
        Ort::SessionOptions options;
        options.SetIntraOpNumThreads(threads > 0 ? threads : 1);
        options.SetInterOpNumThreads(1);
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        return new pa_model{Ort::Session(environment(), path, options)};
    } catch (const std::exception& exception) {
        write_error(error, error_capacity, exception.what());
        return nullptr;
    }
}

extern "C" void pa_model_destroy(pa_model* model) { delete model; }

extern "C" int32_t pa_model_run(pa_model* model, const pa_tensor_in* inputs, size_t input_count,
                                const char* const* output_names, pa_tensor_out* outputs, size_t output_count,
                                char* error, size_t error_capacity) {
    if (!model || (!inputs && input_count) || (!outputs && output_count)) {
        write_error(error, error_capacity, "invalid argument");
        return 1;
    }
    try {
        std::vector<const char*> names;
        std::vector<Ort::Value> values;
        for (size_t i = 0; i < input_count; ++i) {
            const auto& input = inputs[i];
            size_t count = 1;
            for (size_t d = 0; d < input.rank; ++d) count *= static_cast<size_t>(input.shape[d]);
            names.push_back(input.name);
            if (input.floats) {
                values.push_back(Ort::Value::CreateTensor<float>(
                    model->memory, const_cast<float*>(input.floats), count, input.shape, input.rank));
            } else {
                values.push_back(Ort::Value::CreateTensor<int64_t>(
                    model->memory, const_cast<int64_t*>(input.int64s), count, input.shape, input.rank));
            }
        }
        auto results = model->session.Run(Ort::RunOptions{nullptr}, names.data(), values.data(), values.size(),
                                          output_names, output_count);
        for (size_t i = 0; i < output_count; ++i) {
            auto info = results[i].GetTensorTypeAndShapeInfo();
            auto shape = info.GetShape();
            auto& out = outputs[i];
            out.rank = shape.size() < 8 ? shape.size() : 8;
            for (size_t d = 0; d < out.rank; ++d) out.shape[d] = shape[d];
            out.count = info.GetElementCount();
            out.values = static_cast<float*>(std::malloc(sizeof(float) * (out.count ? out.count : 1)));
            std::memcpy(out.values, results[i].GetTensorData<float>(), sizeof(float) * out.count);
        }
        return 0;
    } catch (const std::exception& exception) {
        write_error(error, error_capacity, exception.what());
        return 1;
    }
}

extern "C" void pa_tensor_free(pa_tensor_out* tensor) {
    if (!tensor) return;
    std::free(tensor->values);
    tensor->values = nullptr;
    tensor->count = 0;
}
