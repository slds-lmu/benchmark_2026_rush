#!/bin/bash

# Site-specific. This is how the compute nodes reach Slurm and conda. LRZ needs
# the slurm_setup module and exposes conda through ~/.conda_init, elsewhere
# `module load conda` may be all it takes.
module load slurm_setup

source ~/.conda_init

conda activate benchmark_2026_rush
