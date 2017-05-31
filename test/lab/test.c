// $ gcc -I/opt/libuv/include -o test test.c /opt/libuv/lib/libuv.so
// $ LD_LIBRARY_PATH=/opt/libuv/lib ./test
#include <stdio.h>
#include <uv.h>

int64_t counter = 0;

void callback(uv_idle_t* handle, int status) {
  printf("wait: %ld\n", counter);
  counter++;

  if (counter >= 3) {
    printf("stop: %ld\n", counter);
    uv_idle_stop(handle);
  }
}

int main() {
  const char* err = uv_strerror(UV_EFBIG);
  printf("uv_strerror(UV_EFBIG): %s\n", err);

  // uv_idle_t idler;

  // uv_idle_init(uv_default_loop(), &idler);
  // uv_idle_start(&idler, callback);
  
  // printf("..................... ->\n");
  // uv_loop_t* handle = uv_default_loop();
  // int ret = uv_run(handle, UV_RUN_DEFAULT);
  // printf("..................... OK: %d\n", ret);

  // printf("uv_loop_alive: %d\n", uv_loop_alive(handle));
  // printf("uv_loop_size: %ld\n", uv_loop_size());
  // printf("uv_backend_fd: %d\n", uv_backend_fd(handle));
  // printf("uv_now: %ld\n", uv_now(handle));

  return 0;
}