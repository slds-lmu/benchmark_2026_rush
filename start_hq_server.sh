nohup hq server start --journal rush_paper_2026 &

hq alloc add slurm \
  --worker-start-cmd "source /dss/dsshome1/00/ra98ror2/paper_2026_rush/load_env.sh" \
  --time-limit 24h \
  --cpus 112 \
  --backlog 25 \
  --idle-timeout 2h \
  --max-workers-per-alloc 1\
  -- --clusters=cm4 \
  --partition=cm4_tiny \
  --qos=cm4_tiny \
  --ntasks=112 \
  --get-user-env \
  --export=NONE

hq server stop
rm rush_paper_2026
rm nohup.out

redis-server --protected-mode no --save "" --appendonly no

source("/dss/dsshome1/00/ra98ror2/paper_2026_rush/launch.R")


