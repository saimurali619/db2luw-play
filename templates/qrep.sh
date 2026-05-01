#!/bin/bash
# Q Replication Config Dumper - DEBUG version with full raw output
# This will show exactly why tables are not being detected

echo === Q Replication Configurations across ALL local databases ===
echo Current running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo 

# Source DB2 profile
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
  echo DB2 profile sourced successfully
fi

# Get only local (Indirect) databases
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
  
  # Connect
  db2 connect to "$DB" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo   Failed to connect to $DB
    continue
  fi

  echo   Connected successfully to $DB

  # Raw catalog query with full visible output
  TMP_SCHEMAS=/tmp/qrep_schemas_$$.txt
  echo DEBUG: Running catalog query now...
  db2 -x "SELECT DISTINCT TABSCHEMA 
          FROM SYSCAT.TABLES 
          WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
          AND TABSCHEMA NOT LIKE 'SYS%' 
          ORDER BY TABSCHEMA" > "$TMP_SCHEMAS" 2>&1

  echo DEBUG: Raw output from catalog query:
  cat "$TMP_SCHEMAS"
  echo 

  # Parse schemas (very tolerant)
  SCHEMAS=$(cat "$TMP_SCHEMAS" | grep -E '^[A-Z0-9_]+' | tr -d '[:space:]' | sort -u || echo "")

  if [ -z "$SCHEMAS" ]; then
    echo   No Q Replication control tables found in this database.
    rm -f "$TMP_SCHEMAS"
    db2 terminate > /dev/null 2>&1
    continue
  fi

  echo   Found Q Rep schemas: $SCHEMAS

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
echo Look at the DEBUG lines above - they show the exact output of the catalog query.
echo If you see QRGWNOGB and QRNETGWD_SITF in the DEBUG section then the script works.
echo === Done ===
