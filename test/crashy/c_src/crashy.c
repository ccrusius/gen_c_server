#include "gen_c_server.h"
#include <stdlib.h>

/*
 * State = undefined
 */

void gcs_init(const char* args_buff, ei_x_buff *reply)
{
    /* Reply: {ok,undefined} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"ok");
    ei_x_encode_atom(reply,"undefined");
}

static void maybe_crash(const char *request_buff)
{
    long status;
    if (gcs_decode(request_buff,(int*)0,"{Al}",2,"stop",&status)==4)
        exit(status);
    if (gcs_decode(request_buff,(int*)0,"A","segfault")==1) {
        int* null=(int*)0;
        *null=1;
    }
    if (gcs_decode(request_buff,(int*)0,"A","abort")==1)
        abort();
}

void gcs_handle_call(
        const char *request_buff,
        const char *from_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    maybe_crash(request_buff);

    /* Reply: {reply,ok=Reply,undefined=NewState} */
    ei_x_encode_tuple_header(reply,3);
    ei_x_encode_atom(reply,"reply");
    ei_x_encode_atom(reply,"ok");
    ei_x_encode_atom(reply,"undefined");
}

void gcs_handle_cast(
        const char *request_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    maybe_crash(request_buff);

    /* Reply: {noreply,undefined=NewState} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"reply");
    ei_x_encode_atom(reply,"undefined");
}

void gcs_handle_info(
        const char *info_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    gcs_handle_cast(info_buff, state_buff, reply);
}

void gcs_terminate(const char *reason_buff, const char *state_buff) { }

