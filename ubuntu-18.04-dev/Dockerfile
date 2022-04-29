FROM ubuntu:18.04

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
