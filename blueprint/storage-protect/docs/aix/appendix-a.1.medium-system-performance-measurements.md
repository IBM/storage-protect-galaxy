## Appendix A. Performance results

### Medium system performance measurements

Data was recorded for a medium system in the IBM test lab environment. The measurements were taken on the previous FlashSystem 5030 configuration and will be updated with results from the FlashSystem 5045 in a future update.

_Table 19. Data intake processes_

| Metric   | Limit or range |  Notes   |
|----------|----------------|----------|
| Maximum supported client sessions | 500 |  |
| Daily amount of new data (before data deduplication) |  10 - 30 TB per day** | The daily amount of data is how much new data is backed up each day. |
| Backup ingestion rate | Server-side inline data deduplication | 3.2 TB per hour |  |
| Backup ingestion rate | Client-side data deduplication | 4.3 TB per hour |   |
** The daily amount of new data is a range. For more information, see Chapter 2, ["Implementation requirements"](2-implementation-requirements.md).

_Table 20. Protected data_

| Metric  | Range   | Notes  |
|---------|---------|--------|
| Total managed data (size before data deduplication) | 360 TB - 1440 TB | Total managed data is the volume of data that the server manages, including all versions. |

_Table 21. Data restore processes_

| Metric |  Number of restore processes | Limit  |
|--------|------------------------------|--------|
| Throughput of restore processes | 1 | 398.4 GB per hour |
| Throughput of restore processes | 2 | 664.6 GB per hour |
| Throughput of restore processes | 4 | 1771.0 GB per hour |
| Throughput of restore processes | 6 | 2729.0 GB per hour |
| Throughput of restore processes | 8 | 3645.4  GB per hour |
| Throughput of restore processes | 10 | 4233.0 GB per hour |
