#!/bin/bash

# The login node's default Slurm cluster is `inter`, so pin scancel to cm4.
# Site-specific. Drop it on a single-cluster site.
export SLURM_CLUSTERS=cm4

scancel --name=hq-workers
hq server stop
rm benchmark_2026_rush
rm nohup.out
