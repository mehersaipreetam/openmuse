FROM node:22.22.0-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash python3 python3-pip python3-venv python3-dev \
       build-essential ca-certificates curl git coreutils \
       python3-numpy python3-pandas python3-scipy python3-matplotlib \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/openmuse /workspace \
    && chown 1000:1000 /workspace

COPY files.py /opt/openmuse/files.py
RUN chmod 0555 /opt/openmuse/files.py

ENV HOME=/workspace LANG=C.UTF-8 PIP_BREAK_SYSTEM_PACKAGES=1
WORKDIR /workspace
USER 1000:1000
VOLUME ["/workspace"]
ENTRYPOINT ["/usr/bin/sleep"]
CMD ["infinity"]
