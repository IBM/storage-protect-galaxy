## Chapter 1. Introduction  

This document provides detailed steps to build an IBM Storage Protect server on IBM Storage FlashSystem® C200. It covers deploying the server at the medium configuration size.  

The storage architecture includes:  
* IBM Storage FlashSystem C200 with Fibre Channel and Ethernet attachments  

By following the prerequisite steps precisely, you can set up hardware and prepare your system to run the IBM Storage Protect Blueprint configuration script, [`sp_config.pl`](../../sp-config/sp_config.pl), for a successful deployment. The settings and options that are defined by the script are designed to ensure optimal performance, based on the size of your system.  

The IBM Storage FlashSystem C200 is a high-density, capacity-optimized all-flash system that delivers enterprise-class data services in a compact 2U enclosure. When combined with IBM Storage Protect, it provides a scalable, efficient, and easy-to-manage platform for backup, archive, and long-term data protection workloads, with the reliability benefits of flash and modern data reduction technologies.

Built on IBM FlashCore® technology, the C200 uses an NVMe-based architecture and high-capacity FlashCore Modules (FCMs) to provide consistent performance with low latency and strong read throughput, ideal for accelerating backup and restore operations, improving compression efficiency, and optimizing storage utilization. Its dense flash design allows it to replace multiple traditional disk shelves, significantly reducing power, cooling, and rack footprint, which directly lowers overall TCO while increasing effective usable capacity.

The platform's FlashCore Modules incorporate advanced error correction, health monitoring, and predictive failure analytics that far exceed the resilience of legacy spinning-disk architectures. This enhanced reliability eliminates the historical need to separate DB2 backups across multiple M-disk groups to mitigate mechanical drive failures. On FlashSystem C200, consolidating into a single M-disk group carries no operational risk and simplifies storage layout while maintaining high levels of protection and availability.

With its flexible expansion capabilities, IBM Storage FlashSystem C200 has sufficient capacity to host 2 medium IBM Storage Protect server instances, depending on workload requirements and data retention needs. This scalability allows organizations to consolidate storage, simplify deployment, and ensure predictable performance as data volumes grow.  
While observed performance testing showed 10–15% improvement in random write performance , restore performance was evaluated with smaller chunks. We expect restore performance to improve as the chunk size increases when compared with storage using spinning disks.


### Overview  

The following roadmap lists the main tasks that you must complete to deploy a server:  

* Determine the size of the configuration that you want to implement.  
* Review the requirements and prerequisites for the server system.  
* Set up the hardware by using detailed blueprint specifications for system layout.  
* Configure the hardware and install the Linux operating system.  
* Prepare storage for IBM Storage Protect on IBM Storage FlashSystem C200.  
* Run the IBM Storage Protect workload simulation tool to verify that your configuration is functioning properly.  
* Install the IBM Storage Protect backup-archive client.  
* Install a licensed version of the IBM Storage Protect server.  
* Run the Blueprint configuration script to validate your hardware configuration, and then configure the server.  
* Complete post-configuration steps to begin managing and monitoring your server environment.  

### Deviation from the Blueprints  

Avoid deviations from the Blueprints. Deviations can result in poor performance or other operational problems. Some customization, including substituting comparable server and storage models from other manufacturers, can be implemented, but care must be taken to use components with equivalent or better performance. Avoid the following deviations:  

* Running multiple IBM Storage Protect server instances on the same operating system on the same computer.  
* Reducing the number of drives by substituting larger capacity drives.  
* Using the capacity-saving features of storage systems including thin provisioning, compression, or data deduplication. These features are provided by the IBM Storage Protect software and redundant use in the storage system can lead to performance problems.  

### Note on Flash Performance and Scalability  

The FlashSystem C200 delivers consistent, flash-optimized performance with latency typically in the 1–2 ms range, making it well suited for accelerating backup and restore operations within IBM Storage Protect environments. While performance and capacity within a single C200 system are fixed, the platform supports seamless horizontal scalability through the FlashSystem grid architecture, allowing multiple systems to be integrated to the grid and to expand overall capacity, throughput, and resilience with minimal disruption. By replacing legacy disk-based backup targets with dense, reliable flash storage, the C200 improves restore throughput and overall system responsiveness while simplifying operations and reducing dependency on mechanical media.
