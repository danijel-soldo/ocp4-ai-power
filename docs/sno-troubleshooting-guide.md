# SNO Installation Troubleshooting Guide

## SSH Connection Timeout Error

If you encounter this error during SNO installation:
```
TASK [Check connection] *********************************************************************************
fatal: [10.0.10.103]: FAILED! => {"changed": false, "elapsed": 2715, "msg": "timed out waiting for ping module test: Failed to connect to the host via ssh: ssh: connect to host 10.0.10.103 port 22: Connection timed out"}
```

This occurs during the "Set boot order for SNO" play when Ansible tries to SSH into the SNO node but cannot connect.

## Root Causes

1. **SNO node not fully booted yet** - The node might still be installing RHCOS and hasn't reached the point where SSH is available
2. **SSH service not started** - CoreOS might not have started the SSH daemon yet
3. **Network connectivity issues** - Firewall, routing, or network configuration problems
4. **Wrong SSH key** - The SSH key used by Ansible might not match what was configured in the ignition file
5. **Node installation failed** - The PXE boot or ignition process might have failed

## Debugging Steps

### 1. Check Network Connectivity

From your bastion host, test basic connectivity:

```bash
# Test network connectivity
ping -c 4 10.0.10.103

# Check if SSH port is open
nc -zv 10.0.10.103 22

# Try SSH manually with verbose output
ssh -v core@10.0.10.103
```

### 2. Check SNO Node Console

Access the LPAR console through HMC to see what's happening:
- Is the node stuck at boot?
- Are there any error messages?
- Has RHCOS been installed to disk?
- Is the installation still in progress?

### 3. Verify Bastion Services

Check that all required services are running on the bastion:

```bash
# Check dnsmasq (DNS/DHCP/TFTP)
systemctl status dnsmasq

# Check httpd
systemctl status httpd

# Check if SNO node got an IP via DHCP
cat /var/lib/dnsmasq/dnsmasq.leases | grep "10.0.10.103"

# Check dnsmasq logs
journalctl -u dnsmasq -n 50
```

### 4. Verify Ignition File

Check if the ignition file was created correctly:

```bash
# Check if ignition file exists
ls -lh /var/www/html/ignition/*.ign

# Validate the ignition file contains SSH key
cat /var/www/html/ignition/*.ign | jq '.passwd.users[0].sshAuthorizedKeys'

# If jq is not installed, use grep
grep -A 5 "sshAuthorizedKeys" /var/www/html/ignition/*.ign
```

### 5. Check PXE Boot Files

Verify that RHCOS files are in place:

```bash
# Check TFTP boot files
ls -lh /var/lib/tftpboot/rhcos/
ls -lh /var/lib/tftpboot/boot/grub2/grub.cfg

# Check HTTP files
ls -lh /var/www/html/install/rootfs.img
ls -lh /var/www/html/ignition/
```

### 6. Review Configuration

Check your vars.yaml file for correct configuration:

```bash
# View your configuration
cat /path/to/your/vars.yaml
```

Verify:
- `install_type: sno`
- Correct IP address for the SNO node
- Correct MAC address
- Correct SSH public key
- Correct disk device path (e.g., `/dev/sda` or `/dev/disk/by-id/...`)
- Correct HMC details (`pvm_hmc`, `pvmcec`, `pvmlpar`)

### 7. Check Installation Progress

If you can access the SNO node console, check the installation logs:

```bash
# From the SNO node console (if accessible)
journalctl -b | grep -i ignition
journalctl -b | grep -i ssh
journalctl -b | grep -i coreos

# Check if SSH is running
systemctl status sshd
```

## Solutions

### Solution 1: Wait for Installation to Complete

The most common issue is that the playbook tries to SSH too early. The SNO installation can take 30-60 minutes.

**Steps:**
1. Monitor the SNO node console to see installation progress
2. Wait for the message "Bootstrap complete" or similar
3. Verify SSH is accessible: `ssh core@10.0.10.103`
4. Once SSH works, re-run the playbook or just the failed task

### Solution 2: Increase Timeout

If the node just needs more time, increase the timeout in your vars.yaml:

```yaml
# Add this to your vars.yaml
node_connection_timeout: 3600  # 60 minutes instead of default 45 minutes
```

### Solution 3: Skip Boot Order Step Temporarily

If you want to proceed without setting the boot order (you can do it manually later):

1. Edit `ansible-bastion/playbooks/main.yaml`
2. Comment out lines 49-57 (the "Set boot order for SNO" play)
3. Re-run the playbook
4. Manually set boot order later via HMC:

```bash
# From HMC, set boot order to disk
ssh <hmc_user>@<hmc_host> "chsyscfg -r lpar -m <cec_name> -i 'name=<lpar_name>,boot_mode=norm,bootlist=<disk_device>'"
```

### Solution 4: Manual Boot Order Setting

After the SNO installation completes and SSH is accessible, manually set the boot order:

```bash
# SSH into the SNO node
ssh core@10.0.10.103

# Set boot order to disk (replace /dev/sda with your actual disk)
sudo /usr/sbin/bootlist -m normal -o /dev/sda
```

### Solution 5: Fix Network/SSH Issues

If network connectivity or SSH is the problem:

1. **Check firewall on bastion:**
   ```bash
   # Check if firewall is blocking SSH
   firewall-cmd --list-all
   
   # If needed, allow SSH
   firewall-cmd --permanent --add-service=ssh
   firewall-cmd --reload
   ```

2. **Verify SSH key:**
   ```bash
   # Check if your SSH key is in the ignition file
   cat /var/www/html/ignition/*.ign | grep "$(cat ~/.ssh/id_rsa.pub | cut -d' ' -f2)"
   ```

3. **Check SELinux:**
   ```bash
   # Check SELinux status
   getenforce
   
   # If enforcing, check for denials
   ausearch -m avc -ts recent
   ```

## Automated Troubleshooting Script

Save this as `check-sno-status.sh` on your bastion:

```bash
#!/bin/bash

SNO_IP="${1:-10.0.10.103}"

echo "=== SNO Troubleshooting Script ==="
echo "Checking SNO node: $SNO_IP"
echo ""

echo "1. Network Connectivity:"
if ping -c 2 -W 2 $SNO_IP &>/dev/null; then
    echo "   ✓ Node is pingable"
else
    echo "   ✗ Node is NOT pingable"
fi
echo ""

echo "2. SSH Port Status:"
if nc -zv -w 2 $SNO_IP 22 2>&1 | grep -q succeeded; then
    echo "   ✓ SSH port 22 is open"
else
    echo "   ✗ SSH port 22 is NOT open"
fi
echo ""

echo "3. Bastion Services:"
for service in dnsmasq httpd; do
    if systemctl is-active --quiet $service; then
        echo "   ✓ $service is running"
    else
        echo "   ✗ $service is NOT running"
    fi
done
echo ""

echo "4. DHCP Lease:"
if grep -q "$SNO_IP" /var/lib/dnsmasq/dnsmasq.leases 2>/dev/null; then
    echo "   ✓ DHCP lease found:"
    grep "$SNO_IP" /var/lib/dnsmasq/dnsmasq.leases
else
    echo "   ✗ No DHCP lease found for $SNO_IP"
fi
echo ""

echo "5. Ignition File:"
if ls /var/www/html/ignition/*.ign &>/dev/null; then
    echo "   ✓ Ignition file exists:"
    ls -lh /var/www/html/ignition/*.ign
else
    echo "   ✗ No ignition file found"
fi
echo ""

echo "6. RHCOS Files:"
if [ -f /var/www/html/install/rootfs.img ]; then
    echo "   ✓ rootfs.img exists"
else
    echo "   ✗ rootfs.img NOT found"
fi
if [ -f /var/lib/tftpboot/rhcos/kernel ]; then
    echo "   ✓ kernel exists"
else
    echo "   ✗ kernel NOT found"
fi
if [ -f /var/lib/tftpboot/rhcos/initramfs.img ]; then
    echo "   ✓ initramfs.img exists"
else
    echo "   ✗ initramfs.img NOT found"
fi
echo ""

echo "7. SSH Test:"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no core@$SNO_IP "echo 'SSH works'" 2>/dev/null; then
    echo "   ✓ SSH connection successful"
else
    echo "   ✗ SSH connection failed"
fi
echo ""

echo "=== Troubleshooting Complete ==="
echo ""
echo "Next steps:"
echo "- If node is not pingable: Check network configuration and HMC console"
echo "- If SSH port not open: Node may still be installing, check console"
echo "- If services not running: Start them with 'systemctl start <service>'"
echo "- If SSH fails: Check SSH key in ignition file and wait for installation to complete"
```

Make it executable and run it:

```bash
chmod +x check-sno-status.sh
./check-sno-status.sh 10.0.10.103
```

## Common Scenarios

### Scenario 1: Installation Still in Progress
**Symptoms:** Node is pingable but SSH port not open
**Solution:** Wait for installation to complete (30-60 minutes), monitor console

### Scenario 2: Installation Failed
**Symptoms:** Node stuck at boot, error messages in console
**Solution:** Check ignition file, verify PXE boot configuration, restart installation

### Scenario 3: Network Issues
**Symptoms:** Node not pingable
**Solution:** Check DHCP configuration, verify network settings in HMC, check bastion network interface

### Scenario 4: SSH Key Mismatch
**Symptoms:** SSH port open but authentication fails
**Solution:** Verify SSH public key in ignition file matches your private key

## Prevention

To avoid this issue in future installations:

1. **Monitor the console** during installation
2. **Wait for bootstrap complete** before expecting SSH access
3. **Test connectivity** manually before running automation
4. **Use appropriate timeouts** in your configuration
5. **Verify all prerequisites** before starting installation

## Additional Resources

- [SNO Installation Guide](./SNO.md)
- [Ansible Bastion README](../ansible-bastion/README.md)
- [Red Hat CoreOS Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html)