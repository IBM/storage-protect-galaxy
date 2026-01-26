# R019 -- Client Replication Health Report

## 1. Overview

Provides a health overview of client replication status across servers.

## 2. Required Inputs

None.

## 3. Output Details

Server name, Normal count, Warning count, Critical count, Total file
spaces.

## 4. SQL Query

SELECT \'%1\$s\' AS SERVER,

NORMAL,

WARNING,

CRITICAL,

COUNT

FROM

( SELECT COUNT(status) AS NORMAL

FROM TSMGUI_REPLCLI_GRID

WHERE SERVER = \'%1\$s\'

AND (STATUS = 0

AND (SYNCTIME \> current timestamp - 1 day))

),

( SELECT COUNT(status) AS WARNING

FROM TSMGUI_REPLCLI_GRID

WHERE SERVER = \'%1\$s\'

AND ( (STATUS = 1 AND (SYNCTIME \> current timestamp - 2 days))

OR (STATUS = 0 AND (SYNCTIME \< current timestamp - 1 day)

AND (SYNCTIME \> current timestamp - 2 days)))

),

( SELECT COUNT(status) AS CRITICAL

FROM TSMGUI_REPLCLI_GRID

WHERE SERVER = \'%1\$s\'

AND ( STATUS = 2

OR (STATUS = 1 AND (SYNCTIME \< current timestamp - 2 days)) )

),

( SELECT COUNT(status) AS COUNT

FROM TSMGUI_REPLCLI_GRID

WHERE SERVER = \'%1\$s\' );

## 5. Purpose for Customers

Helps customers monitor replication delays and ensure DR readiness.
