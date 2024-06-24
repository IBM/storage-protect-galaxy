## Appendix A. Performance results

You can compare IBM system performance results against your IBM Storage Protect storage configuration as a reference for expected performance.

Observed results are based on measurements that were taken in a test lab environment. Test systems were configured according to the Blueprints in this document. Backup-archive clients communicated across a 25 Gb Ethernet connection to the IBM Storage Protect server, and deduplicated data was stored in directory-container storage pools. Because many variables can influence throughput in a system configuration, do not expect to see exact matches with the results. Storage pool compression was included in the test configuration on which these performance results are based. The following typical factors can cause variations in actual performance:
* Average object size of your workload
* Number of client sessions that are used in your environment
* Amount of duplicate data

This information is provided to serve only as a reference.

For approximate performance results on a small Blueprint system, see the _Blueprint and Server Automated Configuration for AIX, Version 4 Release 1_ at [IBM Storage Protect Blueprints](https://www.ibm.com/support/pages/ibm-storage-protect-blueprints). Test results for the AIX medium system showed data that was similar to the Linux medium system. Therefore, comparable results would be expected for AIX and Linux small systems.
