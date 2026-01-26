# R020 -- Charge‑Back Capacity Report

## 1. Overview

Provides server‑level capacity metrics for internal cost allocation and
charge‑back.

## 2. Required Inputs

None.

## 3. Output Details

Server name, Version, Status, Client counts, FE capacity, BE capacity,
Retention capacity.

## 4. SQL Query

## SELECT NAME,

##  VRMF,

##  STATUS,

##  NUMCLIENTS,

##  FE_NUMCLIENTS,

##  NUMCLIENTS - FE_NUMCLIENTS AS FE_NUMCLIENTS_NOTREPORTED,

##  FE_CAPACITY_TB,

##  FE_TIMESTAMP,

##  SUR_OCC AS BE_CAPACITY_TB,

##  SUR_RET_OCC AS RET_CAPACITY_TB,

##  SUROCC_TIMESTAMP AS BE_TIMESTAMP

## FROM TSMGUI_ALLSRV_GRID

## WHERE CONFIGURED \> 0

## ORDER BY STATUS;

## 5. Purpose for Customers

Helps customers support cost allocation and capacity charge‑back models.
