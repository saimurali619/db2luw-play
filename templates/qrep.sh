#!/bin/bash
# Simple Q Rep discovery script for local databases only
# Prints raw catalog query so we can see exactly what is happening

echo === Simple Q Rep Control Tables Discovery ===
echo Current DB connection:
db2 "VALUES CURRENT SCHEMA, CURRENT SERVER"
echo 

echo Running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo 

echo Checking local database for Q Rep control tables...
echo Raw catalog query output:
db2 -x "SELECT DISTINCT TABSCHEMA, TABNAME 
        FROM SYSCAT.TABLES 
        WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
        AND TABSCHEMA NOT LIKE 'SYS%' 
        ORDER BY TABSCHEMA, TABNAME"

echo 
echo If the above shows QRGWNOGB or QRNETGWD_SITF then tables exist.
echo If empty or error then tables are not in the current local database or you need to connect to a different DB first.
echo 

echo To see all schemas with any IBMQREP tables:
db2 -x "SELECT DISTINCT TABSCHEMA FROM SYSCAT.TABLES WHERE TABNAME LIKE 'IBMQREP%' ORDER BY TABSCHEMA"

echo 
echo === End ===

# If you see the schemas above, then run these to get the server/schema pairs
echo Example queries once schemas are known:
echo db2 "SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA FROM QRGWNOGB.IBMQREP_SENDQUEUES"
echo db2 "SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA FROM QRNETGWD_SITF.IBMQREP_RECVQUEUES"

Save this as qrep_simple.sh , chmod +x qrep_simple.sh , ./qrep_simple.sh and paste the full output. This will tell us exactly why the tables are not being found.
