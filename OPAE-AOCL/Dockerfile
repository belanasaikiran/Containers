# FROM debian:unstable-slim AS builder
FROM ubuntu:18.04

# Install build dependencies
RUN apt-get update && apt-get install -y curl python3-dev git gcc g++ make cmake uuid-dev libjson-c-dev libedit-dev libudev-dev

# Download and unpack OPAE tarball
ARG OPAE_RELEASE=2.1.0-1
ARG OPAE_SHA256=0c9f52ff1279ca5e34e64828ddf3a6c001fb2969a6349a966cd9515c1048ea01

RUN mkdir -p /usr/src/opae && \
    cd /usr/src/opae && \
    curl -fsSL https://github.com/OPAE/opae-sdk/archive/${OPAE_RELEASE}.tar.gz -o opae.tar.gz && \
    echo "$OPAE_SHA256 opae.tar.gz" | sha256sum -c - && \
    tar -xzf opae.tar.gz && \
    rm -f opae.tar.gz

# Build OPAE
RUN cd /usr/src/opae/opae-sdk-${OPAE_RELEASE} && \
    mkdir build && \
    cd build && \
    CFLAGS="$CFLAGS -Wno-misleading-indentation" \
    cmake .. && \
    make -j xfpga nlb0 nlb3

WORKDIR /work

COPY ../scripts/. ./

RUN apt-get -y update \
  && apt-get -y install software-properties-common \
  && add-apt-repository ppa:git-core/ppa \
  && DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  git \
  jq \
  libelf-dev \
  libtinfo5 \
  libxml2 \
  ninja-build \
  python3 \
  sudo \
  zlib1g-dev \
  && apt-get -y clean \
  && ./install_aocl.sh /opt/aocl \
  && useradd --system --user-group --shell /sbin/nologin --create-home --home-dir /home/build build \
  && echo 'build ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/build \
  && rm -rf "$PWD"

USER build
WORKDIR /home/build

ENV PATH="/opt/aocl/hld/bin:$PATH"
RUN aoc -version
