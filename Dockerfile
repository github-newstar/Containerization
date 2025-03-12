#chatServer cpp env
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gdb \
    git \
    curl \
    wget \
    vim \


