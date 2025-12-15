## Chapter 2. Implementation requirements  

Select the appropriate size for your IBM Storage Protect environment and then review requirements for hardware and software.  

Use Table 1 to select the server size, based on the amount of data that you manage. Both the total managed data and daily amount of new data are measured before data deduplication.  

Data amounts in the table are based on the use of directory-container storage pools with inline data deduplication, a feature that was introduced in IBM Storage Protect Version 7.1.3. The blueprints are also designed to use inline storage pool compression, a feature that was introduced in IBM Storage Protect V7.1.5.  

> **Tip**: Before you configure a solution, learn about container storage pools. See [Directory-container storage pools FAQs](https://www.ibm.com/support/pages/node/3227697).  

_Table 1. Selecting the size of the IBM Storage Protect server on IBM Storage FlashSystem C200 (Linux)_  

| If your total managed data is in this range | And the amount of new data that you back up with one replication copy is in this range | The amount of new data that you back up with two replication copies is in this range | Build a server of this size |
|-------------------|---------------------|----------------------|----------------|
| 360 TB – 1440 TB   | 10 – 30 TB per day   | 6 – 18 TB per day     | Medium         |

The _daily ingestion rate_ is the amount of data that you back up each day. The daily ingestion needs to be completed in a backup window that leaves enough time remaining in the day to complete maintenance tasks. For optimum performance, split the tasks of backing up and archiving client data, and performing server data maintenance into separate time windows. The daily ingestion amounts in Table 1 are based on test results with 128 MB sized objects, which are used by IBM Storage Protect for Virtual Environments assuming a backup window of eight hours. The daily ingestion amount is stated as a range because backup throughput, and the time that is required to complete maintenance tasks, vary based on workload.  

If a server is used to both accept backup data and receive replicated data from other servers, more planning is needed. Any data that is received through replication must be considered as part of the daily backup amount. For example, a server that receives 25 TB of new backup data and 15 TB of new replication data daily has a total ingestion rate of 40 TB per day. Optionally, backup data and data received through replication can be placed in separate directory-container storage pools.  

**Remember**: If you are planning to create two replication copies of the backup data, you will need to consider it while selecting the size of the server. The daily amount of backup data has to be decreased to reduce the amount of time required to back up data. This is done to compensate for the additional time needed to create the second replication copy.  

Not every workload can achieve the maximum amount in the range for daily backups. The range is a continuum, and placement within the range depends on several factors:  

* **Major factors**  
  * **Average object size.** Workloads with smaller average object sizes, such as those that are common with file server backups, typically have smaller backup throughputs. If the average object size is less than 128 KB, daily backup amounts are likely to fall in the lower 25 % of the range. If the average object size is larger, for example, 512 KB or more, backup throughputs are greater.  
  * **Daily data reduction.** When data is reduced by using data deduplication and compression, less data must be written to storage pools. As a result, the server can handle larger amounts of daily data ingestion.  
* **Additional factors**  
  * **Data deduplication location.** By using client-side data deduplication, you reduce the processing workload on the server. As a result, you can increase the total amount of data that is deduplicated daily.  
  * **Network performance.** By using efficient networks, you can back up and replicate more data daily.  

Additionally, including optional features in the solution, such as making a copy of the container storage pool to tape storage, will require adjustments to the maximum amount of new backup data that can be processed per day. The amount of time required to complete the optional data copy or movement activities needs to be considered in evaluating the daily ingest limit for the server.  

To better understand the factors that affect the maximum amount of daily data ingestion, review the following figure:  

![Figure 1. Range for daily data ingestion in a medium IBM Storage FlashSystem C200 system](./diagrams/Range%20for%20daily%20data%20ingestion%20in%20a%20large%20system.png)  

_Total managed data_ is the amount of data that is protected. This amount includes all versions. A range is provided because data processing responds differently to data deduplication and compression, depending on the type of data that is backed up. The smaller number in the range represents the physical capacity of the IBM Storage Protect storage pool. Although the use of inline compression does not result in additional growth of the IBM Storage Protect database, compression might result in the ability to store more data in the same amount of storage pool space. In this way, the amount of total managed data can increase causing more database space to be used.  

To estimate the total managed data for your environment, you must have the following information:  

* The amount of client data (the front-end data amount) that will be protected  
* The number of days that backup data must be retained  
* An estimate of the daily change percentage  
* The backup model that is used for a client type, for example, incremental-forever, full daily, or full periodic  

If you are unsure of your workload characteristics, use the middle of the range for planning purposes.  

You can calculate the total managed data for different types of clients in groups and then add the group results.  

* **Client types with incremental-forever backup operations**  
  * Use the following formula to estimate the total managed data:  
    ```
    Frontend + (Frontend * changerate * (retention - 1))
    ```
  * For example, if you back up 100 TB of front-end data, use a 30-day retention period, and have a 5 % change rate, calculate your total managed data as shown:  
    ```
    100 TB + (100TB * 0.05 * (30-1)) = 245 TB total managed data
    ```
* **Client types with full daily backup operations**  
  * Use the following formula to estimate the total managed data:  
    ```
    Frontend * retention * (1 + changerate)
    ```
  * For example, if you back up 10 TB of front-end data, use a 30-day retention period, and have a 3 % change rate, calculate your total managed data as shown:  
    ```
    10 TB * 30 * (1 + .03) = 309 TB total managed data
    ```

To efficiently maintain periodic copies of your data to meet long-term retention requirements, you can use the retention set feature. Retention sets are created from existing backups without requiring data to be redundantly sent to the IBM Storage Protect server. Retention sets can either be created in-place by maintaining the existing backups for multiple retention requirements, or with copies made to tape media. In-place retention sets will increase the amount of total managed data requiring additional storage pool and database space. Retention set copies will require space in a retention pool, but have a very minimal impact to database space.  
