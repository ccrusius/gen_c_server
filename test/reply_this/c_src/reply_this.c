#include "gen_c_server.h"

void gcs_init(const char* args_buff, ei_x_buff *reply)
{
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"ok");
    ei_x_encode_atom(reply,"undefined");
}

void gcs_handle_call(
        const char *request_buff,
        const char *from_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    int index = 0;
    const char *the_reply;
    if(gcs_decode(request_buff,&index,"{At}",2,"reply_this",&the_reply) == 4)
    {
        int reply_len = request_buff + index - the_reply;
        ei_x_append_buf(reply,the_reply,reply_len);
    }
    else
    {
        ei_x_encode_tuple_header(reply,3);
        ei_x_encode_atom(reply,"reply");
        ei_x_encode_atom(reply,"ok");
        ei_x_encode_atom(reply,"undefined");
    }
}

void gcs_handle_cast(
        const char *request_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    int index = 0;
    const char *the_reply;
    if(gcs_decode(request_buff,&index,"{At}",2,"reply_this",&the_reply) == 4)
    {
        int reply_len = request_buff + index - the_reply;
        ei_x_append_buf(reply,the_reply,reply_len);
    }
    else
    {
        ei_x_encode_tuple_header(reply,2);
        ei_x_encode_atom(reply,"noreply");
        ei_x_encode_atom(reply,"undefined");
    }
}

void gcs_handle_info(
        const char *info_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    gcs_handle_cast(info_buff, state_buff, reply);
}

void gcs_terminate(const char *reason_buff, const char *state_buff) { }

