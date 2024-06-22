## Appendix A. Performance results

### Large system performance measurements

Data was recorded for a large system in the IBM test lab environment.

_Table 22. Data intake processes._

| Metric  | Limit or range  | Notes  |
|---------|-----------------|--------|
| Maximum supported client sessions | 1000 |  |
| Daily amount of new data (before data deduplication) |  30 - 100 TB per day** | The daily amount of data is how much new data is backed up each day. |
| Backup ingestion rate | Server-side inline data deduplication | 16.4 TB per hour |  |
| Backup ingestion rate |  Client-side data deduplication | 22.2 TB per hour |  |
** The daily amount of new data is a range. For more information, see Chapter 2, ["Implementation requirements"](2-implementation-requirements.md).

_Table 23. Protected data_

| Metric   | Range    | Notes    |
|----------|----------|----------|
| Total managed data (size before data deduplication) | 1000 TB - 4000 TB | Total managed data is the volume of data that the server manages, including all versions. |

_Table 24. Data movement_

| Metric | Number of restore processes | Limit  |
|--------|-----------------------------|--------|
| Throughput of restore processes | 1 | 745.8 GB per hour |
| Throughput of restore processes | 2 | 1304.4 GB per hour |
| Throughput of restore processes | 4 | 2489 GB per hour |
| Throughput of restore processes | 6 | 4047 GB per hour |
| Throughput of restore processes | 8 | 5154.4 GB per hour |
| Throughput of restore processes | 10 | 6750 GB per hour |
| Throughput of restore processes | 20 | 8990.6 GB per hour |
| Throughput of restore processes | 40 | 9982.5 GB per hour |