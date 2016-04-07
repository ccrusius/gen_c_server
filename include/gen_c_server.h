#ifndef __GEN_C_SERVER_H__
#define __GEN_C_SERVER_H__
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

#include "ei.h"

/*
 * Callback to initialize the C node.
 *
 * @param args_buff The buffer containing arguments used in the init call from
 *        Erlang's side of things. They can be retrieved with the ei_decode
 *        family of functions.
 * @param reply The buffer where the gcs_init function should store its reply
 *        by calling the appropriate ei_x_encode functions. ei_x_encode_version
 *        will be called automatically, meaning the function should not call it
 *        itself.
 */
void gcs_init(const char* args_buff, ei_x_buff* reply);

/*
 * Callback to handle gen_c_server:calls.
 *
 * @param request_buff The buffer containing the call's request.
 * @param from_buff The buffer containing the From element of Erlang's
 *        gen_server:handle_call.
 * @param state_buff The buffer containing the C node state.
 * @param reply The buffer where the function should store its reply by calling
 *        the appropriate ei_x_encode functions. ei_x_encode_version will be
 *        called automatically, meaning the function should not call it itself.
 */
void gcs_handle_call(
        const char *request_buff,
        const char *from_buff,
        const char *state_buff,
        ei_x_buff  *reply);

/*
 * Callback to handle gen_c_server:casts.
 *
 * @param request_buff The buffer containing the cast's request.
 * @param state_buff The buffer containing the C node state.
 * @param reply The buffer where the function should store its reply
 *        by calling the appropriate ei_x_encode functions. ei_x_encode_version
 *        will be called automatically, meaning the function should not call it
 *        itself.
 */
void gcs_handle_cast(
        const char *request_buff,
        const char *state_buff,
        ei_x_buff  *reply);

/*
 * Callback to handle gen_c_server:infos.
 *
 * @param info_buff The buffer containing the info's message.
 * @param state_buff The buffer containing the C node state.
 * @param reply The buffer where the function should store its reply
 *        by calling the appropriate ei_x_encode functions. ei_x_encode_version
 *        will be called automatically, meaning the function should not call it
 *        itself.
 */
void gcs_handle_info(
        const char *info_buff,
        const char *state_buff,
        ei_x_buff  *reply);

void gcs_terminate(const char *reason_buff, const char *state_buff);

/*
 * Decode a buffer based on the given format.
 *
 * The extra arguments are the destination for the decoded elements - or, in
 * some cases, the detailed specification of what is required.
 *
 * Format | Decode  | Argument
 * -------+---------+---------------------------------------------------------
 *  a     | atom    | char*        : Atom (must have enough space)
 *  A     | atom    | const char*  : The desired atom value
 *  l     | long    | long*        : Long
 *  p     | pid     | erlang_pid*  : Pid
 *  r     | ref     | erlang_ref*  : Reference
 *  t     | term    | const char** : Term buffer
 *  v     | version | int*         : Version
 *  {     | tuple   | int          : Number of expected elements (0 for any)
 *  }     | nothing | none         : This format is for readability purposes
 *  _     | term    | none         : Decoded term is simply skipped.
 *
 * Returns how many characters from the format string have been successfully
 * processed.
 */
int gcs_decode(const char* buffer, int *index, const char* fmt, ...);

#endif
