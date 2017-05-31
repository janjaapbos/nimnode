// $ gcc -I/opt/libuv/include -o exam exam.c /opt/libuv/lib/libuv.so
// $ LD_LIBRARY_PATH=/opt/libuv/lib ./exam
#include <stdio.h>
#include <stdlib.h>
#include <uv.h>

void exit_cb(uv_process_t *child, int64_t exit_status, int term_signal) {
  fprintf(stderr, "Process exited with status %ld, signal %d\n", exit_status, term_signal);
  uv_close((uv_handle_t*) child, NULL);
}

void read_cb(uv_stream_t* stream, ssize_t nread, const uv_buf_t* buf) {
  if (nread == UV_EOF) {
    fprintf(stdout, "read: finished\n");
  } else {
    fprintf(stdout, "read: %ld size, %s\n", nread, buf->base);
  }
}

void alloc_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf) {
  static char buffer[1024];
  buf->base = buffer;
  buf->len = sizeof(buffer);
}

uv_process_t child;
uv_process_options_t options;
int main(int argc, char** argv) {
  int err = 0;
  char* args[3];
  args[0] = "/usr/bin/nim";
  args[1] = "help"; 
  args[2] = NULL;

  options.stdio_count = 3;
  // uv_stdio_container_t child_stdio[3];
  // child_stdio[0].flags = UV_IGNORE;
  // child_stdio[1].flags = UV_INHERIT_FD;
  // child_stdio[1].data.fd = 1;
  // child_stdio[2].flags = UV_INHERIT_FD;
  // child_stdio[2].data.fd = 2;
  // options.stdio = child_stdio;

  uv_stdio_container_t *child_stdio = (uv_stdio_container_t *)malloc(3 * sizeof(uv_stdio_container_t));
  child_stdio->flags = UV_IGNORE;
  (child_stdio + 1)->flags = UV_INHERIT_FD;
  (child_stdio + 1)->data.fd = 1;
  uv_pipe_t *pipe = malloc(sizeof(uv_pipe_t));
  if (err = uv_pipe_init(uv_default_loop(), pipe, 1)) {
    fprintf(stderr, "ERROR: %s\n", uv_strerror(err));
    return 1;
  }
  (child_stdio + 2)->flags = UV_CREATE_PIPE | UV_READABLE_PIPE;
  //(child_stdio + 2)->data.fd = 2;
  (child_stdio + 2)->data.stream = (uv_stream_t *)pipe;
  options.stdio = child_stdio;

  options.exit_cb = exit_cb;
  options.file = "/usr/bin/nim";
  options.args = args;
  //options.flags = UV_PROCESS_SETUID | UV_PROCESS_SETGID;

  printf("UV_PROCESS_SETUID | UV_PROCESS_SETGID: %d\n", UV_PROCESS_SETUID | UV_PROCESS_SETGID);

  if ((err = uv_spawn(uv_default_loop(), &child, &options))) {
    fprintf(stderr, "ERROR: %s\n", uv_strerror(err));
    return 1;
  }

  if (err = uv_read_start((uv_stream_t *)pipe, alloc_cb, read_cb)) {
    fprintf(stderr, "ERROR: %s\n", uv_strerror(err));
    return 1;
  }

  return uv_run(uv_default_loop(), UV_RUN_DEFAULT);
}





