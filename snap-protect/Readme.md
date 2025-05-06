# Consistent SGC for IBM Storage Protect

-----------------------------------


## Introduction Test

This project provides scripts that facilitate the creation and restoration of consistent Safeguarded Copies (SGC)for IBM Storage Protect server instances. Storage Protect server instances store their data and metadata in storage systems. Managing SGC depends on the storage system. 

This project supports the following storage system:

- IBM Storage Scale version 5.1.9 and above - see [Storage Scale scripts](storage-scale/Readme.md)



### License

This project is under [Apache License 2.0](../LICENSE).


## Workflows

There are two basic workflows that are accomplished by the script in this project for the supported storage systems.

Safeguarded copies are managed for data areas of a Storage Protect instance. Data area is the storage space where the Storage Protect instance stores data (backup objects) and metadata (database, logs, instance configuration).

- With Storage Scale the data area is a **file system and fileset**. 


### Safeguarded copy creation

The workflow to create consistent and safeguarded copies (SGC) for all relevant data areas of the Storage Protect instance consists of 3 phases and requires the Storage Protect instance to be running. The SGC creation phases are:

- **Phase 1:** Connect to the instance Db2 and write suspend the Db2. Must be executed by instance user. 
- **Phase 2:** Create the SGC for all relevant data areas of the Storage Protect instance
- **Phase 3:** Resume the Db2 of the instances. Must be executed by instance user. 

Each phase must be performed as an atomic operation. Phase 1 and phase 3 must be executed by the instance user. Phase 2 can be executed by other users that have the privilege to create SGC. All phases should be run quickly together to minimize the Storage Protect instance suspended state.

The SGC creation workflow is facilitated by the `*snap-create.sh` scripts for the selected storage systems. 

**The SGC creation script must be executed as instance user on the server where the instance is running. Otherwise, no SGC is created for the instance.**



### Safeguarded copy restoration

To workflow to restore the SGC  for all relevant relevant data areas of a Storage Protect instance consists of 3 phases. This workflow requires the Storage Protect server instance to be stopped. The SGC restoration phases are:

- **Phase 1:** Restore the SGC for all relevant data areas of the instance.
- **Phase 2:** Restart the instance Db2 and resume the instance Db2. Must be executed by instance user. 
- **Phase 3:** Start the Storage Protect instance. 

Each phase must be performed as an atomic operation. Phase 2 must be executed by the instance user. Phase 1 and 3 can be executed by other users that have the privileges to restore SGC and start the Storage Protect instance.

The SGC restoration workflow is facilitated by the `*snap-restore.sh` scripts for the selected storage systems. 


**The SGC restoration script must be executed as instance user on the server where the instance was running. The Storage Protect instance must be stopped prior to executing the restoration script. When running restoration script on one server while the instance is running on another server, the script does not detect this and performs the restore operation while the instance may be running on another server. This will cause the Storage Protect instance to become unavailable.**

