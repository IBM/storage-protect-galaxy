## Appendix E. Modification of blueprint configurations

If you want to customize the configurations that are detailed in this document, plan carefully.

Consider the following before you deviate from the blueprint specifications:
* If you want to extend the usable storage for your system by adding storage enclosures, you must also add storage for the IBM Storage Protect database. Increase the database storage by approximately 1% of the additional total amount of managed data that will be protected (size before data deduplication).
* You can use AIX operating systems other than AIX 7.2, but the following caveats apply:
  * The version and operating system must be supported for use with the IBM Storage Protect server.
  * Additional configuration steps or modifications to steps for installation and configuration might be needed.
  * Refer to Storage Protect Server and Backup-archive client operating system compatibility matrix on the [support page 84861](https://www.ibm.com/support/pages/overview-ibm-storage-protect-supported-operating-systems).
  * For AIX specific information refer to [support page 7144921](https://www.ibm.com/support/pages/ibm-storage-protect-8122-server-requirements-and-support-aix%C2%AE).
* If you use other storage systems, performance measurements that are reported for the blueprint configurations are not guaranteed to match your customization.
* In general, no guarantees can be made for a customized environment. Test the environment to ensure that it meets your business requirements.