# IBM DB2 LUW 11.5.9 Installation Role

Ansible role to install and configure IBM DB2 on RHEL 8.

## Features
- Supports DB2 11.5.9
- Multiple instances support
- Designed for Red Hat Ansible Automation Platform (AAP)

## Requirements
- RHEL 8 (or compatible)
- Root/sudo access
- DB2 installer: `db2_v11.5.9_linuxx64_server.tar.gz`

## Role Variables

See `defaults/main.yml` and `group_vars/all.yml`

## Usage

```yaml
- hosts: db2_servers
  roles:
    - db2luw_install
