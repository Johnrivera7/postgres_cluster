# PostgreSQL Cluster with Patroni and Consul
Automated script for deploying a PostgreSQL cluster using Consul as the distributed system coordinator and Patroni for high availability.

## Repository Overview
This script automates the deployment of a PostgreSQL cluster with Consul handling service discovery and configuration, and Patroni ensuring high availability. The cluster setup includes multiple PostgreSQL nodes where Consul manages the state of the cluster and Patroni provides seamless failover.

## Prerequisites
- Ubuntu servers for each PostgreSQL node.
- Open ports for Consul (8300, 8301, 8302, 8500, 8600), Patroni/PostgreSQL (5432, 8008), and SSH (22).
- Instances should have a valid hostname.

## Structure Diagram


## Usage
- Run the script on each PostgreSQL node.
- The script configures Consul and Patroni interactively.
- Follow on-screen instructions for setup on each node.

## Notes
- This script was tested on Ubuntu 22.04 instances.
- Ensure proper firewall or security group configurations are in place.
- The script installs the latest version of PostgreSQL available from the official repository.

## Getting Started
Clone this repository to your local machine:
```bash
git clone https://github.com/Johnrivera7/postgres_cluster.git
cd postgres-cluster
chmod u+x setup_postgres_cluster.sh
./setup_postgres_cluster.sh
```

## Author
John Rivera González - johnriveragonzalez@gmail.com

Version
0.1.1

## Acknowledgments

Thanks to the contributions and support from the community. Special thanks to:
- [@kunthar](https://github.com/kunthar) for his invaluable insights and contributions to this project.

# Disclaimer
This script is provided as-is. Use at your own risk.

Feel free to customize the information based on your preferences and any additional details you want to include. Choose a license that aligns with how you want others to use, modify, and distribute your script.
