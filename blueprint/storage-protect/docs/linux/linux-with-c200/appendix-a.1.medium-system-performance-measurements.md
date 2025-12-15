## Appendix A. Performance results

### Appendix A.1 Medium system performance measurements

Data was recorded for a medium system in the IBM test lab environment. The measurements were taken on a previous hardware configuration and will be updated with results from the FlashSystem C200 in a future update.

_Table 27. Data intake processes_

| Metric   | Limit or range |  Notes   |
|----------|----------------|----------|
| Maximum supported client sessions | 500 |  |
| Daily amount of new data (before data deduplication) | 10 – 30 TB per day\*\* | The daily amount of data is how much new data is backed up each day. |
| Backup ingestion rate | Server-side inline data deduplication | 6.5 TB per hour |  |
| Backup ingestion rate | Client-side data deduplication | 10 TB per hour |   |

\*\* The daily amount of new data is a range. For more information, see Chapter 2, [“Implementation requirements”](#chapter-2-implementation-requirements).

_Table 28. Protected data_

| Metric  | Range   | Notes  |
|---------|---------|--------|
| Total managed data (size before data deduplication) |  360 TB - 1440 TB | Total managed data is the volume of data that the server manages, including all versions. |

_Table 29. Data restore processes_

| Metric |  Number of restore processes | Limit  |
|--------|------------------------------|--------|
| Throughput of restore processes | 1 | 547.56 GB per hour |
| Throughput of restore processes | 2 | 1179.05 GB per hour |
| Throughput of restore processes | 4 | 1640.50 GB per hour |
| Throughput of restore processes | 6 | 2601.46 GB per hour |
| Throughput of restore processes | 8 | 3293.32 GB per hour |
| Throughput of restore processes | 10 | 4002.02 GB per hour |
| Throughput of restore processes | 12 | 4413.08 GB per hour |
