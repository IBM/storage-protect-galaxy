# R030 -- Node Storage Consumption Summary

## 1. Overview

Provides a summary of node-level storage consumption and activity.

## 2. Required Inputs

None.

## 3. Output Details

Node name, Storage consumed, Activity metrics.

## 4. SQL Query

select devclass, pooltype, est_capacity_mb, pct_utilized,

encrypted, pct_encrypted, reusedelay

from stgpools;

## 5. Purpose for Customers

Helps customers identify top storage-consuming nodes.
