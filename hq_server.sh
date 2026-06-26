# The login node's default Slurm cluster is `inter`, but worker allocations are
# submitted to the `cm4` cluster (see --clusters=cm4 below). HyperQueue's
# automatic allocator polls allocation state with plain `scontrol`/`sacct`, which
# would otherwise hit `inter` and fail with "Invalid job id specified", so the
# server never sees its workers come up. Pin every Slurm call to cm4.
export SLURM_CLUSTERS=cm4

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
