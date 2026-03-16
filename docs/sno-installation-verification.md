# SNO Installation Verification and Troubleshooting

## Quick Status Check

If your SNO LPAR is up and SSH is working, the RHCOS installation succeeded. Now you need to verify the OpenShift installation status.

### 1. Check OpenShift Installation Status

From the **bastion host**, check the installation progress:

```bash
# Set the kubeconfig path (adjust the path to your workdir)
export KUBECONFIG=~/sno-work/auth/kubeconfig

# Check if the cluster is accessible
oc whoami

# Check cluster version and installation status
oc get clusterversion

# Check all cluster operators
oc get co

# Check node status
oc get nodes
```

### 2. Expected Output

**Successful installation:**
```bash
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.13.x    True        False         Xm      Cluster version is 4.13.x

$ oc get nodes
NAME       STATUS   ROLES                         AGE   VERSION
master-0   Ready    control-plane,master,worker   Xm    v1.26.x

$ oc get co
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.13.x    True        False         False      Xm
baremetal                                  4.13.x    True        False         False      Xm
...
```

**Installation in progress:**
```bash
$ oc get co
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED
authentication                             4.13.x    False       True          False
console                                    4.13.x    False       True          False
...
```

### 3. Check Installation Logs

#### On the Bastion Host

```bash
# Check Ansible playbook logs
# The logs are in the terminal output where you ran the playbook

# Check openshift-install logs (if using openshift-install directly)
cd ~/sno-work
cat .openshift_install.log

# Monitor installation progress
openshift-install wait-for bootstrap-complete --dir=~/sno-work
openshift-install wait-for install-complete --dir=~/sno-work
```

#### On the SNO Node

SSH into the SNO node to check CoreOS and installation logs:

```bash
# SSH to the SNO node
ssh core@<sno-ip>

# Check bootstrap service status
sudo systemctl status bootkube.service

# Check journal logs for installation
sudo journalctl -u bootkube.service -f

# Check for any failed services
sudo systemctl --failed

# Check kubelet status
sudo systemctl status kubelet

# Check container runtime
sudo crictl ps

# Check pod status
sudo crictl pods
```

### 4. Common Installation Issues

#### Issue 1: Cluster Operators Not Available

**Symptoms:**
```bash
$ oc get co
NAME           VERSION   AVAILABLE   PROGRESSING   DEGRADED
authentication           False       True          False
```

**Check:**
```bash
# Get detailed status
oc describe co authentication

# Check operator pods
oc get pods -n openshift-authentication

# Check events
oc get events -n openshift-authentication --sort-by='.lastTimestamp'
```

#### Issue 2: Node Not Ready

**Symptoms:**
```bash
$ oc get nodes
NAME       STATUS     ROLES                         AGE   VERSION
master-0   NotReady   control-plane,master,worker   Xm    v1.26.x
```

**Check:**
```bash
# Get node details
oc describe node master-0

# Check node conditions
oc get node master-0 -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}'

# SSH to node and check kubelet
ssh core@<sno-ip>
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
```

#### Issue 3: Pods Not Starting

**Check:**
```bash
# List all pods across all namespaces
oc get pods -A

# Check pods in specific namespace
oc get pods -n openshift-etcd

# Describe problematic pod
oc describe pod <pod-name> -n <namespace>

# Check pod logs
oc logs <pod-name> -n <namespace>
```

### 5. Installation Timeout

If the installation is taking too long (>60 minutes), check:

```bash
# On bastion - check if bootstrap is complete
cd ~/sno-work
openshift-install wait-for bootstrap-complete --log-level=debug

# On SNO node - check what's happening
ssh core@<sno-ip>

# Check if etcd is running
sudo crictl ps | grep etcd

# Check if API server is running
sudo crictl ps | grep kube-apiserver

# Check system resources
free -h
df -h
```

### 6. Ansible Playbook Error Logs

If the Ansible playbook failed, check:

```bash
# The error should be in the terminal output
# Look for lines starting with "fatal:" or "FAILED"

# Common playbook errors and locations:

# 1. Monitor role errors
cat /path/to/ansible-bastion/playbooks/roles/monitor/tasks/*.yaml

# 2. Check if bootstrap-complete was reached
# The playbook waits for this step

# 3. Re-run just the monitor step
cd ansible-bastion
ansible-playbook -i inventory -e @your-vars.yaml playbooks/step-4-monitor.yaml
```

### 7. Verify Installation Files

```bash
# On bastion - check if all required files exist
ls -lh ~/sno-work/auth/kubeconfig
ls -lh ~/sno-work/auth/kubeadmin-password
ls -lh ~/sno-work/.openshift_install.log

# Check ignition file was created
ls -lh /var/www/html/ignition/*.ign
```

### 8. Network Connectivity Check

```bash
# From bastion - verify SNO node is reachable
ping -c 4 <sno-ip>

# Check DNS resolution
nslookup api.<cluster-id>.<domain>
nslookup api-int.<cluster-id>.<domain>

# Check if API is accessible
curl -k https://api.<cluster-id>.<domain>:6443/healthz

# From SNO node - check internet access
ssh core@<sno-ip>
curl -I https://registry.redhat.io
```

### 9. Complete Installation Manually

If the playbook failed but the node is up, you can complete the installation manually:

```bash
# On bastion
cd ~/sno-work

# Wait for bootstrap to complete (should already be done for SNO)
openshift-install wait-for bootstrap-complete --log-level=info

# Wait for installation to complete
openshift-install wait-for install-complete --log-level=info

# This will output the console URL and kubeadmin password when complete
```

### 10. Access the Cluster

Once installation is complete:

```bash
# Set kubeconfig
export KUBECONFIG=~/sno-work/auth/kubeconfig

# Get cluster info
oc cluster-info

# Get console URL
oc whoami --show-console

# Get kubeadmin password
cat ~/sno-work/auth/kubeadmin-password

# Login to web console
# URL: https://console-openshift-console.apps.<cluster-id>.<domain>
# Username: kubeadmin
# Password: <from kubeadmin-password file>
```

### 11. Post-Installation Verification

```bash
# Verify all cluster operators are available
oc get co | grep -v "True.*False.*False"

# Check all nodes are ready
oc get nodes

# Check all pods are running
oc get pods -A | grep -v "Running\|Completed"

# Check cluster version
oc get clusterversion

# Check machine config
oc get mcp

# Run cluster diagnostics
oc adm must-gather
```

### 12. Common Playbook Error Messages

#### "Timed out waiting for bootstrap-complete"
```bash
# Check bootstrap service on SNO node
ssh core@<sno-ip>
sudo systemctl status bootkube.service
sudo journalctl -u bootkube.service | tail -100
```

#### "Timed out waiting for install-complete"
```bash
# Check cluster operators
oc get co
oc get co -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Progressing" and .status=="True")) | .metadata.name'

# Check what's blocking
oc get co <operator-name> -o yaml
```

#### "Failed to connect to API server"
```bash
# Check if API server is running on SNO node
ssh core@<sno-ip>
sudo crictl ps | grep kube-apiserver

# Check API server logs
sudo crictl logs <api-server-container-id>
```

### 13. Useful Commands Summary

```bash
# Quick health check
export KUBECONFIG=~/sno-work/auth/kubeconfig
oc get clusterversion && oc get nodes && oc get co

# Watch installation progress
watch -n 5 'oc get co'

# Check all resources
oc get all -A

# Get cluster events
oc get events -A --sort-by='.lastTimestamp' | tail -20

# Check etcd health
oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}{end}'
```

### 14. If Everything Fails

If the installation is stuck or failed:

1. **Collect logs:**
   ```bash
   # On bastion
   cd ~/sno-work
   tar czf sno-logs.tar.gz .openshift_install.log auth/

   # On SNO node
   ssh core@<sno-ip>
   sudo journalctl > /tmp/sno-journal.log
   sudo tar czf /tmp/sno-diagnostics.tar.gz /tmp/sno-journal.log /var/log/
   ```

2. **Start over:**
   ```bash
   # Power off SNO node via HMC
   # Clean up bastion
   rm -rf ~/sno-work
   rm -f /var/www/html/ignition/*.ign
   
   # Re-run the playbook from the beginning
   cd ansible-bastion
   ansible-playbook -i inventory -e @your-vars.yaml playbooks/main.yaml
   ```

## Next Steps

Once the cluster is fully installed and all operators are available:

1. **Set boot order** (if not done automatically):
   ```bash
   ssh core@<sno-ip>
   sudo /usr/sbin/bootlist -m normal -o /dev/sda
   ```

2. **Run customization** (optional):
   ```bash
   cd ansible-bastion
   ansible-playbook -i inventory -e @your-vars.yaml playbooks/step-5-customization.yaml
   ```

3. **Access the cluster:**
   - Web Console: https://console-openshift-console.apps.<cluster-id>.<domain>
   - API: https://api.<cluster-id>.<domain>:6443
   - Username: kubeadmin
   - Password: cat ~/sno-work/auth/kubeadmin-password