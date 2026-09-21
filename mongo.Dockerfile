FROM docker.io/mongo:latest

# install Python3, pip, pymongo for low memory usage healthcheck
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-pymongo && \
    rm -rf /var/lib/apt/lists/*
