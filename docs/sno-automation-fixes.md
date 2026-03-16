# SNO Automation Fixes - Missing RHCOS Kernel Files

## Problem Summary

During SNO installation, the PXE boot process failed with the error:
```
error: ../../grub-core/net/tftp.c:254:file /var/lib/tftpboot/rhcos/kernel not found.
```

This occurred because the RHCOS kernel and initramfs files were not being downloaded correctly or were missing from the TFTP directory.

## Root Causes Identified

1. **Silent download failures** - The original code didn't verify if downloads succeeded
2. **Missing error handling** - No retries or validation of downloaded files
3. **Permission issues** - Files might not have correct ownership for dnsmasq/TFTP access
4. **No verification step** - The playbook didn't check if files were present before proceeding

## Fixes Applied

### 1. Enhanced Download Process (`download_files.yaml`)

**Changes made:**
- Added explicit directory creation with correct ownership before downloads
- Added retry logic (3 attempts with 10-second delays) for each download
- Added timeout handling (300 seconds per download)
- Added file size validation after each download to ensure files aren't corrupted
- Added proper ownership (dnsmasq:dnsmasq) for TFTP files
- Added summary output showing downloaded file sizes
- Added failure detection for empty or null URLs

**Key improvements:**
```yaml
- name: Downloading CoreOS kernel
  get_url:
    url: "{{ rhcos_kernel_url.stdout }}"
    dest: /var/lib/tftpboot/rhcos/kernel
    mode: 0644
    owner: dnsmasq
    group: dnsmasq
    force: true
    timeout: 300
  register: kernel_download
  retries: 3
  delay: 10
  until: kernel_download is succeeded

- name: Verify kernel was downloaded
  stat:
    path: /var/lib/tftpboot/rhcos/kernel
  register: kernel_stat
  failed_when: not kernel_stat.stat.exists or kernel_stat.stat.size < 5000000
```

### 2. New Verification Task (`verify_rhcos_files.yaml`)

**Purpose:** Verify all RHCOS files are present and accessible before proceeding with installation.

**Checks performed:**
- ✓ Kernel file exists and is > 5 MB
- ✓ Initramfs file exists and is > 10 MB  
- ✓ Rootfs file exists and is > 100 MB
- ✓ Files have correct ownership (dnsmasq:dnsmasq)
- ✓ Files have correct permissions (0644)
- ✓ TFTP service can actually access the kernel file

**Benefits:**
- Fails fast if files are missing or corrupted
- Provides clear error messages with file sizes
- Tests actual TFTP accessibility, not just file existence
- Prevents wasting time on PXE boot attempts that will fail

### 3. Integration into Main Workflow

Added verification step after file downloads in `main.yaml`:
```yaml
- name: Download OCP files
  include_tasks: download_files.yaml
  when: day2_workers is not defined

- name: Verify RHCOS files are present and accessible
  include_tasks: verify_rhcos_files.yaml
  when: day2_workers is not defined
```

## Expected File Sizes

For reference, typical RHCOS file sizes for ppc64le:
- **kernel**: 10-15 MB
- **initramfs.img**: 100-150 MB
- **rootfs.img**: 400-500 MB

Files significantly smaller than these values indicate incomplete downloads.

## How to Use the Fixed Automation

### Fresh Installation

Simply run the playbook as normal:
```bash
cd ansible-bastion
ansible-playbook -i inventory playbooks/main.yaml
```

The enhanced automation will:
1. Download RHCOS files with retries
2. Verify each file after download
3. Check file sizes and permissions
4. Test TFTP accessibility
5. Fail with clear error messages if anything is wrong

### If You Already Hit the Error

If you already encountered the missing kernel error:

**Option 1: Re-run the services setup**
```bash
cd ansible-bastion
ansible-playbook -i inventory playbooks/step-1-setup-services.yaml
```

This will re-download and verify all files.

**Option 2: Manual fix then continue**
```bash
# Fix the files manually (see sno-quick-fix.md)
# Then continue from where you left off
cd ansible-bastion
ansible-playbook -i inventory playbooks/step-3-netboot-nodes.yaml
```

## Troubleshooting

### If downloads still fail

1. **Check internet connectivity:**
   ```bash
   curl -I https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/
   ```

2. **Check if proxy is needed:**
   ```bash
   # If behind a proxy, set environment variables
   export http_proxy=http://proxy.example.com:8080
   export https_proxy=http://proxy.example.com:8080
   ```

3. **Check disk space:**
   ```bash
   df -h /var/lib/tftpboot
   df -h /var/www/html
   ```

4. **Check SELinux isn't blocking:**
   ```bash
   ausearch -m avc -ts recent
   ```

### If verification fails

The verification task will show exactly which file is missing or too small:
```
FAILED - RETRYING: Verify all RHCOS files are present
fatal: [localhost]: FAILED! => {
    "assertion": "tftp_kernel.stat.exists",
    "msg": "RHCOS files are missing or too small. Please check:
    - Kernel: False (0.0 MB)
    - Initramfs: True (125.5 MB)
    - Rootfs: True (450.2 MB)"
}
```

This tells you exactly what needs to be fixed.

## Prevention

These fixes prevent the issue by:
1. **Detecting problems early** - Before PXE boot attempts
2. **Providing clear feedback** - Exact file sizes and status
3. **Automatic retries** - Handles transient network issues
4. **Validation** - Ensures files are complete and accessible

## Related Documentation

- [SNO Quick Fix Guide](./sno-quick-fix.md) - Manual recovery steps
- [SNO Troubleshooting Guide](./sno-troubleshooting-guide.md) - Comprehensive troubleshooting
- [SNO Installation Guide](../ansible-bastion/docs/SNO.md) - Original installation documentation

## Testing

To test the fixes without running a full installation:

```bash
# Test just the services setup
cd ansible-bastion
ansible-playbook -i inventory playbooks/step-1-setup-services.yaml --tags download

# Check the verification output
# You should see:
# - "All RHCOS files verified successfully"
# - File sizes for each component
# - "TFTP access verified"
```

## Future Improvements

Potential enhancements for consideration:
1. Add checksum verification for downloaded files
2. Cache downloads to avoid re-downloading on retries
3. Add bandwidth throttling for large downloads
4. Support for alternative mirror sites
5. Pre-flight check before starting installation

## Summary

The automation now includes:
- ✅ Robust download with retries and timeouts
- ✅ File size validation
- ✅ Ownership and permission verification
- ✅ TFTP accessibility testing
- ✅ Clear error messages with actionable information
- ✅ Fail-fast behavior to save time

These changes ensure that RHCOS files are properly downloaded and accessible before attempting PXE boot, preventing the "kernel not found" error.