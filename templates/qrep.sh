#!/bin/bash
# Full working Q Rep Config Dumper - uses temp files to avoid connection loss
# Discovers from metadata tables in local databases

echo === Q Replication Configurations across ALL local databases ===
echo Current running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo Running ASN processes count: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo 

# Source DB2 profile
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
fi

# Get local databases
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo ERROR: No local databases found.
  exit 1
fi

echo Found local databases: $DBS
echo 

for DB in $DBS; do
  echo --------------------------------------------------
  echo DATABASE: $DB
  
  db2 connect to "$DB" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo   Failed to connect to $DB
    continue
  fi

  echo   Checking Q Rep control tables...

  TMP_SCHEMAS=/tmp/qrep_schemas_$$.txt
  db2 -x "SELECT DISTINCT TABSCHEMA 
          FROM SYSCAT.TABLES 
          WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
          AND TABSCHEMA NOT LIKE 'SYS%' 
          ORDER BY TABSCHEMA" > "$TMP_SCHEMAS" 2>&1

  SCHEMAS=$(grep -E '^[A-Z][A-Z0-9_]+$' "$TMP_SCHEMAS" | sort -u || echo "")

  if [ -z "$SCHEMAS" ]; then
    echo   No Q Replication control tables found in this database.
    rm -f "$TMP_SCHEMAS"
    db2 terminate > /dev/null 2>&1
    continue
  fi

  for SCHEMA in $SCHEMAS; do
    echo   Q Rep schema: $SCHEMA

    # SENDQUEUES
    TMP_COUNT=/tmp/qrep_count_$$.txt
    db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
            WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_SENDQUEUES'" > "$TMP_COUNT" 2>&1
    if grep -q "1" "$TMP_COUNT"; then
      echo     APPLY config IBMQREP_SENDQUEUES:
      db2 -x "SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA 
              FROM $SCHEMA.IBMQREP_SENDQUEUES;"
    fi
    rm -f "$TMP_COUNT"

    # RECVQUEUES
    db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
            WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_RECVQUEUES'" > "$TMP_COUNT" 2>&1
    if grep -q "1" "$TMP_COUNT"; then
      echo     CAPTURE config IBMQREP_RECVQUEUES:
      db2 -x "SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA 
              FROM $SCHEMA.IBMQREP_RECVQUEUES;"
    fi
    rm -f "$TMP_COUNT"
  done

  rm -f "$TMP_SCHEMAS"
  db2 terminate > /dev/null 2>&1
done

echo 
echo === Summary ===
echo All capture_server/capture_schema/apply_server/apply_schema pairs from metadata tables are listed above.
echo Use them to start asnqcap / asnqapp even if processes are down.
echo === Done ===

