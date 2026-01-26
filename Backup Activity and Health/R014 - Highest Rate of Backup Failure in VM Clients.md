# R014 -- Highest Backup Failure Rate (VM Clients)

## 1. Overview

Identifies VMs with the highest backup failure percentages.

## 2. Required Inputs

None.

## 3. Output Details

VM name, VM owner, Failure %, Server.

## 4. SQL Query

SELECT node_name,

clients.type,

rate,

fail_table.server

FROM (

SELECT a.node_name,

a.as_entity,

ROUND(CAST(failed AS FLOAT) / total_vm \* 100.0, 1) AS rate,

\'%s\' AS server

FROM (

SELECT name AS node_name,

as_entity,

COUNT(name) AS failed

FROM summary_extended s

INNER JOIN tsmgui_allcli_grid

ON sub_entity = name

AND as_entity = vm_owner

WHERE activity = \'BACKUP\'

AND status \> 0

AND successful = \'NO\'

AND (activity_type = \'Full\'

OR activity_type LIKE \'Incremental%%\')

AND sub_entity IS NOT NULL

GROUP BY name, as_entity

) a

INNER JOIN (

SELECT name AS node_name,

as_entity,

COUNT(name) AS total_vm

FROM summary_extended s

INNER JOIN tsmgui_allcli_grid

ON sub_entity = name

AND as_entity = vm_owner

WHERE activity = \'BACKUP\'

AND (activity_type = \'Full\'

OR activity_type LIKE \'Incremental%%\')

AND sub_entity IS NOT NULL

GROUP BY name, as_entity

) b

ON a.node_name = b.node_name

AND a.as_entity = b.as_entity

) fail_table

INNER JOIN tsmgui_allcli_grid clients

ON node_name = name

AND as_entity = vm_owner

AND fail_table.server = clients.server

ORDER BY rate DESC

FETCH FIRST 10 ROWS ONLY;

## 5. Purpose for Customers

Helps detect unstable VM backups and hypervisor issues.
