# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a server optimization toolkit written in Bash that helps optimize Debian/Ubuntu servers for network performance and security. The project consists of multiple modular scripts that can be run individually or as part of an optimization suite.

## Commands and Usage

### Installation and Execution
- **One-line installation**: `bash <(curl -sL ss.hide.ss)`
- **Manual installation**: `chmod +x scripts/*.sh && sudo ./install.sh`
- **Run individual scripts**: `sudo ./scripts/run_optimization.sh <option>`

### Available Script Options
- `update`: System and package updates
- `bbr`: Enable Google BBR congestion control
- `tcp`: TCP network optimization
- `dns`: DNS server configuration  
- `ssh`: SSH security configuration (port and password changes)
- `ipv6`: Disable IPv6 protocol
- `basic`: Quick network optimization (runs update, bbr, tcp)
- `all`: Run all optimization scripts

### Testing and Validation
No automated test suite exists. Manual testing involves:
- Running scripts on test systems first
- Verifying configuration changes in `/etc/sysctl.conf`, `/etc/ssh/sshd_config`, etc.
- Checking network performance with tools like `iperf3`, `ping`, `curl`
- Validating BBR with `lsmod | grep bbr` and `sysctl net.ipv4.tcp_congestion_control`

## Code Architecture

### Core Components

**Entry Points**:
- `install.sh`: Main installer script that downloads and sets up the toolkit
- `scripts/run_optimization.sh`: Master control script that orchestrates individual optimizations

**Shared Libraries**:
- `scripts/common_functions.sh`: Centralized utility functions for logging, system detection, validation, and error handling

**Individual Optimization Scripts**:
- `scripts/system_update.sh`: System package updates
- `scripts/enable_bbr.sh`: BBR congestion control configuration
- `scripts/tcp_tuning.sh`: TCP parameter optimization
- `scripts/configure_dns.sh`: DNS server configuration
- `scripts/configure_ssh.sh`: SSH security hardening
- `scripts/disable_ipv6.sh`: IPv6 protocol disabling

### Key Architectural Patterns

**Modular Design**: Each optimization is a separate script that can run independently
**Centralized Configuration**: `scripts/server_config.conf` for shared settings
**Unified Logging**: All scripts use common logging functions with timestamps to `/var/log/server_optimization.log`
**System Detection**: Automatic detection of OS distribution, version, and package manager
**Safety Mechanisms**: Automatic backup of configuration files before modifications
**Interactive Menu System**: User-friendly menu-driven interface for script selection

### Script Execution Flow
1. `install.sh` downloads all components to `/opt/server-optimization/`
2. User selects optimization via interactive menu
3. `run_optimization.sh` validates and executes the selected script
4. Individual scripts use `common_functions.sh` for system detection, logging, and safety checks
5. Configuration files are backed up before modification
6. Changes are applied with validation and rollback capabilities

### Configuration Management
- Scripts automatically detect system type (Debian/Ubuntu/CentOS)
- Package managers are auto-detected (apt/yum/dnf)
- Kernel version compatibility is checked for BBR
- All modifications create timestamped backups in `/etc/backup_*` directories

### Error Handling and Safety
- Root permission validation
- System compatibility checks
- Configuration file syntax validation
- Automatic rollback on failure
- Comprehensive logging with error codes and stack traces