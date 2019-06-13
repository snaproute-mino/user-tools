FROM alpine:latest as downloader

RUN apk add --no-cache bash curl

WORKDIR /data/monolithic

ARG MONOLITHIC_URL

ADD builder/ /context

RUN /context/copy-monolithic

FROM nginx:1.17.0-alpine

RUN apk add --no-cache tini bash dhcp dhcrelay

COPY --from=downloader /data /data

ARG DHCP_TEMPLATE_FILE=run/dhcpd.conf

ADD run/entrypoint.sh /usr/local/bin/entrypoint.sh
ADD run/generate-dhcpd-config /usr/local/bin
ADD run/generate-nginx-config /usr/local/bin

# this port is handled by nginx
EXPOSE 80/tcp

# this port will be handled by relay agent
EXPOSE 67/udp 67/tcp

VOLUME ["/etc/dhcp"]
VOLUME ["/var/lib/dhcp"]
VOLUME ["/var/log/"]

STOPSIGNAL SIGTERM

ENTRYPOINT [ "/sbin/tini", "--", "/usr/local/bin/entrypoint.sh" ]
CMD []