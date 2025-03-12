#-------------------构建基础编译镜像
#server共用的编译环境
FROM ubuntu:22.04 AS base-image

#设置工作目录
WORKDIR /app

#必要的包
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gdb \
    git \
    curl \
    wget \
    vim \
    ninja-build

#boost库相关
RUN apt-get install -y  autotools-dev libicu-dev build-essential libbz2-dev libboost-all-dev

#更新证书
RUN apt-get  install -y ca-certificates --no-install-recommends

#下载boost源码
RUN wget https://archives.boost.io/release/1.82.0/source/boost_1_82_0.tar.gz


RUN tar zxvf boost_1_82_0.tar.gz && \
    cd boost_1_82_0 && \
    ./bootstrap.sh --prefix=/usr/ && \
    ./b2 install -j$(nproc)

#下载安装cmake
RUN wget https://github.com/Kitware/CMake/releases/download/v3.27.0/cmake-3.27.0.tar.gz && \
    apt install libssl-dev -y && \
    tar -zxvf cmake-3.27.0.tar.gz && \
    cd cmake-3.27.0 && \
    ./bootstrap && \
    make -j$(nproc) && \
    make install && \
    cmake --version
    
#jsoncpp安装
RUN apt-get install -y libjsoncpp-dev

#调整jsoncpp的位置和项目所使用的路径相同
RUN mv /usr/include/jsoncpp/json /usr/include/json

#grpc安装相关
RUN git clone -b v1.34.0 https://gitee.com/mirrors/grpc-framework.git grpc && \
    cd grpc && \
    git submodule update --init 

#编译
RUN cd grpc && mkdir build && \
    cd build && \
    sed -i '1i#include <limits>' ../third_party/abseil-cpp/absl/synchronization/internal/graphcycles.cc && \
    sed -i 's/std::max(SIGSTKSZ, 65536)/std::max(SIGSTKSZ, static_cast<long int>(65536))/g' ../third_party/abseil-cpp/absl/debugging/failure_signal_handler.cc && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -G Ninja  && \
    ninja && \
    ninja install

#安装 hiredis
WORKDIR /app
RUN git clone https://github.com/redis/hiredis.git && \
    cd hiredis && \
    mkdir build && \
    cd build && \
    cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release && \
    ninja && \
    ninja install

#安装 redis-plus-plux
RUN git clone https://github.com/sewenew/redis-plus-plus.git && \
    cd redis-plus-plus && \
    mkdir build && \
    cd build && \
    cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release && \
    ninja && \
    ninja install

#安装 mysql-connector-c++
RUN wget  https://downloads.mysql.com/archives/get/p/20/file/mysql-connector-c%2B%2B-8.3.0-src.tar.gz && \
    tar -zxvf mysql-connector-c++-8.3.0-src.tar.gz && \
    cd mysql-connector-c++-8.3.0-src && \
    mkdir build && \
    cd build && \
    apt install libmysqlclient-dev -y && \
    cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DWITH_JDBC=ON -DCMAKE_BUILD_TYPE=Release && \
    ninja && \
    ninja install

#更新环境变量
RUN echo "/usr/lib64" >> /etc/ld.so.conf.d/mysql-connector-cpp.conf && \
    ldconfig

#清理现场
WORKDIR /
RUN rm -rf /app

#chatServer的编译
FROM base-image AS chatserver-builder

WORKDIR /root/code

#传递git仓库最新的commit-id
ARG COMMIT_SHA

RUN git clone https://github.com/github-newstar/chatServer.git && \
    cd chatServer && \
    mkdir build && \
    cd build && \
    cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release && \
    ninja

FROM ubuntu:22.04 AS chatserver-final
WORKDIR /root
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libicu70 \
    libssl3 \
    libstdc++6 \
    libmysqlclient21 \
    && rm -rf /var/lib/apt/lists/*

# 从构建阶段复制必要的库文件
# Boost库
COPY --from=builder /usr/lib/libboost_*.so* /usr/lib/

# JsonCpp库
COPY --from=builder /usr/lib/x86_64-linux-gnu/libjsoncpp* /usr/lib

# gRPC及相关库
COPY --from=builder /usr/lib/libgrpc*.so* /usr/lib/
COPY --from=builder /usr/lib/libprotobuf.so* /usr/lib/
COPY --from=builder /usr/lib/libabsl*.so* /usr/lib/
COPY --from=builder /usr/lib/libupb*.so* /usr/lib/
COPY --from=builder /usr/lib/libaddress_sorting.so* /usr/lib/
COPY --from=builder /usr/lib/libgpr.so* /usr/lib/

# Redis相关库
COPY --from=builder /usr/lib/x86_64-linux-gnu/libredis* /usr/lib/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libhiredis* /usr/lib/
COPY --from=builder /usr/lib/libredis++.so* /usr/lib/

# MySQL C++ 连接器
COPY --from=builder /usr/lib64/libmysqlcppconn*.so* /usr/lib64/

# 拷贝二进制文件
COPY --from=chatServer-builder /root/code/chatServer/build/chatServer /root/chatServer/chatServer
COPY --from=chatServer-builder /root/code/chatServer/build/config.ii  /root/chatServer/config.ii

# 更新动态链接器配置
RUN echo "/usr/lib64" >> /etc/ld.so.conf.d/mysql-connector-cpp.conf && \
    ldconfig

WORKDIR /root/chatServer
CMD ["/root/chatServer/chatServer"]
