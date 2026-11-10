#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One ONNX model on the CPU, for Euphona's own engine. Not safe for concurrent runs.
typedef struct pa_model pa_model;

/// One input tensor. Exactly one of `floats` and `int64s` is set; a rank of 0 is a scalar.
typedef struct pa_tensor_in {
    const char* name;
    const float* floats;
    const int64_t* int64s;
    const int64_t* shape;
    size_t rank;
} pa_tensor_in;

/// One float output tensor, owned by the caller after a successful run; free with pa_tensor_free.
typedef struct pa_tensor_out {
    float* values;
    size_t count;
    int64_t shape[8];
    size_t rank;
} pa_tensor_out;

/// Returns NULL and writes a message on failure.
pa_model* pa_model_create(const char* path, int32_t threads, char* error, size_t error_capacity);
void pa_model_destroy(pa_model* model);

/// Runs the model and fills one output per name. Returns 0 on success.
int32_t pa_model_run(pa_model* model, const pa_tensor_in* inputs, size_t input_count,
                     const char* const* output_names, pa_tensor_out* outputs, size_t output_count,
                     char* error, size_t error_capacity);
void pa_tensor_free(pa_tensor_out* tensor);

#ifdef __cplusplus
}
#endif
