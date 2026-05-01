#!/bin/bash
# Q Replication Config Dumper - Clean & Robust Version

echo "=== Q Replication Configurations across ALL local databases ==="
echo "Current running ASN processes for reference:"
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo

# Source DB2 profile
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
fi

# Get local databases
DBS=$(db2 list db directory | awk '/Indirect/{getline;getline;getline;getline; print $4}' | sort -u)

if [ -z "$DBS" ]; then
  echo "ERROR: No local databases found."
  exit 1
fi

echo "Found local databases: $DBS"
echo

for DB in $DBS; do
  echo "--------------------------------------------------"
  echo "DATABASE: $DB"

  db2 connect to "$DB" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "  Failed to connect to $DB"
    continue
  fi

  # Get schemas containing Q Rep tables
  SCHEMAS=$(db2 -x "
    SELECT DISTINCT RTRIM(TABSCHEMA)
    FROM SYSCAT.TABLES
    WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES')
      AND TABSCHEMA NOT LIKE 'SYS%'
    ORDER BY TABSCHEMA
  ")

  echo "DEBUG: Raw schema query result:"
  echo "$SCHEMAS"
  echo

  if [ -z "$SCHEMAS" ]; then
    echo "  No Q Replication control tables found in this database."
    db2 terminate > /dev/null 2>&1
    continue
  fi

  echo "  Found Q Rep schemas: $SCHEMAS"

  for SCHEMA in $SCHEMAS; do
    echo "  Q Rep schema: $SCHEMA"

    # Check SENDQUEUES table
    SEND_COUNT=$(db2 -x "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_SENDQUEUES'
    ")

    if [ "$SEND_COUNT" = "1" ]; then
      echo "    APPLY config (IBMQREP_SENDQUEUES):"
      db2 -x "
        SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
        FROM $SCHEMA.IBMQREP_SENDQUEUES
      "
    fi

    # Check RECVQUEUES table
    RECV_COUNT=$(db2 -x "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_RECVQUEUES'
    ")

    if [ "$RECV_COUNT" = "1" ]; then
      echo "    CAPTURE config (IBMQREP_RECVQUEUES):"
      db2 -x "
        SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
        FROM $SCHEMA.IBMQREP_RECVQUEUES
      "
    fi

  done

  db2 terminate > /dev/null 2>&1
done

echo
echo "=== Summary ==="
echo "All capture_server/capture_schema/apply_server/apply_schema pairs are listed above."
echo "=== Done ==="
