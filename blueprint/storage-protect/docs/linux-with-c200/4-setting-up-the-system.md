### 4 Setting up the system

The deployment process is broken into eight steps.  Each step is described in its own chapter:

1. **Set up and configure hardware:** Rack and cable the server and FlashSystem C200, zone the SAN, and verify firmware levels.
2. **Install the operating system:** Install and update a supported Linux distribution, configure networking and tune kernel settings.
3. **Configure multipath I/O for FlashSystem C200:** Enable DM‑multipath, set SCSI timeouts and verify that each LUN is visible through multiple paths.
4. **Configure file systems for IBM Storage Protect:** Create XFS file systems on the database, log and storage pool volumes either via an automated script or manually.
6. **Test system performance:** Use the workload simulation tool to verify that the server and storage meet throughput expectations for the medium configuration.
7. **Install the IBM Storage Protect backup‑archive client:** Install the client software on nodes that will protect data.
8. **Install the IBM Storage Protect server:** Install the server packages, create the database and log volumes, and run the blueprint configuration script.
