ARG ALPINE_VERSION=3.15
FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache build-base zlib-dev bzip2-dev xz-dev ncurses-dev \
    readline-dev sqlite-dev openssl-dev libffi-dev linux-headers wget file

# Download and extract Python 3.12 (3.14 needs OpenSSL 3.0+, absent on Alpine 3.15)
ARG PYTHON_VERSION=3.12.12

RUN cd /opt && \
    wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
    tar xzf Python-${PYTHON_VERSION}.tgz && mv /opt/Python-${PYTHON_VERSION} /opt/python

ARG SQLITE_VERSION=3460100
RUN cd /opt && \
    wget https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz && \
    tar xzf sqlite-autoconf-${SQLITE_VERSION}.tar.gz && \
    mv /opt/sqlite-autoconf-${SQLITE_VERSION} /opt/sqlite
