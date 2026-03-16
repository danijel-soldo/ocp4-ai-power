# SNO Installation Quick Fix - Missing Kernel File

## Problem
The HMC console shows:
```
Loading kernel
error: ../../grub-core/net/tftp.c:254:file /var/lib/tftpboot/rhcos/kernel not found.
Loading initrd
error: ../../grub-core/loader/powerpc/ieee1275/linux.c:333:you need to load the kernel first.
```

## Root Cause
The RHCOS kernel file is missing from the TFTP directory or has the wrong filename.

## Solution

### Step 1: Check if RHCOS files exist

```bash
# Check the TFTP directory
ls -lh /var/lib/tftpboot/rhcos/

# Expected files:
# - kernel (or rhcos-live-kernel-ppc64le)
# - initramfs.img (or rhcos-live-initramfs.ppc64le.img)
```

### Step 2: Download RHCOS files if missing

The playbook should have downloaded these, but if they're missing or have wrong names:

```bash
# Create directory if it doesn't exist
mkdir -p /var/lib/tftpboot/rhcos

# Set the RHCOS version (check your vars.yaml for the correct version)
export RHCOS_VERSION="4.13"
export RHCOS_TAG="latest"
export RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/${RHCOS_VERSION}/${RHCOS_TAG}"

# Download kernel
cd /var/lib/tftpboot/rhcos
curl -L -o kernel "${RHCOS_URL}/rhcos-live-kernel-ppc64le"

# Download initramfs
curl -L -o initramfs.img "${RHCOS_URL}/rhcos-live-initramfs.ppc64le.img"

# Verify files
ls -lh /var/lib/tftpboot/rhcos/
```

### Step 3: Download rootfs image for HTTP

```bash
# Create directory if it doesn't exist
mkdir -p /var/www/html/install

# Download rootfs
cd /var/www/html/install
curl -L -o rootfs.img "${RHCOS_URL}/rhcos-live-rootfs.ppc64le.img"

# Fix SELinux context
restorecon -vR /var/www/html || true

# Verify file
ls -lh /var/www/html/install/rootfs.img
```

### Step 4: Verify grub.cfg paths

Check that the grub configuration points to the correct file paths:

```bash
# View grub config
cat /var/lib/tftpboot/boot/grub2/grub.cfg

# The paths should match:
# linux "/rhcos/kernel" ...
# initrd "/rhcos/initramfs.img"
```

### Step 5: Verify TFTP service

```bash
# Check TFTP is enabled in dnsmasq
grep -i tftp /etc/dnsmasq.conf

# Should show:
# enable-tftp
# tftp-root=/var/lib/tftpboot

# Restart dnsmasq
systemctl restart dnsmasq

# Verify it's running
systemctl status dnsmasq
```

### Step 6: Set correct permissions

```bash
# Set ownership and permissions
chown -R dnsmasq:dnsmasq /var/lib/tftpboot/rhcos/
chmod 755 /var/lib/tftpboot/rhcos/
chmod 644 /var/lib/tftpboot/rhcos/*

# Verify
ls -lh /var/lib/tftpboot/rhcos/
```

### Step 7: Test TFTP access

```bash
# Install tftp client if not present
yum install -y tftp

# Test TFTP download from localhost
cd /tmp
tftp localhost -c get rhcos/kernel

# If successful, you should see the kernel file in /tmp
ls -lh /tmp/kernel
rm /tmp/kernel
```

### Step 8: Reboot the SNO node

After fixing the files, reboot the SNO LPAR via HMC:

```bash
# From HMC (replace with your values)
ssh <hmc_user>@<hmc_host>

# Power off the LPAR
chsysstate -r lpar -m <cec_name> -o shutdown --immed -n <lpar_name>

# Wait a few seconds, then netboot again
lpar_netboot -i -D -f -t ent -m <sno_mac> -s auto -d auto \
  -S <bastion_ip> -C <sno_ip> -G <gateway> <lpar_name> default_profile <cec_name>
```

Or use the Ansible playbook to netboot:

```bash
# From bastion
cd /path/to/ansible-bastion
ansible-playbook -i inventory playbooks/step-3-netboot-nodes.yaml
```

## Prevention

To avoid this issue, ensure the playbook completed the file download step successfully. Check the playbook output for:

```
TASK [services : Download RHCOS kernel]
TASK [services : Download RHCOS initramfs]
TASK [services : Download RHCOS rootfs]
```

If these tasks failed or were skipped, the files won't be present.

## Alternative: Manual File Check Script

Save this as `check-rhcos-files.sh`:

```bash
#!/bin/bash

echo "=== Checking RHCOS Files ==="
echo ""

# Check TFTP files
echo "1. TFTP Boot Files:"
if [ -f /var/lib/tftpboot/rhcos/kernel ]; then
    echo "   ✓ kernel exists ($(du -h /var/lib/tftpboot/rhcos/kernel | cut -f1))"
else
    echo "   ✗ kernel NOT FOUND"
fi

if [ -f /var/lib/tftpboot/rhcos/initramfs.img ]; then
    echo "   ✓ initramfs.img exists ($(du -h /var/lib/tftpboot/rhcos/initramfs.img | cut -f1))"
else
    echo "   ✗ initramfs.img NOT FOUND"
fi
echo ""

# Check HTTP files
echo "2. HTTP Install Files:"
if [ -f /var/www/html/install/rootfs.img ]; then
    echo "   ✓ rootfs.img exists ($(du -h /var/www/html/install/rootfs.img | cut -f1))"
else
    echo "   ✗ rootfs.img NOT FOUND"
fi
echo ""

# Check ignition
echo "3. Ignition Files:"
if ls /var/www/html/ignition/*.ign &>/dev/null; then
    for ign in /var/www/html/ignition/*.ign; do
        echo "   ✓ $(basename $ign) exists ($(du -h $ign | cut -f1))"
    done
else
    echo "   ✗ No ignition files found"
fi
echo ""

# Check grub config
echo "4. Grub Configuration:"
if [ -f /var/lib/tftpboot/boot/grub2/grub.cfg ]; then
    echo "   ✓ grub.cfg exists"
    echo "   Kernel path in grub.cfg:"
    grep 'linux.*kernel' /var/lib/tftpboot/boot/grub2/grub.cfg | head -1
    echo "   Initrd path in grub.cfg:"
    grep 'initrd' /var/lib/tftpboot/boot/grub2/grub.cfg | head -1
else
    echo "   ✗ grub.cfg NOT FOUND"
fi
echo ""

# Check services
echo "5. Services:"
if systemctl is-active --quiet dnsmasq; then
    echo "   ✓ dnsmasq is running"
else
    echo "   ✗ dnsmasq is NOT running"
fi

if systemctl is-active --quiet httpd; then
    echo "   ✓ httpd is running"
else
    echo "   ✗ httpd is NOT running"
fi
echo ""

echo "=== Check Complete ==="
```

Run it:
```bash
chmod +x check-rhcos-files.sh
./check-rhcos-files.sh
```

## Expected File Sizes

For reference, typical RHCOS file sizes for ppc64le:
- kernel: ~10-15 MB
- initramfs.img: ~100-150 MB
- rootfs.img: ~400-500 MB

If files are much smaller, they may be corrupted or incomplete downloads.