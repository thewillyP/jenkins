FROM ubuntu:22.04

RUN apt-get update && apt-get install -y openssh-server && apt-get clean && \
    mkdir -p /var/run/sshd /hostkeys

COPY start-sshd.sh /usr/local/bin/start-sshd.sh
RUN chmod +x /usr/local/bin/start-sshd.sh

EXPOSE 2222

CMD ["/usr/local/bin/start-sshd.sh"]