/* Copyright (c) 2010-2011 Xiph.Org Foundation, Skype Limited
   Written by Jean-Marc Valin and Koen Vos */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef COPUS_OPUS_H
#define COPUS_OPUS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opus types */
typedef int16_t opus_int16;
typedef uint16_t opus_uint16;
typedef int32_t opus_int32;
typedef uint32_t opus_uint32;

/* Opus error codes */
#define OPUS_OK                0
#define OPUS_BAD_ARG          -1
#define OPUS_BUFFER_TOO_SMALL -2
#define OPUS_INTERNAL_ERROR   -3
#define OPUS_INVALID_PACKET   -4
#define OPUS_UNIMPLEMENTED    -5
#define OPUS_INVALID_STATE    -6
#define OPUS_ALLOC_FAIL       -7

/* Application modes */
#define OPUS_APPLICATION_VOIP                2048
#define OPUS_APPLICATION_AUDIO               2049
#define OPUS_APPLICATION_RESTRICTED_LOWDELAY 2051

/* CTL request IDs */
#define OPUS_SET_BITRATE_REQUEST             4002
#define OPUS_SET_COMPLEXITY_REQUEST          4010
#define OPUS_RESET_STATE                     4028

/* Opaque encoder/decoder types */
typedef struct OpusEncoder OpusEncoder;
typedef struct OpusDecoder OpusDecoder;

/* Encoder API */
OpusEncoder *opus_encoder_create(opus_int32 Fs, int channels, int application, int *error);
void opus_encoder_destroy(OpusEncoder *st);
opus_int32 opus_encode(OpusEncoder *st, const opus_int16 *pcm, int frame_size,
                       unsigned char *data, opus_int32 max_data_bytes);
int opus_encoder_ctl(OpusEncoder *st, int request, ...);

/* Decoder API */
OpusDecoder *opus_decoder_create(opus_int32 Fs, int channels, int *error);
void opus_decoder_destroy(OpusDecoder *st);
int opus_decode(OpusDecoder *st, const unsigned char *data, opus_int32 len,
                opus_int16 *pcm, int frame_size, int decode_fec);
int opus_decoder_ctl(OpusDecoder *st, int request, ...);

/* Utility */
const char *opus_strerror(int error);
const char *opus_get_version_string(void);

#ifdef __cplusplus
}
#endif

#endif /* COPUS_OPUS_H */
