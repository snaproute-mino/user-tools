FROM fedora AS builder

ENV DEBIAN_FRONTEND noninteractive

RUN dnf -y update && \
    dnf -y install \
        libguestfs-tools \
        qemu-kvm \
        libvirt \
        virt-install \
    && \
    dnf -y clean all

ENV LIBGUESTFS_BACKEND=direct

#       qemu-utils \
#        libvirt-bin \
#        libvirt-dev \
#        libvirt-daemon \
#        libvirt-daemon-config-network \
#        python-libvirt \

ARG DISK_SIZE=8

WORKDIR /local/
ADD onie-recovery-x86_64-kvm_x86_64-r0.iso /source/


RUN qemu-img create -f qcow2 onie-installed.qcow2 8G && \
    qemu-system-x86_64 \
        -name "onie" \
        -boot "order=cd,once=d" \
        -cdrom /source/onie-recovery-x86_64-kvm_x86_64-r0.iso \
        -drive file=/local/onie-installed.qcow2,media=disk,if=virtio,index=0 \
        -serial mon:stdio \
        -nographic


RUN qemu-img create -f qcow2 /local/onie.qcow2 ${DISK_SIZE}G && \
    virt-resize -v -x /local/onie-installed.qcow2 /local/onie.qcow2

FROM kubevirt/container-disk-v1alpha
COPY --from=builder /local/onie.qcow2 /disk
