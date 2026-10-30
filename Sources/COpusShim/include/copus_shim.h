#ifndef COPUS_SHIM_H
#define COPUS_SHIM_H

#include <opus.h>

/// opus_encoder_ctl / opus_decoder_ctl are variadic and not callable from
/// Swift. These wrappers expose the few settings EarBud needs.

/// Creates a mono encoder that produces Fieldy-format frames: CELT-only
/// (restricted low delay), constant bitrate. At 16 kHz, 20 ms and 16000 bit/s
/// every frame is 40 bytes with TOC 0xB8. Returns NULL on failure.
OpusEncoder *copus_shim_fieldy_encoder_create(opus_int32 sample_rate, opus_int32 bitrate, int *error);

/// Resets decoder state (OPUS_RESET_STATE).
int copus_shim_decoder_reset(OpusDecoder *decoder);

#endif
