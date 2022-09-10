# Installation

This guide details the installation and basic usage of the GPU Query Optimizer in Postgres.

## Building postgres

### Prerequisites

1. Install CUDA following the instructions: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html

2. verify that CUDA is installed and functional:
```
$ nvcc --version
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2021 NVIDIA Corporation
Built on Sun_Mar_21_19:15:46_PDT_2021
Cuda compilation tools, release 11.3, V11.3.58
Build cuda_11.3.r11.3/compiler.29745058_0
```

3. find CUDA installation path (in my case `/usr/local/cuda`):
```
$ which nvcc
/usr/local/cuda/bin/nvcc
```

4. find GPU Compute Capability
```
$ /usr/local/cuda/extras/demo_suite/deviceQuery | grep Capability
  CUDA Capability Major/Minor version number:    6.1
```

### Installation
1. from the build folder (which can be the same as the repository root),
    run the `configure` script
```bash
# (optional) enable bitmapset extension if available
export CFLAGS="-march=native -mtune=native"
export CPPFLAGS="-march=native -mtune=native"

# where do you want to install
PG_PREFIX=/home/user/postgres/opt
mkdir -p $PG_PREFIX

# assuming you want to build in-tree, otherwise use full path to configure
# --with-icu enables unicode (used by some databases we experimented on)
# we also added --without-readline because readline was not available on our machine
./configure --prefix=$PG_PREFIX \
    --with-icu \
    --enable-cuda=/usr/local/cuda \
    --with-cudasm=61

# for debugging you might want to enable the following options:
# --enable-debug
# --enable-cassert
# --enable-depend
# and also disable compiler optimizations with
# export CFLAGS="-O0"
```

2. from the build folder run `make`
```bash
# see README for list of available options.
# we always built with profiling enabled which prints additional timing
# information.
# For debugging purposes, you might want to compile with enable_debug=yes
# pass -jN for faster build time
make -j $(nproc) enable_gpuqo_profiling=yes
```

3. finally, run `make install`

4. (optional) run `make -j $(nproc) world` and `make install-world` to get
    the extensions (used in Musicbrainz database)

### Setup
1. add the Postgres installation path to your PATH
```bash
export PATH=$PG_PREFIX/bin:$PATH
```

2. create new PGDATA folder
```bash
#
export PGDATA=/home/user/postgres/data
mkdir -p $PGDATA

initdb
```

3. run the just built Postgres daemon
```bash
PORT=6543 # default postgres port is 5432

setsid postgres -p $PORT > /tmp/pgout 2> /tmp/pgerr &

# check that it is running
less /tmp/pgerr
# LOG:  database system is ready to accept connections

# to stop the daemon you can run
# kill $(head -n 1 < $PGDATA/postmaster.pid)
```
