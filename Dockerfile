FROM ubuntu:oracular
RUN  apt update && apt upgrade -y && apt install -y openssl curl
WORKDIR /workingdir
