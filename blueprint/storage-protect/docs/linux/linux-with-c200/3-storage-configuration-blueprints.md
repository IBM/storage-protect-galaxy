## Chapter 3. Storage configuration blueprints

After you acquire hardware for the scale of server that you want to build, you must prepare your storage to be used with IBM Storage Protect. Configuration blueprints provide detailed specifications for storage layout. Use them as a map when you setup and configure your hardware.

Specifications in ["Hardware requirements"](2.1.1-hw-requirements.md) and the default values in the ["Planning worksheets"](2.2-planning-worksheets.md) were used to construct the blueprints for medium systems. If you deviate from those specifications, you must account for any changes when you configure your storage.

**Note**: The IBM FlashSystem C200 configurations use hardware compression built into the FlashCore Modules; therefore, hardware deduplication must not be enabled. The IBM Storage Protect software will perform the data reduction, and redundantly performing these tasks in the storage system will result in performance problems.

**Tip**: Earlier versions of the blueprints are available at the bottom of the blueprint web page.

**FlashSystem C200 layout requirements**

A _managed disk_, or _MDisk_, is a logical unit of physical storage. In the blueprint configurations, MDisks are internal-storage RAID arrays and consist of multiple physical disks that are presented as logical volumes to the system. When you configure the disk system, you will create MDisk groups, or data storage pools, and then create MDisk arrays in the groups.

The medium blueprint configurations include more than one MDisk distributed array and combine the MDisks together into a single MDisk group or storage pool. In previous blueprint versions, a one-to-one mapping exists between MDisks and MDisk groups. Sharing a common storage pool for multiple arrays is not required for disk systems which do not support this or for configurations that were implemented to the earlier blueprint design.

Volumes, or LUNs, belong to one MDisk group and one I/O group. The MDisk group defines which MDisks provide the storage that makes up the volume. The I/O group defines which nodes provide I/O access to the volume. When you create volumes, make them fully allocated with a vdev type of striped. For IBM FlashSystem C200 hardware, select the generic volume type when you create volumes.

Table 10 and Table 11 describe the layout requirements for MDisk and volume configuration in the storage blueprints.

_Table 10. Components of MDisk configuration_

| Component    | Details         |
|--------------|-----------------|
| Server storage requirement | How the storage is used by the IBM Storage Protect server. |
| Disk type    | Size and speed for the disk type that is used for the storage requirement. |
| Disk quantity | Number of each disk type that is needed for the storage requirement. |
| Hot spare coverage | Number of disks that are reserved as spares to take over in case of disk  failure. For distributed arrays this represents the number of rebuild areas. |
| RAID type     | Type of RAID array that is used for logical storage. |
| RAID array quantity and DDM per array |  Number of RAID arrays to be created, and how many disk drive modules (DDMs) are to be used in each of the arrays. |
| Usable size   | Size that is available for data storage after accounting for space that is lost to RAID array redundancy. |
| Suggested MDisk names | Preferred name to use for MDisks and MDisk groups. |
| Usage         | IBM Storage Protect server component that uses part of the physical disk. |

_Table 11. Components of volume (LUN) configuration_

| Component    | Details         |
|--------------|-----------------|
| Server storage requirement | Requirement for which the physical disk is used. |
| Volume name  | Unique name that is given to a specific volume. |
| Quantity     | Number of volumes to create for a specific requirement. Use the same naming standard for each volume that is created for the same requirement. |
| Uses MDisk group | The name of the MDisk group from which the space is obtained to create the volume. |
| Size         | The size of each volume. |
| Intended server mount point | The directory on the IBM Storage Protect server system where the volume is mounted. </br> If you plan to use directories other than the defaults that are configured by the Blueprint configuration script, you must also use those directory values when you configure your hardware. In this case, do not use the values that are specified in the blueprints. |
| Usage        | IBM Storage Protect server component that uses part of the physical disk. |

**FlashSystem C200 volume protection feature**

The IBM FlashSystem C200 volume protection feature is a safeguard that prevents unintended deletion of volumes containing important data when there has been recent I/O against the volumes. Activate this feature to protect the volumes used with IBM Storage Protect. The volume protection feature is not on by default, and must be enabled for each storage pool from the IBM FlashSystem C200 user interface.
