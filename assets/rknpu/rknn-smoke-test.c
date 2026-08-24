#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rknn_api.h"

#define TEST_RUNS 10

static int check(int ret, const char *operation)
{
    if (ret == RKNN_SUCC)
        return 0;

    fprintf(stderr, "%s failed: %d\n", operation, ret);
    return -1;
}

int main(int argc, char **argv)
{
    rknn_context ctx = 0;
    rknn_input_output_num io_num = {0};
    rknn_tensor_attr input_attr = {0};
    rknn_sdk_version version = {0};
    rknn_input input = {0};
    rknn_output *outputs = NULL;
    unsigned char *input_data = NULL;
    uint64_t checksum = 0;
    int64_t total_us = 0;
    int ret = EXIT_FAILURE;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s MODEL.rknn\n", argv[0]);
        return EXIT_FAILURE;
    }

    if (check(rknn_init(&ctx, argv[1], 0, 0, NULL), "rknn_init"))
        goto out;
    if (check(rknn_query(ctx, RKNN_QUERY_SDK_VERSION, &version,
                         sizeof(version)), "RKNN_QUERY_SDK_VERSION"))
        goto out;
    if (check(rknn_query(ctx, RKNN_QUERY_IN_OUT_NUM, &io_num,
                         sizeof(io_num)), "RKNN_QUERY_IN_OUT_NUM"))
        goto out;
    if (io_num.n_input != 1 || io_num.n_output == 0) {
        fprintf(stderr, "unexpected model I/O count: %u/%u\n",
                io_num.n_input, io_num.n_output);
        goto out;
    }

    input_attr.index = 0;
    if (check(rknn_query(ctx, RKNN_QUERY_INPUT_ATTR, &input_attr,
                         sizeof(input_attr)), "RKNN_QUERY_INPUT_ATTR"))
        goto out;

    input_data = calloc(1, input_attr.size);
    outputs = calloc(io_num.n_output, sizeof(*outputs));
    if (!input_data || !outputs) {
        fprintf(stderr, "failed to allocate inference buffers\n");
        goto out;
    }

    input.index = 0;
    input.buf = input_data;
    input.size = input_attr.size;
    input.pass_through = 0;
    input.type = input_attr.type;
    input.fmt = input_attr.fmt;
    if (check(rknn_inputs_set(ctx, 1, &input), "rknn_inputs_set"))
        goto out;

    for (int run = 0; run < TEST_RUNS; run++) {
        rknn_perf_run perf = {0};

        if (check(rknn_run(ctx, NULL), "rknn_run"))
            goto out;
        memset(outputs, 0, io_num.n_output * sizeof(*outputs));
        for (uint32_t i = 0; i < io_num.n_output; i++) {
            outputs[i].index = i;
            outputs[i].want_float = 1;
        }
        if (check(rknn_outputs_get(ctx, io_num.n_output, outputs, NULL),
                  "rknn_outputs_get"))
            goto out;
        for (uint32_t i = 0; i < io_num.n_output; i++) {
            const unsigned char *bytes = outputs[i].buf;
            for (uint32_t j = 0; j < outputs[i].size; j++)
                checksum = (checksum * 131) + bytes[j];
        }
        if (check(rknn_outputs_release(ctx, io_num.n_output, outputs),
                  "rknn_outputs_release"))
            goto out;
        if (check(rknn_query(ctx, RKNN_QUERY_PERF_RUN, &perf, sizeof(perf)),
                  "RKNN_QUERY_PERF_RUN"))
            goto out;
        total_us += perf.run_duration;
    }

    printf("RKNN runtime: %s\n", version.api_version);
    printf("RKNPU driver: %s\n", version.drv_version);
    printf("Model I/O: %u input, %u output; input bytes: %u\n",
           io_num.n_input, io_num.n_output, input_attr.size);
    printf("Inference: %d runs, average %.2f ms, checksum %016llx\n",
           TEST_RUNS, total_us / (TEST_RUNS * 1000.0),
           (unsigned long long)checksum);
    ret = EXIT_SUCCESS;

out:
    free(outputs);
    free(input_data);
    if (ctx)
        rknn_destroy(ctx);
    return ret;
}
