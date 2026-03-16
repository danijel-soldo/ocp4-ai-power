# SNO (Single Node OpenShift) Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PowerVM Environment                                 │
│                                                                              │
│  ┌────────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │     Bastion LPAR                   │  │     SNO LPAR                 │  │
│  │  ┌──────────────────────────────┐  │  │                              │  │
│  │  │ IP: 9.47.87.83               │  │  │  IP: 9.47.87.82              │  │
│  │  │ vCPU: 2                      │  │  │  vCPU: 8                     │  │
│  │  │ Memory: 8GB                  │  │  │  Memory: 16GB                │  │
│  │  │ Storage: 50GB                │  │  │  Storage: 120GB              │  │
│  │  └──────────────────────────────┘  │  │                              │  │
│  │                                     │  │  ┌────────────────────────┐  │  │
│  │  Services Running:                  │  │  │  OpenShift Single Node │  │  │
│  │  ┌──────────────────────────────┐  │  │  │                        │  │  │
│  │  │ 1. dnsmasq                   │  │  │  │  - Control Plane       │  │  │
│  │  │    • DNS Server              │  │  │  │  - Worker Node         │  │  │
│  │  │      - api.sno.ocp.io        │  │  │  │  - All OCP Services    │  │  │
│  │  │      - api-int.sno.ocp.io    │  │  │  └────────────────────────┘  │  │
│  │  │      - *.apps.sno.ocp.io     │  │  │                              │  │
│  │  │    • DHCP Server             │  │  │  MAC: fa:b0:45:27:43:20      │  │
│  │  │      - IP Assignment         │  │  │                              │  │
│  │  │      - PXE Boot Config       │  │  │  Boot: PXE Network Boot      │  │
│  │  │    • TFTP Server             │  │  │                              │  │
│  │  │      - PXE Boot Files        │  │  └──────────────────────────────┘  │
│  │  │      - /var/lib/tftpboot     │  │                                    │
│  │  └──────────────────────────────┘  │                                    │
│  │                                     │                                    │
│  │  ┌──────────────────────────────┐  │                                    │
│  │  │ 2. httpd (Apache)            │  │                                    │
│  │  │    • Port: 8000              │  │                                    │
│  │  │    • Serves:                 │  │                                    │
│  │  │      - Ignition files        │  │                                    │
│  │  │        /ignition/sno.ign     │  │                                    │
│  │  │      - RHCOS rootfs image    │  │                                    │
│  │  │        /install/rootfs.img   │  │                                    │
│  │  └──────────────────────────────┘  │                                    │
│  │                                     │                                    │
│  │  ┌──────────────────────────────┐  │                                    │
│  │  │ 3. grub2 (PXE)               │  │                                    │
│  │  │    • Network Boot Config     │  │                                    │
│  │  │    • RHCOS Kernel            │  │                                    │
│  │  │    • RHCOS Initramfs         │  │                                    │
│  │  │    • Boot Parameters         │  │                                    │
│  │  └──────────────────────────────┘  │                                    │
│  │                                     │                                    │
│  │  File Structure:                    │                                    │
│  │  • /etc/dnsmasq.conf                │                                    │
│  │  • /etc/dnsmasq.d/addnhosts         │                                    │
│  │  • /var/lib/tftpboot/               │                                    │
│  │    └─ boot/grub2/grub.cfg           │                                    │
│  │    └─ rhcos/kernel                  │                                    │
│  │    └─ rhcos/initramfs.img           │                                    │
│  │  • /var/www/html/                   │                                    │
│  │    └─ ignition/sno.ign              │                                    │
│  │    └─ install/rootfs.img            │                                    │
│  └─────────────────────────────────────┘                                    │
│                                                                              │
│  Network Configuration:                                                      │
│  • Subnet: 9.47.80.0/20                                                      │
│  • Gateway: 9.47.95.254                                                      │
│  • DNS: 9.47.87.83 (Bastion)                                                 │
│  • Domain: sno.ocp.io                                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

Installation Flow:
═════════════════

1. Bastion Setup
   └─> Configure dnsmasq (DNS/DHCP/TFTP)
   └─> Configure httpd (HTTP server)
   └─> Setup PXE boot files (grub2)
   └─> Create ignition file (openshift-install)
   └─> Download RHCOS images

2. SNO Installation
   └─> Network boot SNO LPAR via PXE
   └─> DHCP assigns IP to SNO
   └─> PXE loads kernel & initramfs
   └─> Downloads rootfs from HTTP
   └─> Applies ignition configuration
   └─> Installs OpenShift

3. Monitoring
   └─> openshift-install wait-for bootstrap-complete
   └─> openshift-install wait-for install-complete
   └─> oc get nodes / oc get co

Key Services Summary:
════════════════════

Bastion LPAR Services:
• dnsmasq    - DNS, DHCP, TFTP (PXE)
• httpd      - HTTP server for ignition & RHCOS images
• grub2      - Network boot configuration

SNO LPAR:
• Single Node OpenShift (Control Plane + Worker)