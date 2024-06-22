## Chapter 4. Setting up the system

You must setup hardware and preconfigure the system before you run the IBM Storage Protect Blueprint configuration script.

**About this task**

Some steps are unique based on the type of storage that you are configuring for your system. Steps are marked for Storwize® or IBM Elastic Storage Server systems as applicable.

**Procedure**

1. Configure your storage hardware according to the blueprint specifications and manufacturer instructions. </br>Follow the instructions in ["Step 1: Setup and configure hardware"](4.1-step-1-setup-and-configure-hardware.md).
1. Install the AIX operating system on the server. </br>Follow the instructions in ["Step 2: Install the operating system"](4.2-step-2-install-the-operating-system.md).
1. **IBM FlashSystem storage**: Configure multipath I/O for disk storage devices. </br>Follow the instructions in ["Step 3: IBM FlashSystem Storage: Configure multipath I/O"](4.3-step-3-ibm-flashsystem-storage-configure-multipath-io.md).
1. **IBM FlashSystem Storage**: Create file systems for IBM Storage Protect. </br>Follow the instructions in ["Step 4: IBM FlashSystem Storage: Configure file systems for IBM Storage Protect"](4.4-step-4-ibm-flashsystem-storage-configure-file-systems-for-ibm-storage-protect.md).
1. **IBM Elastic Storage System**: Configure the IBM Elastic Storage System. </br>Follow the instructions in ["Step 5: IBM Elastic Storage System: Configuring the system"](4.5-step-5-ibm-elastic-storage-system-configuring-the-system.md).
1. Test system performance with the IBM Storage Protect workload simulation tool, sp_disk_load_gen.pl. </br>Follow the instructions in ["Step 6: Test system performance"](4.6-step-6-test-system-performance.md).
1. Install the IBM Storage Protect backup-archive client. </br>Follow the instructions in ["Step 7: Install the IBM Storage Protect backup-archive client"](4.7-step-7-install-the-ibm-storage-protect-backup-archive-client.md).
1. Install the IBM Storage Protect license and server. </br>Follow the instructions in ["Step 8: Install the IBM Storage Protect server"](4.8-step-8-install-the-ibm-storage-protect-server.md).