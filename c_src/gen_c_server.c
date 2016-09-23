/*
   %CopyrightBegin%

   Copyright Cesar Crusius 2016. All Rights Reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

   %CopyrightEnd%
*/
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include "gen_c_server.h"

#include "erl_interface.h"

#define GCS_EXIT_INVALID_ARGC            1
#define GCS_EXIT_GEN_CALL_SEND           2
#define GCS_EXIT_NO_HOST                 3
#define GCS_EXIT_EI_CONNECT_INIT         4
#define GCS_EXIT_EI_CONNECT              5
#define GCS_EXIT_PTHREAD_CREATE          6
#define GCS_EXIT_EI_RECONNECT            7
#define GCS_EXIT_EI_SEND                 8
#define GCS_EXIT_GEN_CALL                9
#define GCS_EXIT_MUTEX_LOCK             10

/*==============================================================================
 *
 * ei utilities
 *
 *============================================================================*/
static void
erlang_pid_dup(const erlang_pid *in, erlang_pid *out)
{ *out = *in; memcpy(out->node,in->node,MAXATOMLEN_UTF8); }

static void
erlang_trace_dup(const erlang_trace *in, erlang_trace *out)
{ *out = *in; erlang_pid_dup(&in->from,&out->from); }

static void
erlang_msg_dup(const erlang_msg *in, erlang_msg *out)
{
    *out = *in;
    erlang_pid_dup(&in->from,&out->from);
    erlang_pid_dup(&in->to,&out->to);
    memcpy(out->toname,in->toname,MAXATOMLEN_UTF8);
    memcpy(out->cookie,in->cookie,MAXATOMLEN_UTF8);
    erlang_trace_dup(&in->token,&out->token);
}

static void
ei_x_buff_dup(const ei_x_buff *in, ei_x_buff *out)
{
    if (out->buff) free(out->buff);
    *out = *in;
    if (out->buffsz == 0 && out->buff == NULL) return;
    out->buff = (char*) malloc(in->buffsz);
    memcpy(out->buff,in->buff,out->buffsz);
}

int gcs_decode(const char* buffer, int *index, const char* fmt, ...)
{
    va_list args;
    va_start(args,fmt);

    const char *ptr = fmt;

    int aux_index = 0;
    if(!index) index = &aux_index;

    const int original_index = *index;

    union {
        int        aux_int;
        long       aux_long;
        erlang_pid aux_pid;
        erlang_ref aux_ref;
        char       aux_atom[MAXATOMLEN_UTF8];
    } aux_value;

    for(;*ptr;++ptr) {
        if (*ptr == '{') {
            int desired = va_arg(args,int);
            if (ei_decode_tuple_header(buffer,index,&aux_value.aux_int)) break;
            if (desired > 0 && aux_value.aux_int != desired) break;
        }
        else if (*ptr == '}') {
            /* Ignore */
        }
        else if (*ptr == '_') {
            if (ei_skip_term(buffer,index)) break;
        }
        else if (*ptr == 'a') {
            char* atom = va_arg(args,char*);
            if (!atom) atom = aux_value.aux_atom;
            if (ei_decode_atom(buffer,index,atom)) break;
        }
        else if (*ptr == 'A') {
            const char *desired = va_arg(args,const char*);
            if (ei_decode_atom(buffer,index,aux_value.aux_atom)) break;
            if (desired && strcmp(desired,aux_value.aux_atom) != 0) break;
        }
        else if (*ptr == 'l') {
            long* val = va_arg(args,long*);
            if (!val) val = &aux_value.aux_long;
            if (ei_decode_long(buffer,index,val)) break;
        }
        else if (*ptr == 'p') {
            erlang_pid* pid = va_arg(args,erlang_pid*);
            if (!pid) pid = &aux_value.aux_pid;
            if (ei_decode_pid(buffer,index,pid)) break;
        }
        else if (*ptr == 'r') {
            erlang_ref* ref = va_arg(args,erlang_ref*);
            if (!ref) ref = &aux_value.aux_ref;
            if (ei_decode_ref(buffer,index,ref)) break;
        }
        else if (*ptr == 't') {
            const char** term = va_arg(args,const char**);
            if (term) *term = buffer + *index;
            if (ei_skip_term(buffer,index)) break;
        }
        else if (*ptr == 'v') {
            int* version = va_arg(args,int*);
            if (!version) version = &aux_value.aux_int;
            if (ei_decode_version(buffer,index,version)) break;
        }
        else break;
    }

    va_end(args);

    if (*ptr) *index = original_index;

    return ptr-fmt;
}

/*==============================================================================
 *
 * The internal C node state.
 *
 * The state holds information about the node identification, and the current
 * connection to the Erlang node.
 *
 *============================================================================*/
struct c_node_state {
    char *c_node_name;     /* C node 'alive name' */
    char *c_node_hostname; /* FQDN host name */
    char *c_node_fullname; /* Convenience: node_name@node_hostname */

    char *erlang_node_fullname; /* Erlang node we're connected to. */
    char *erlang_node_cookie;   /* Cookie used for communications. */

    ei_cnode ec; /* The EI connection structure. */
    int connection_fd; /* The connection file descriptor. */
};

/*==============================================================================
 *
 * Printing
 *
 * Our convention is that a specific line, defined by C_NODE_END_MSG, is
 * printed at the end of every message sent. This allows the Erlang node
 * to know when we're done sending what we want to send.
 *
 * Since printing functions may be called from multiple threads, we put
 * a mutex around them so that messages don't get chopped up.
 *
 *============================================================================*/
static const char *C_NODE_START_MSG = "... - .- .-. -"; /* Morse code for "start" */
static const char *C_NODE_END_MSG   = ". -. -.."; /* Morse code for "end" */

static pthread_mutex_t print_mutex = PTHREAD_MUTEX_INITIALIZER;

static void _vprint(const char* prefix, const char* fmt, va_list args)
{
    pthread_mutex_lock(&print_mutex);
    printf("\n%s\n",C_NODE_START_MSG);
    printf("%s",prefix);
    vprintf(fmt,args);
    printf("\n%s\n",C_NODE_END_MSG);
    fflush(stdout);
    pthread_mutex_unlock(&print_mutex);
}

#define C_NODE_PRINT(prefix) \
    va_list args; va_start(args,fmt); _vprint(prefix,fmt,args); va_end(args);

static void info_print(const char *fmt,...)    {
    if (ei_get_tracelevel() > 0) { C_NODE_PRINT("<INFO> "); }
}
//static void warning_print(const char *fmt,...) { C_NODE_PRINT("<WARN>"); }
static void error_print(const char *fmt,...)   { C_NODE_PRINT("<ERROR>"); }

static void debug_print(const char *fmt,...) {
    if (ei_get_tracelevel() > 2) { C_NODE_PRINT("<INFO>[DEBUG] "); }
}

static void trace_print(const char *fmt,...) {
    if (ei_get_tracelevel() > 3) { C_NODE_PRINT("<INFO>[TRACE] "); }
}

/* =========================================================================
 *
 * Pthread utilities
 *
 * ========================================================================= */
static int pthread_failures = 0;
static const int PTHREAD_MAX_FAILURES = 1;

static void increment_pthread_failures(const char* msg, int status)
{
  ++pthread_failures;
  error_print(msg);
  if(pthread_failures < PTHREAD_MAX_FAILURES) return;
  error_print("Too many pthread failures");
  exit(status);
}

#define gcs_pthread_mutex_lock(VAR) \
  while(pthread_mutex_lock(&VAR) != 0) \
    increment_pthread_failures(\
      "pthread_mutex_lock failed (" #VAR ")",\
      GCS_EXIT_MUTEX_LOCK);

/*==============================================================================
 *
 * Main
 *
 * Establish a connection to the Erlang node, and enter the main message loop.
 *
 *============================================================================*/
static void _connect(struct c_node_state *state);
static void _main_message_loop(struct c_node_state *state);

int main(int argc, char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if(argc != 6) {
        error_print(
                 "Invalid arguments when starting generic C node.\n"
                 "Is this executable being called from gen_c_server?\n"
                 "Usage: %s <name> <hostname> <remote> <cookie> <trace level>\n"
                 "Call:  %s %s %s %s %s %s %s %s %s %s",
                 argv[0], argv[0],
                 (argc > 1 ? argv[1] : ""),
                 (argc > 2 ? argv[2] : ""),
                 (argc > 3 ? argv[3] : ""),
                 (argc > 4 ? argv[4] : ""),
                 (argc > 5 ? argv[5] : ""),
                 (argc > 6 ? argv[6] : ""),
                 (argc > 7 ? argv[7] : ""),
                 (argc > 8 ? argv[8] : ""),
                 (argc > 9 ? argv[9] : ""));
        exit(GCS_EXIT_INVALID_ARGC);
    }

    erl_init(NULL,0);

    struct c_node_state *state = (struct c_node_state*)malloc(sizeof *state);

    state->c_node_name          = strdup(argv[1]);
    state->c_node_hostname      = strdup(argv[2]);
    state->erlang_node_fullname = strdup(argv[3]);
    state->erlang_node_cookie   = strdup(argv[4]);
    ei_set_tracelevel(atoi(argv[5]));

#   ifdef _WIN32
    /* Without this, gethostbyname() does not work on Windows... */
    WSAData wsdata;
    WSAStartup(WINSOCK_VERSION, &wsdata);
    /* Without this, Windows pops up the annoying crash dialog box,
       making automated tests impossible. */
    SetErrorMode(SetErrorMode(0) | SEM_NOGPFAULTERRORBOX);
#   endif

    _connect(state);

    _main_message_loop(state);

#   ifdef _WIN32
    WSACleanup();
#   endif

    info_print("C node stopped.");

    free(state);

    return 0;
}

static void
_connect(struct c_node_state *state)
{
    struct hostent *host;

    if ((host = gethostbyname(state->c_node_hostname)) == NULL) {
        error_print("Can not resolve host information for %s. (%d)"
                    ,state->c_node_hostname
                    ,h_errno);
        exit(GCS_EXIT_NO_HOST);
    }

    state->c_node_fullname = (char*)
        malloc(strlen(state->c_node_name) + strlen(state->c_node_hostname) + 2);
    sprintf(state->c_node_fullname, "%s@%s"
           ,state->c_node_name
           ,state->c_node_hostname);

    struct in_addr *addr = (struct in_addr *) host->h_addr;

    if (ei_connect_xinit(&state->ec
                        ,state->c_node_hostname
                        ,state->c_node_name
                        ,state->c_node_fullname
                        ,addr
                        ,state->erlang_node_cookie, 0) < 0) {
        error_print("ei_connect_xinit failed: %d (%s)\n"
               "  host  name='%s'\n"
               "  alive name='%s'\n"
               "  node  name='%s'",
               erl_errno,strerror(erl_errno),
               state->c_node_hostname,
               state->c_node_name,
               state->c_node_fullname);
        exit(GCS_EXIT_EI_CONNECT_INIT);
    }

    info_print("C node '%s' starting.",ei_thisnodename(&state->ec));

    state->connection_fd = ei_connect(&state->ec,state->erlang_node_fullname);
    if (state->connection_fd < 0) {
        error_print("ei_connect '%s' failed: %d (%s)",
                state->erlang_node_fullname,
                erl_errno, strerror(erl_errno));
        exit(GCS_EXIT_EI_CONNECT);
    }

    info_print("C node '%s' connected.",ei_thisnodename(&state->ec));
}

static void
_reconnect(struct c_node_state *state)
{
    if ((state->connection_fd = ei_connect(&state->ec, state->erlang_node_fullname)) < 0) {
        error_print("Cannot reconnect to parent node '%s': %d (%s)",
                state->erlang_node_fullname, erl_errno, strerror(erl_errno));
        exit(GCS_EXIT_EI_RECONNECT);
    }
}


/*==============================================================================
 *
 * Should we be running or not?
 *
 * Both infinite loops, the message loop and the execution loop, stop when
 * this variable is set to zero.
 *
 *============================================================================*/
static int running = 1;

/*==============================================================================
 *
 * Message queue.
 *
 * To allow for long-running calls, we need to have our message loop run on the
 * main thread, while executions happen on a separate thread. We maintain a
 * queue of messages waiting to be processed. The main thread can add to it,
 * and the execution thread can remove messages from it.
 *
 * The execution thread keeps going through messages in the queue until
 * there is none left. When that happens, it waits for a new message to arrive,
 * and resumes executions. The wait is done when the condition variable
 * 'start_executions' is signalled.
 *
 *============================================================================*/
struct message {
    struct message *next;
    erlang_msg msg;
    ei_x_buff  input;
};

static void
message_new(struct message *out)
{
    out->next = NULL;
    ei_x_new(&out->input);
}

static void
message_free(struct message *msg)
{
    ei_x_free(&msg->input);
    free(msg);
}

static struct message *current_message;

/* The lock on the list. */
static pthread_mutex_t message_queue_lock = PTHREAD_MUTEX_INITIALIZER;

/* The empty list lock and condition variable. */
static pthread_mutex_t empty_queue_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  empty_queue_cond = PTHREAD_COND_INITIALIZER;

/*==============================================================================
 *
 * Messages
 *
 *============================================================================*/
struct command {
    char cmd[MAXATOMLEN_UTF8];
    erlang_pid pid;
    const char *args_buff;
    const char *state_buff;
    const char *from_buff;  // The {pid(),Tag} from gen_server:handle_call
    int        from_buff_len;
};

static int
_decode_command(const char* input, struct command* cmd)
{
    int  index = 0;
    char *errmsg;

    memset(cmd,0,sizeof *cmd); /* Reset everything. */

#   define INV_TUPLE(msg) { errmsg = msg; goto invalid_command_tuple; }

    int ndecoded = gcs_decode(input,&index,"v{apttt}",
            (int*)0,5,
            cmd->cmd,
            &cmd->pid,
            &cmd->args_buff,
            &cmd->state_buff,
            &cmd->from_buff);

    if (ndecoded == 0) INV_TUPLE("Invalid version in message buffer.");
    if (ndecoded == 1) INV_TUPLE("Message buffer is not a tuple of size 5.");
    if (ndecoded == 2) INV_TUPLE("First tuple element is not an atom.");
    if (ndecoded == 3) INV_TUPLE("Second tuple element is not a PID.");
    if (ndecoded == 4) INV_TUPLE("Third tuple element is not an erlang term.");
    if (ndecoded == 5) INV_TUPLE("Fourth tuple element is not an erlang term.");
    if (ndecoded == 6) INV_TUPLE("Fifth tuple element is not an erlang term.");

    cmd->from_buff_len = (input+index)-(cmd->from_buff);

#   undef INV_TUPLE

    return index;

invalid_command_tuple:
    {
        index  = 0;
        int  version;
        char *err_buff = NULL;

        if (ei_decode_version(input,&index,&version) < 0
            || ei_s_print_term(&err_buff,input,&index) < 0)
            error_print("%s\nInvalid term. What are you doing?",errmsg);
        else
            error_print("%s\nMessage: %s",errmsg,err_buff);
        if (err_buff!=NULL) free(err_buff);

        memset(cmd,0,sizeof *cmd); /* Reset everything. */
        return -1;
    }
}

/*==============================================================================
 *
 * The execution thread function.
 *
 *============================================================================*/
static void*
_execution_loop(void *arg)
{
    struct c_node_state *state = (struct c_node_state*) arg;

    ei_x_buff reply_buffer;
    ei_x_new(&reply_buffer);

    ei_x_buff out_msg_buffer;
    ei_x_new(&out_msg_buffer);

    while(running) {
        /* Wait for a message to be added to the queue. */
        gcs_pthread_mutex_lock(empty_queue_lock);
        while (current_message == NULL)
            pthread_cond_wait(&empty_queue_cond,&empty_queue_lock);
        pthread_mutex_unlock(&empty_queue_lock);

        /* Since this is the only function that drops messages from the queue,
         * we don't need to worry about current_message becoming NULL or
         * otherwise changing behind our backs. */
        while (current_message != NULL) {
            /* XXX process message */
            debug_print("Processing message.");
            struct command cmd;
            if (_decode_command(current_message->input.buff,&cmd)>0) {
                reply_buffer.index=0;
                debug_print("Message command: '%s'",cmd.cmd);
                if(!strcmp(cmd.cmd,"init")) {
                    gcs_init(cmd.args_buff,&reply_buffer);
                }
                else if(!strcmp(cmd.cmd,"terminate")) {
                    // The 'terminate' reply is ignored, but we send one
                    // anyway.
                    gcs_terminate(cmd.args_buff, cmd.state_buff);
                    ei_x_encode_atom(&reply_buffer,"ok");
                    running = 0;
                }
                else if(!strcmp(cmd.cmd,"call")) {
                    //
                    // We wrap the gcs_handle_call Reply into a 3-tuple
                    // {'$gcs_call_reply',From,Reply}
                    //
                    ei_x_encode_tuple_header(&reply_buffer,3);
                    ei_x_encode_atom(&reply_buffer,"$gcs_call_reply");
                    ei_x_append_buf(&reply_buffer,cmd.from_buff,cmd.from_buff_len);
                    gcs_handle_call(
                            cmd.args_buff,
                            cmd.from_buff,
                            cmd.state_buff,
                            &reply_buffer);
                }
                else if(!strcmp(cmd.cmd,"cast")) {
                    //
                    // We wrap the gcs_handle_cast Reply into a 2-tuple
                    // {'$gcs_cast_reply',Reply}
                    //
                    ei_x_encode_tuple_header(&reply_buffer,2);
                    ei_x_encode_atom(&reply_buffer,"$gcs_cast_reply");
                    gcs_handle_cast(
                            cmd.args_buff,
                            cmd.state_buff,
                            &reply_buffer);
                }
                else if(!strcmp(cmd.cmd,"info")) {
                    //
                    // We wrap the gcs_handle_info Reply into a 2-tuple
                    // {'$gcs_info_reply',Reply}
                    //
                    ei_x_encode_tuple_header(&reply_buffer,2);
                    ei_x_encode_atom(&reply_buffer,"$gcs_info_reply");
                    gcs_handle_info(
                            cmd.args_buff,
                            cmd.state_buff,
                            &reply_buffer);
                }
                else error_print("Unknown command '%s'",cmd.cmd);

                if(reply_buffer.index > 0) {
                    debug_print("Sending message reply.");
                    out_msg_buffer.index = 0;
                    ei_x_encode_version(&out_msg_buffer);
                    ei_x_encode_tuple_header(&out_msg_buffer,2);
                    ei_x_encode_atom(&out_msg_buffer,state->c_node_fullname);
                    ei_x_append(&out_msg_buffer,&reply_buffer);

                    if(ei_send(state->connection_fd, &cmd.pid,
                                out_msg_buffer.buff,
                                out_msg_buffer.index) < 0) {
                        error_print("Could not send message reply.");
                        exit(GCS_EXIT_EI_SEND);
                    }
                }
            }

            debug_print("Finished processing message.");

            /* Drop the first message from the queue. */
            gcs_pthread_mutex_lock(message_queue_lock);
            struct message *next_message = current_message->next;
            message_free(current_message);
            current_message = next_message;
            pthread_mutex_unlock(&message_queue_lock);
        }
    }

    ei_x_free(&reply_buffer);

    debug_print("End of execution loop.");

    /* We ideally should return, but the problem is that we'll get timeouts
     * on the Erlang side. The "proper" thing is to get notified on the message
     * loop side when the thread ends, but right now it is blocked waiting
     * for a message in ei_xreceive_msg. exit(0) will do for now. */
    exit(0);

    return NULL;
}

/*==============================================================================
 *
 * The main message loop.
 *
 * This is executed in the main thread, and its job is basically to keep the
 * C node ticking while the execution thread keeps the executions going. It
 * replies to internal Erlang messages such as TICK, and delegates the actual
 * work to the message queue, where it gets picked up by the execution thread.
 *
 *============================================================================*/
static const char *C_NODE_READY_MSG = ".-. . .- -.. -.--"; /* Morse for "ready". */
static int _process_gen_call(const char*, ei_x_buff*);

static void
_main_message_loop(struct c_node_state *state)
{
    pthread_t execution_thread;
    if(pthread_create(&execution_thread,NULL,&_execution_loop,state)!=0) {
        error_print("pthread_create failed: %d (%s)", errno, strerror(errno));
        exit(GCS_EXIT_PTHREAD_CREATE);
    }

    ei_x_buff msg_buffer;
    ei_x_new(&msg_buffer);

    ei_x_buff reply_buffer;
    ei_x_new(&reply_buffer);

    int waiting_for_exit = 0;

    printf("%s\n",C_NODE_READY_MSG); fflush(stdout);

    while (running) { // The execution thread will set running=0
        erlang_msg msg;
        switch (ei_xreceive_msg(state->connection_fd, &msg, &msg_buffer)) {
            case ERL_ERROR:
                debug_print(
                        "ei_xreceive_msg failed: %d (%s)",
                        erl_errno, strerror(erl_errno));
                _reconnect(state);
                break;
            case ERL_TICK:
                trace_print("TICK");
                break;
            case ERL_MSG:
                switch(msg.msgtype) {
                    case ERL_LINK:
                        debug_print("Erlang node linked.");
                        break;
                    case ERL_UNLINK:
                    case ERL_EXIT:
                        debug_print("C node unlinked; terminating.");
                        running = 0;
                        break;
                    case ERL_SEND:
                    case ERL_REG_SEND:
                        {
                            if (waiting_for_exit) break;
                            debug_print("Got message.");

                            /* Intercept '$gen_call' messages here. */
                            if (_process_gen_call(msg_buffer.buff,&reply_buffer))
                            {
                                if(ei_send(state->connection_fd, &msg.from,
                                            reply_buffer.buff,
                                            reply_buffer.index) < 0) {
                                    error_print("Could not send message reply.");
                                    exit(GCS_EXIT_GEN_CALL_SEND);
                                }
                                break;
                            }

                            /* The 'terminate' call is special: we will send
                             * the message and give the thread a chance to
                             * exit, but we will stop processing messages
                             * until that happens. (If we did not have to
                             * keep replying TICKs, we could have pthread_joined
                             * here.) */
                            struct command cmd;
                            if (_decode_command(msg_buffer.buff,&cmd)<0) break;
                            if (!strcmp(cmd.cmd,"terminate"))
                                waiting_for_exit = 1;

                            /* Deep copy message. */
                            struct message* new_message = (struct message*)malloc(sizeof *new_message);
                            message_new(new_message);
                            erlang_msg_dup(&msg,&new_message->msg);
                            ei_x_buff_dup(&msg_buffer,&new_message->input);

                            /* Add the message to the queue, signalling in case it is
                             * the first one. Once it is added there, the execution loop
                             * will take care of it at some point, so we're free to
                             * get back to responding to ticks. */
                            pthread_mutex_lock(&message_queue_lock);

                            if (current_message == NULL) {
                                /* We are the only ones adding to the queue, so we
                                 * don't need to worry about current_message becoming
                                 * non-NULL between the test above and our insertion
                                 * below. */
                                pthread_mutex_lock(&empty_queue_lock);
                                trace_print("Signaling non-empty message queue.");
                                pthread_cond_signal(&empty_queue_cond);
                                current_message = new_message;
                                pthread_mutex_unlock(&empty_queue_lock);
                            }
                            else {
                                struct message *last_message;
                                for(last_message=current_message;
                                        last_message->next != NULL;
                                        last_message=last_message->next);
                                last_message->next = new_message;
                            }

                            pthread_mutex_unlock(&message_queue_lock);
                        }
                        break;
                }
                break;
        }
    }

    /* The following statements are usually not called, since the execution
     * thread will exit(0) once "terminate" is received. They are left here
     * because if a proper signalling mechanism is implemented, they are what
     * is required for a "clean" exit. */
    ei_x_free(&msg_buffer);
    ei_x_free(&reply_buffer);
    pthread_join(execution_thread,NULL); // Should have finished already.
}

static int
_process_gen_call(const char* gen_call_msg, ei_x_buff* reply)
{
    int         ndecoded;
    erlang_ref  ref;
    const char* msg;

    /* Decode {'$gen_call', {_,Ref}, Msg} */
    ndecoded = gcs_decode(gen_call_msg,(int*)0,
            "v{A{_r}t}",
            (int*)0,         /* version */
            3,               /* tuple size {'$gen_call',From,Msg} */
            "$gen_call",     /* required atom */
            2,               /* tuple size {_,Ref}=From */
            &ref,            /* reference */
            &msg);           /* message */

    if (ndecoded != 9) return 0;

    reply->index = 0;

    /* net_adm:ping
     * Msg   = {is_auth,_}
     * Reply = {Ref,yes}
     */
    if (gcs_decode(msg,(int*)0,"{A",0,"is_auth") == 2) {
        ei_x_encode_version(reply);
        ei_x_encode_tuple_header(reply,2);
        ei_x_encode_ref(reply,&ref);
        ei_x_encode_atom(reply,"yes");
        return 1;
    }

    /* A '$gen_call' we don't understand. */
    int  index     = 0;
    char *err_buff = NULL;
    int  version;
    ei_decode_version(gen_call_msg,&index,&version);
    ei_s_print_term(&err_buff,gen_call_msg,&index);
    error_print("Unprocessed `$gen_call' message\nMessage %s",err_buff);
    free(err_buff);
    exit(GCS_EXIT_GEN_CALL);

    return 0;
}
