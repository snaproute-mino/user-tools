# cnnos-monolithic hosting server

## Running via docker (this will run dhcp/nginx server on all interfaces)
docker run --rm -it --name cnnos-monolithic --net=host cnnos-monolithic


## Running on only the default interface (where default route is learned)
DEFAULT_INTERFACE="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
HOST_HTTP_SERVER_PORT=8888
docker run --rm -it --name cnnos-monolithic --net=host \
    -e "HOST_HTTP_SERVER_PORT=${HOST_HTTP_SERVER_PORT}" \
    -e "INTERFACES=${DEFAULT_INTERFACE}" \
    cnnos-monolithic

## Running on multiple interfaces
INTERFACES="eth0 eth1"
HOST_HTTP_SERVER_PORT=8888
docker run --rm -it --name cnnos-monolithic --net=host \
    -e "HOST_HTTP_SERVER_PORT=${HOST_HTTP_SERVER_PORT}" \
    -e "INTERFACES=${INTERFACES}" \
    cnnos-monolithic