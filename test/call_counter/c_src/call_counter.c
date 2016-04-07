#include "gen_c_server.h"

/*
 * State = { ncalls, ncasts, ninfos }
 */

static void encode_state(
        ei_x_buff *reply,
        long ncalls,
        long ncasts,
        long ninfos)
{
    ei_x_encode_tuple_header(reply,3);
    ei_x_encode_long(reply,ncalls);
    ei_x_encode_long(reply,ncasts);
    ei_x_encode_long(reply,ninfos);
}

void gcs_init(const char* args_buff, ei_x_buff *reply)
{
    /* Reply: {ok,{0,0,0}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"ok");
    encode_state(reply,0,0,0);
}

void gcs_handle_call(
        const char *request_buff,
        const char *from_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {reply,NewState=Reply,{ncalls+1,ncasts,ninfos}=NewState} */
    ei_x_encode_tuple_header(reply,3);
    ei_x_encode_atom(reply,"reply");
    encode_state(reply,ncalls+1,ncasts,ninfos);
    encode_state(reply,ncalls+1,ncasts,ninfos);
}

void gcs_handle_cast(
        const char *request_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {noreply,NewState={ncalls,ncasts+1,ninfos}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"noreply");
    encode_state(reply,ncalls,ncasts+1,ninfos);
}

void gcs_handle_info(
        const char *info_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {noreply,NewState={ncalls,ncasts,ninfos+1}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"noreply");
    encode_state(reply,ncalls,ncasts,ninfos+1);
}

void gcs_terminate(const char *reason_buff, const char *state_buff) { }

