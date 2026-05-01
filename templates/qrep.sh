#!/bin/bash
# Q Replication Config Dumper - Dynamic discovery from metadata tables
# Connects to local databases and finds all schemas and server/schema pairs

echo === Q Replication Configurations across ALL local databases ===
echo Current running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo 

# Source profile
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
fi

# Local databases only
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

  TMP_SCHEMAS=/tmp/qrep_schemas_$$.txt
  db2 -x "SELECT DISTINCT TABSCHEMA 
          FROM SYSCAT.TABLES 
          WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
          AND TABSCHEMA NOT LIKE 'SYS%' 
          ORDER BY TABSCHEMA" > "$TMP_SCHEMAS" 2>&1

  echo DEBUG Raw catalog query for $DB:
  cat "$TMP_SCHEMAS"
  echo 

  # Robust parsing
  SCHEMAS=()
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ ^[A-Z][A-Z0-9_]+$ ]]; then
      SCHEMAS+=("$line")
    fi
  done < "$TMP_SCHEMAS"

  if [ ${#SCHEMAS[@]} -eq 0 ]; then
    echo   No Q Replication control tables found in this database.
    rm -f "$TMP_SCHEMAS"
    db2 terminate > /dev/null 2>&1
    continue
  fi

  echo   Found Q Rep schemas: ${SCHEMAS[*]}

  for SCHEMA in "${SCHEMAS[@]}"; do
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
echo === Done ===

Save as qrep.sh, chmod +x qrep.sh, ./qrep.sh

This is dynamic, uses while read for parsing, and keeps connection per database. Run it - the DEBUG will show the schemas and it will dump the pairs.
