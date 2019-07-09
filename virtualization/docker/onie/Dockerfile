FROM debian:9 as oniebuilder

# Add initial development packages
RUN apt-get update && apt-get install -y \
    build-essential stgit u-boot-tools util-linux \
    gperf device-tree-compiler python-all-dev xorriso \
    autoconf automake bison flex texinfo libtool libtool-bin \
    realpath gawk libncurses5 libncurses5-dev bc \
    dosfstools mtools pkg-config git wget help2man libexpat1 \
    libexpat1-dev fakeroot python-sphinx rst2pdf \
    libefivar-dev libnss3-tools libnss3-dev libpopt-dev \
    libssl-dev sbsigntool uuid-runtime uuid-dev cpio \
    bsdmainutils curl sudo

# Create build user
RUN useradd -m -s /bin/bash build && \
    adduser build sudo && \
    echo "build:build" | chpasswd && \
    mkdir --mode=0777 -p /local/onie

USER build

RUN git config --global user.email "build@onie.local" && \
    git config --global user.name "ONIE Build"

WORKDIR /local/onie

RUN git clone https://github.com/opencomputeproject/onie /local/onie 

RUN sed -i 's/^#EXTRA_CMDLINE_LINUX.*/EXTRA_CMDLINE_LINUX ?= dhcp=eth0,eth1/' machine/kvm_x86_64/machine.make && \
    sed -i "s/^#.*RECOVERY_DEFAULT_ENTRY.*/RECOVERY_DEFAULT_ENTRY = embed/" machine/kvm_x86_64/machine.make && \
    sed -i 's#true ${onie_dhcp="$val"}#true ${onie_dhcp="${val//,/ }"}#' machine/kvm_x86_64/machine.make && \
    sed -i 's#echo "Post installation hook"# \
        echo "Post installation hook"\n \
        local embed=$(grep 'embed' /proc/cmdline | wc -l)\n \
        echo "checking /proc/cmdline for embed: $embed" \n \
        if [ "$embed" == "1" ]; then \n \
            poweroff \n \
        fi#' machine/kvm_x86_64/installer.conf && \
        cat machine/kvm_x86_64/installer.conf && \
    cd /local/onie/build-config && \
    make -j4 MACHINE=kvm_x86_64 recovery-iso

# +    local embed=$(grep 'embed' /proc/cmdline | wc -l)
# +    echo "checking /proc/cmdline for embed: $embed"
# +    if [ "$embed" == "1" ]; then
# +        poweroff
# +    fi

ARG DISK_SIZE=8G

FROM fedora:29 AS builder

ENV DEBIAN_FRONTEND noninteractive
ENV LIBGUESTFS_BACKEND=direct

RUN dnf -y update && \
    dnf -y install \
        libguestfs-tools \
        qemu-kvm \
        libvirt \
        virt-install \
    && \
    dnf -y clean all

COPY --from=oniebuilder /local/onie/build/images/onie-recovery-x86_64-kvm_x86_64-r0.iso /source/

WORKDIR /local

RUN qemu-img create -f qcow2 /local/disk-installed.qcow2 8G && \
    qemu-system-x86_64 \
        -name "onie" \
        -boot "order=cd,once=d" \
        -cdrom /source/onie-recovery-x86_64-kvm_x86_64-r0.iso \
        -drive file=/local/disk-installed.qcow2,media=disk,if=virtio,index=0 \
        -serial mon:stdio \
        -nographic

ARG DISK_SIZE=8G

RUN echo "creating a ${DISK_SIZE} disk" && \
    qemu-img create -f qcow2 /local/disk.qcow2 ${DISK_SIZE}

RUN virt-resize -v -x /local/disk-installed.qcow2 /local/disk.qcow2

FROM kubevirt/container-disk-v1alpha
COPY --from=builder /local/disk.qcow2 /disk