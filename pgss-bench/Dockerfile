FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bison flex libreadline-dev zlib1g-dev \
    libssl-dev pkg-config git ca-certificates \
    linux-perf procps psmisc \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/brendangregg/FlameGraph.git /opt/FlameGraph
ENV PATH="/opt/FlameGraph:/usr/local/pgsql/bin:${PATH}"

# perf wrapper on Debian may fail on kernel version mismatch;
# fall back to whatever perf_* binary was actually installed
RUN ln -sf $(find /usr/bin -name 'perf_*' | head -1) /usr/local/bin/perf 2>/dev/null || true

RUN useradd -m -s /bin/bash postgres \
    && install -d -o postgres -g postgres /usr/local/pgsql /tmp/pgdata /results

WORKDIR /pg-src
