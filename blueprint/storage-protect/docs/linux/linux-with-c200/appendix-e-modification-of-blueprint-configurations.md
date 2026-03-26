## Appendix E. Modification of blueprint configurations

If you want to customize the configurations that are detailed in this document, plan carefully.

Consider the following before you deviate from the blueprint specifications:
* If you want to extend the usable storage for your system by adding storage enclosures, you must also add storage for the IBM Storage Protect database. Increase the database storage by approximately 1% of the additional total amount of managed data that will be protected (size before data deduplication).
* You can use Linux operating systems other than Red Hat Enterprise Linux, but the following caveats apply:
  * The version and operating system must be supported for use with the IBM Storage Protect server.
  * Additional configuration steps or modifications to steps for installation and configuration might be needed.
* If you use other storage systems, performance measurements that are reported for the blueprint configurations are not guaranteed to match your customization.
* In general, no guarantees can be made for a customized environment. Test the environment to ensure that it meets your business requirements.
