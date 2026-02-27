# Introduction
The `ocp4-ai-power` [project](https://github.com/danijel-soldo/ocp4-ai-power) provides Terraform based automation code to help the deployment of OpenShift Container Platform (OCP) 4.x on PowerVM systems with Agent-based installer, assisted installer and SNO. It can be used for IBM PowerVS, PowerVC and HMC. The difference between this playbook and other UPI playbooks is it uses net boot or bootp method for OCP installation.

> **Note:** For bugs/enhancement requests etc. please open a GitHub [issue](https://github.com/danijel-soldo/ocp4-ai-power/issues)

## 📖 Documentation Site

**[https://danijel-soldo.github.io/ocp4-ai-power/](https://danijel-soldo.github.io/ocp4-ai-power/)**

The documentation is hosted on GitHub Pages and includes quickstart guides for SNO installation.

# Directory structure
There are 5 subdirectories for `ocp4-ai-power`:
- ansible-bastion -- ansible play book to setup bastion, create OCP configuration and perform OCP installation and customization
- data -- default place to store private, public key and pull secret
- tf-common -- Common modules for terraform
- tf-powervc -- Terraform modules for PowerVC, it is the working directory for PowerVC
- tf-powervs -- Terraform modules for PowerVS, it is the working directory for PowerVS (WIP)  

# For PowerVC

Follow the [guide](tf-powervc/README.md) for OCP installation on PowerVM LPARs managed via PowerVC

# For PowerVS (WIP)

Follow the [guide](tf-powervs/README.md) for OCP installation on PowerVM LPARs managed via PowerVS (this part is not work yet)

# Quick Start – Single Node OpenShift (SNO)

Two quickstart guides are available for SNO installation on PowerVM:

| Guide | Live URL | Description |
|-------|----------|-------------|
| **Automated Quick Start** | [View ↗](https://danijel-soldo.github.io/ocp4-ai-power/quick-start-automated.html) | Uses the Ansible automation in this repository – recommended for most users |
| **Manual Step-by-Step Quick Start** | [View ↗](https://danijel-soldo.github.io/ocp4-ai-power/quick-start.html) | Manually configures each service – useful for learning or custom setups |

