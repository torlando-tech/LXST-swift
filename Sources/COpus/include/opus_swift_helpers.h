/* Swift-callable wrappers for variadic opus_encoder/decoder_ctl functions */
#ifndef OPUS_SWIFT_HELPERS_H
#define OPUS_SWIFT_HELPERS_H

#include "opus.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline int opus_encoder_set_bitrate(OpusEncoder *st, opus_int32 bitrate) {
    return opus_encoder_ctl(st, OPUS_SET_BITRATE(bitrate));
}

static inline int opus_encoder_set_complexity(OpusEncoder *st, opus_int32 complexity) {
    return opus_encoder_ctl(st, OPUS_SET_COMPLEXITY(complexity));
}

static inline int opus_encoder_set_signal(OpusEncoder *st, opus_int32 signal) {
    return opus_encoder_ctl(st, OPUS_SET_SIGNAL(signal));
}

static inline int opus_encoder_reset(OpusEncoder *st) {
    return opus_encoder_ctl(st, OPUS_RESET_STATE);
}

static inline int opus_decoder_reset(OpusDecoder *st) {
    return opus_decoder_ctl(st, OPUS_RESET_STATE);
}

#ifdef __cplusplus
}
#endif

#endif /* OPUS_SWIFT_HELPERS_H */
