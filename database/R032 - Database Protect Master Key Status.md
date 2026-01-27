# R032 -- Database Protect Master Key Status

## 1. Overview

Shows the status of the Protect Master Key used for securing encrypted
database objects.

## 2. Required Inputs

None.

## 3. Output Details

Protect Master Key status (ON/OFF).

## 4. SQL Query

```sql SELECT
    PROTECT_MASTER_KEY
FROM
    db;

```

## 5. Purpose for Customers

Helps customers verify that database encryption key protection is
enabled.
