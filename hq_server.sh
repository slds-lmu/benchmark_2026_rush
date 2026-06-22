nohup hq server start --journal benchmark_2026_rush &

hq alloc add slurm \
  --worker-start-cmd "source /dss/dsshome1/00/ra98ror2/benchmark_2026_rush/hq_env.sh" \
  --time-limit 24h \
  --cpus 112 \
  --backlog 25 \
  --idle-timeout 10m \
  --max-workers-per-alloc 1\
  -- --clusters=cm4 \
  --partition=cm4_tiny \
  --qos=cm4_tiny \
  --ntasks=112 \
  --get-user-env \
  --export=NONE

hq server stop
rm benchmark_2026_rush
rm nohup.out
