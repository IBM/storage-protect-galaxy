## Chapter 1. Introduction

This document provides detailed steps to build a small, medium, or large IBM Storage Protect server with disk-only storage that uses data deduplication on an IBM® AIX® system.

Two options for the storage architecture are included:

* IBM FlashSystem® with Fibre Channel attachments
* IBM Elastic Storage System with an Ethernet or Infiniband attachment.

By following prerequisite steps precisely, you can setup hardware and prepare your system to run the IBM Storage Protect Blueprint configuration script, [`sp_config.pl`](../../tools/sp_config.pl), for a successful deployment. The settings and options that are defined by the script are designed to ensure optimal performance, based on the size of your system.

### Overview
The following roadmap lists the main tasks that you must complete to deploy a server:

1. Determine the size of the configuration that you want to implement.
1. Review the requirements and prerequisites for the server system.
1. Setup the hardware by using detailed blueprint specifications for system layout.
1. Configure the hardware and install the AIX operating system.
1. Prepare storage for IBM Storage Protect.
1. Run the IBM Storage Protect workload simulation tool to verify that your configuration is functioning properly.
1. Install the IBM Storage Protect backup-archive client.
1. Install a licensed version of the IBM Storage Protect server.
1. Run the Blueprint configuration script to validate your hardware configuration, and then configure the server.
1. Complete post-configuration steps to begin managing and monitoring your server environment.

### Deviating from the Blueprints

Avoid deviations from the Blueprints. Deviations can result in poor performance or other operational problems. Some customization, including substituting comparable server and storage models from other manufacturers, can be implemented, but care must be taken to use components with equivalent or better performance. Avoid the following deviations:

* Running multiple IBM Storage Protect server instances on the same operating system on the same computer.
* Reducing the number of drives by substituting larger capacity drives.
* Using the capacity-saving features of storage systems including thin provisioning, compression, or data deduplication. These features are provided by the IBM Storage Protect software and redundant use in the storage system can lead to performance problems.

The Blueprints on IBM Power Systems are implemented without the use of logical partitions (LPARs) or a Virtual I/O Server (VIOS). If you plan to implement a variation of the Blueprint that uses a larger Power Systems server model with LPARs, avoid using a VIOS to virtualize network and storage connections for the IBM Storage Protect server. Instead, use dedicated network and storage adapters that are assigned directly to the LPAR that is running the IBM Storage Protect server.
