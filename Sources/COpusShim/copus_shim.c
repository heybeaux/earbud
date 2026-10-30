#include "copus_shim.h"

OpusEncoder *copus_shim_fieldy_encoder_create(opus_int32 sample_rate, opus_int32 bitrate, int *error) {
    OpusEncoder *enc = opus_encoder_create(sample_rate, 1, OPUS_APPLICATION_RESTRICTED_LOWDELAY, error);
    if (enc == NULL) {
        return NULL;
    }
    int rc = opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
    if (rc == OPUS_OK) rc = opus_encoder_ctl(enc, OPUS_SET_VBR(0));
    if (rc == OPUS_OK) rc = opus_encoder_ctl(enc, OPUS_SET_BANDWIDTH(OPUS_BANDWIDTH_WIDEBAND));
    if (rc != OPUS_OK) {
        opus_encoder_destroy(enc);
        if (error) *error = rc;
        return NULL;
    }
    return enc;
}

int copus_shim_decoder_reset(OpusDecoder *decoder) {
    return opus_decoder_ctl(decoder, OPUS_RESET_STATE);
}
