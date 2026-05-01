#!/bin/bash
# Q Replication Config Dumper - FINAL FIXED VERSION
# Uses metadata tables only (IBMQREP_SENDQUEUES / IBMQREP_RECVQUEUES)
# Works even when ASN processes are down for maintenance
# Fixed sub-shell connection loss (SQL1024N / integer expression expected)

echo === Q Replication Configurations across ALL databases in this instance ===
echo Current running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo Running ASN processes count: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo 

# Source DB2 profile explicitly (fixes environment issues in loops/scripts)
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
  echo DB2 profile sourced successfully
else
  echo WARNING: Could not find DB2 profile at ~/sqllib/db2profile
fi

# Get list of all LOCAL (Indirect) databases
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo ERROR: No local databases found in DB directory.
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
    echo   Failed to connect to $DB check permissions / instance
    continue
  fi

  # Quick connection test
  if ! db2 -x "VALUES 1" > /dev/null 2>&1; then
    echo   Connection test failed for $DB
    db2 terminate > /dev/null 2>&1
    continue
  fi

  echo   Checking Q Rep control tables...

  # Use temp file to avoid sub-shell connection loss
  TMPFILE=/tmp/qrep_schemas_$$.txt
  db2 -x "SELECT DISTINCT TABSCHEMA 
          FROM SYSCAT.TABLES 
          WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
          AND TABSCHEMA NOT LIKE 'SYS%' 
          ORDER BY TABSCHEMA" > "$TMPFILE" 2>&1

  SCHEMAS=$(grep -E '^[A-Z][A-Z0-9_]+$' "$TMPFILE" | sort -u || echo "")

  if [ -z "$SCHEMAS" ]; then
    echo   No Q Replication control tables found in this database.
    rm -f "$TMPFILE"
    db2 terminate > /dev/null 2>&1
    continue
  fi

  for SCHEMA in $SCHEMAS; do
    echo   Q Rep schema: $SCHEMA

    # SENDQUEUES = Apply-side
    TMP_COUNT=/tmp/qrep_count_$$.txt
    db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
            WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_SENDQUEUES'" > "$TMP_COUNT" 2>&1
    SEND_COUNT=$(grep -o '[0-9]*' "$TMP_COUNT" | head -1 || echo "0")
    rm -f "$TMP_COUNT"

    if [ "$SEND_COUNT" = "1" ]; then
      echo     APPLY config IBMQREP_SENDQUEUES:
      db2 -x "SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA 
              FROM $SCHEMA.IBMQREP_SENDQUEUES;"
    fi

    # RECVQUEUES = Capture-side
    db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
            WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_RECVQUEUES'" > "$TMP_COUNT" 2>&1
    RECV_COUNT=$(grep -o '[0-9]*' "$TMP_COUNT" | head -1 || echo "0")
    rm -f "$TMP_COUNT"

    if [ "$RECV_COUNT" = "1" ]; then
      echo     CAPTURE config IBMQREP_RECVQUEUES:
      db2 -x "SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA 
              FROM $SCHEMA.IBMQREP_RECVQUEUES;"
    fi
  done

  rm -f "$TMPFILE"
  db2 terminate > /dev/null 2>&1
done

echo 
echo === Summary ===
echo ASN processes running: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo All server/schema pairs needed to start ASN processes are now listed above from the control tables.
echo Use these exact values in your asnqcap / asnqapp start commands.
echo === Done. All Q Rep configs dumped. ===
