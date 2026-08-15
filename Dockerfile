FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        clang \
        cpio \
        device-tree-compiler \
        dwarves \
        flex \
        git \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        lld \
        llvm \
        python3 \
        rsync \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
