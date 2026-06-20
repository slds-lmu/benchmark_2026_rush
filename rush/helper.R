start_redis = function(job) {
  redis_file = sprintf("redis_%s", job$job.id)
  socket_path = sprintf("/tmp/%s.sock", redis_file)
  system(sprintf("redis-server --port 0 --unixsocket %s --daemonize yes --pidfile /tmp/%s.pid --dir %s --save '' --appendonly no", socket_path, redis_file, tempdir()))
  timeout = Sys.time() + 30
  while (!file.exists(socket_path) && Sys.time() < timeout) Sys.sleep(0.1)
  if (!file.exists(socket_path)) stop("Redis failed to start")
  redux::redis_config(path = socket_path)
}