# 在 Proxmox 上安装 Virtual DSM (vDSM)

## vDSM 优点

 - 支持使用 virtio-balloon 进行动态调整虚拟机在宿主机上的内存占用。

## 安装步骤

### 1. 生成镜像

首先，您需要生成 Virtual DSM 的镜像。您可以使用修改过的 Docker vDSM 安装脚本 来完成这一步骤。
确保您的系统已安装 docker 和 fakeroot，并在基于 amd64 架构的 Linux 系统上运行以下命令：

```
sudo bash -c "$(curl https://raw.githubusercontent.com/awalol/virtual-dsm-proxmox-qemu/main/install.sh)"
```

执行完毕后，您将在工作目录内找到两个以 boot.img 和 system.img 结尾的文件，这些文件将用于后续步骤。

### 2. 创建虚拟机

在 Proxmox 中创建一个新的虚拟机，基本上保持默认设置即可。但需要注意以下几点：

1. 在 SCSI 控制器选项中选择 VirtIO SCSI single。

1. 暂时不要创建任何磁盘。
2. 添加一个串行接口，因为 DSM 控制台使用串行连接。

创建完成后，您的虚拟机设置应该类似于下图所示：

![image](https://github.com/awalol/virtual-dsm-proxmox-qemu/assets/61059886/ea72f9c6-e133-4150-bbf6-d838721ea406)

### 3. 导入磁盘

连接到宿主机的 shell，然后执行以下命令来导入生成的镜像文件到虚拟机中：

```
qm importdisk <vmid> <source> <storage>
```

例如：

```
qm importdisk 104 DSM_VirtualDSM_69057.boot.img slot1-1T-DATA
qm importdisk 104 DSM_VirtualDSM_69057.system.img slot1-1T-DATA
```

请注意导入镜像的顺序，您需要按正确的顺序添加硬盘。
将 boot.img 设置为 scsi9，将 system.img 设置为scsi10，添加一个新的磁盘作为数据盘 设置为scsi11

![image](https://github.com/awalol/virtual-dsm-proxmox-qemu/assets/61059886/de5f9dfd-c78d-4de6-a1e8-5461fedbe6d3)

然后，确保在 "选项 -> 引导顺序" 中启用了 scsi9 的引导选项。

### 4. 启用 virtio-balloon

要启用 virtio-balloon，您有两种方法：

#### 方法一：使用任务计划

进入控制面板 -> 任务计划。
创建一个新的触发任务，如下图所示：

![image](https://github.com/awalol/virtual-dsm-proxmox-qemu/assets/61059886/fdb4af53-2fe0-4279-9f94-1c1437d7adf3)
![image](https://github.com/awalol/virtual-dsm-proxmox-qemu/assets/61059886/05da2647-aaa7-488e-92b3-fed516ac5adf)

最后，重新启动虚拟机以确保设置生效。

#### 方法二：修改 /usr/lib/modules-load.d 

您可以参考此文章来修改 /usr/lib/modules-load.d
[SA6400 内核5.10 编译 TCP_BBR 和 流控 Fq / Cake 模块](www.openos.org/threads/sa6400-5-10-tcp_bbr-fq-cake.5146/)

## 参考资料

- [Virtual DSM 逆向笔记 (在kvm中运行VDSM)](https://jxcn.org/2022/04/vdsm-kvm/)
- [RedPill-TTG/dsm-research/vdsm-investigation.md](https://github.com/RedPill-TTG/dsm-research/blob/master/VDSM/vdsm-investigation.md#attempting-to-run-vmm-image-under-proxmox)
- [Virtual DSM in a docker container](https://github.com/vdsm/virtual-dsm)
